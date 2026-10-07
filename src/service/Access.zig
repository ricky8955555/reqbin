const std = @import("std");

const httpz = @import("httpz");
const sqlite = @import("sqlite");
const zdt = @import("zdt");

const db = @import("../core/db.zig");
const origin = @import("../utils/origin.zig");
const models = @import("../core/models.zig");
const network = @import("../utils/network.zig");
const proxy = @import("../utils/proxy.zig");
const Template = @import("../utils/Template.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    db: *sqlite.Db,

    trusted_proxies: []const network.Network,
};

const RenderContext = struct {
    request: *httpz.Request,
    subpath: []const u8,

    fn print(context: *const anyopaque, writer: *std.Io.Writer, name: []const u8) anyerror!bool {
        const self: *const RenderContext = @ptrCast(@alignCast(context));
        var split = std.mem.splitScalar(u8, name, '.');

        const first = split.next().?;
        const optional_second = split.next();
        if (split.next() != null) return false;

        if (std.mem.eql(u8, first, "method")) {
            if (optional_second != null) return false;
            if (self.request.method == .OTHER) {
                try writer.writeAll(self.request.method_string);
            } else {
                try writer.writeAll(@tagName(self.request.method));
            }
        } else if (std.mem.eql(u8, first, "body")) {
            if (optional_second != null) return false;
            if (self.request.body()) |body| {
                try writer.writeAll(body);
            }
        } else if (std.mem.eql(u8, first, "headers")) {
            if (optional_second) |second| {
                const value = self.request.header(second) orelse return false;
                try writer.writeAll(value);
            } else {
                var it = self.request.headers.iterator();
                while (it.next()) |header| {
                    try writer.print("{s}: {s}", .{ header.key, header.value });
                }
            }
        } else if (std.mem.eql(u8, first, "query")) {
            var query = try self.request.query();

            if (optional_second) |second| {
                const value = query.get(second) orelse return false;
                try writer.writeAll(value);
            } else {
                var i: usize = 0;
                var it = query.iterator();
                while (it.next()) |kv| : (i += 1) {
                    try writer.print("{s}={s}", .{ kv.key, kv.value });
                    if (i != it.keys.len) {
                        try writer.writeByte('&');
                    }
                }
            }
        } else if (std.mem.eql(u8, first, "cookies")) {
            var cookies = self.request.cookies();
            if (optional_second) |second| {
                const value = cookies.get(second) orelse return false;
                try writer.writeAll(value);
            } else {
                try writer.writeAll(cookies.header);
            }
        } else if (std.mem.eql(u8, first, "subpath")) {
            if (optional_second != null) return false;
            try writer.writeAll(self.subpath);
        } else {
            return false;
        }

        return true;
    }

    fn variables(self: *const RenderContext) Template.Variables {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .print = print,
            },
        };
    }
};

server: httpz.Server(*const Context),

const Bin = @This();

pub fn init(ctx: *const Context, config: httpz.Config) !Bin {
    var app = Bin{
        .server = undefined,
    };

    app.server = try httpz.Server(*const Context).init(ctx.io, ctx.allocator, config, ctx);

    var router = try app.server.router(.{});

    router.all("/*", captureAccess, .{});

    return app;
}

pub fn listen(self: *Bin) !std.Thread {
    return self.server.listenInNewThread();
}

pub fn deinit(self: *Bin) void {
    self.server.deinit();
}

fn respondError(res: *httpz.Response, status: std.http.Status) void {
    res.setStatus(status);
    res.body = status.phrase() orelse "";
    res.content_type = .TEXT;
}

pub fn renderResponse(template: Template, context: *const RenderContext, writer: *std.Io.Writer) !void {
    const variables = context.variables();
    try template.render(writer, variables, .{});
}

fn captureAccess(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const params = std.mem.trimStart(u8, req.url.path, "/");
    const slash_idx = std.mem.indexOfScalar(u8, params, '/') orelse params.len;
    const bin_name = params[0..slash_idx];
    const subpath = params[slash_idx..];

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const bin = try db.bins.get(ctx.db, allocator, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    if (bin.subpath == .reject and subpath.len != 0 and !std.mem.eql(u8, subpath, "/")) {
        respondError(res, .not_found);
        return;
    }

    const remote_addr = origin.retrieveRemoteAddr(req, ctx.trusted_proxies);
    const remote_addr_str = remote_addr: {
        var buf: [64]u8 = undefined;
        break :remote_addr std.fmt.bufPrint(&buf, "{f}", .{remote_addr}) catch unreachable;
    };

    if (bin.ips) |ips| {
        for (ips.value) |net| {
            if (net.value.isHost(remote_addr)) break;
        } else {
            respondError(res, .forbidden);
            return;
        }
    }
    if (bin.methods) |methods| {
        _ = std.mem.indexOfScalar(httpz.Method, methods.value, req.method) orelse {
            respondError(res, .method_not_allowed);
            return;
        };
    }

    var capture = models.Capture{
        .bin = bin.id.?,
        .method = @tagName(req.method),
        .remote_addr = remote_addr_str,
        .headers = if (bin.headers) .{ .value = .{ .httpz = req.headers.* } } else null,
        .query = if (bin.query) .{ .value = .{ .httpz = (try req.query()).* } } else null,
        .subpath = if (bin.subpath == .accept) subpath else null,
        .body = if (bin.body) req.body() else null,
        .time = .{ .value = zdt.Datetime.nowUTC(ctx.io) },
    };

    try db.captures.add(ctx.db, arena.allocator(), &capture);

    switch (bin.responding.value) {
        .template => |template| {
            const writer = res.writer();

            const parsed = Template.parse(ctx.allocator, template.body) catch |err| {
                try writer.print("Failed to parse template: {any}", .{err});
                res.setStatus(.internal_server_error);
                res.content_type = .TEXT;
                return;
            };
            defer parsed.deinit(ctx.allocator);

            const context = RenderContext{ .request = req, .subpath = subpath };

            renderResponse(parsed, &context, writer) catch |err| {
                try writer.print("Failed to render template: {any}", .{err});
                res.setStatus(.internal_server_error);
                res.content_type = .TEXT;
                return;
            };

            res.status = template.status;

            var it = template.headers.value.iterator();

            while (it.next()) |header| {
                try res.headerOpts(
                    header.key,
                    header.value,
                    .{ .dupe_name = true, .dupe_value = true },
                );
            }
        },
        .capture => {
            try res.json(capture, .{});
        },
        .proxy => |options| {
            proxy.proxy(allocator, ctx.io, req, res, .{
                .base_url = options.target,
                .path = .{ .overwrite = subpath },
            }) catch |err| {
                var writer = res.writer();
                try writer.print("Failed to proxy request: {any}", .{err});

                res.setStatus(.internal_server_error);
                res.content_type = .TEXT;

                return;
            };
        },
    }
}
