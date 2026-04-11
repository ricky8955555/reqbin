const builtin = @import("builtin");
const std = @import("std");

const httpz = @import("httpz");
const sqlite = @import("sqlite");
const zdt = @import("zdt");

const httpz_utils = @import("httpz_utils.zig");
const models = @import("models.zig");
const network = @import("network.zig");
const response_template = @import("response_template.zig");
const sql_query = @import("sql_query.zig");
const Template = @import("Template.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    db: *sqlite.Db,

    auth: ?[]const u8 = null,

    trusted_proxies: []const network.Network,
};

const Authorization = struct {
    pub const Config = struct {
        credential: []const u8,
    };

    config: Config,
    allocator: std.mem.Allocator,

    pub fn init(config: Config, mw_config: httpz.MiddlewareConfig) !Authorization {
        return .{ .config = config, .allocator = mw_config.allocator };
    }

    pub fn execute(self: *const Authorization, req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
        const authorized = authorized: {
            const scheme = "Basic ";
            const optional_authorization = req.header("authorization");

            if (optional_authorization) |authorization| {
                if (std.mem.startsWith(u8, authorization, scheme)) {
                    const encoded = authorization[scheme.len..];

                    const decoder = std.base64.standard.Decoder;

                    const bufsize = decoder.calcSizeForSlice(encoded) catch break :authorized false;
                    if (bufsize != self.config.credential.len) break :authorized false;

                    const got = try self.allocator.alloc(u8, bufsize);
                    defer self.allocator.free(got);

                    decoder.decode(got, encoded) catch break :authorized false;

                    if (!std.mem.eql(u8, got, self.config.credential)) break :authorized false;

                    break :authorized true;
                }
            }

            break :authorized false;
        };

        if (!authorized) {
            respondError(res, .unauthorized);
        } else {
            return executor.next();
        }
    }
};

server: httpz.Server(*Context),
_api_middlewares: []const httpz.Middleware(*Context),

const App = @This();

const access_path_prefix = "/access";

pub fn init(ctx: *Context, config: httpz.Config) !App {
    var app = App{
        .server = undefined,
        ._api_middlewares = undefined,
    };

    app.server = try httpz.Server(*Context).init(ctx.allocator, config, ctx);

    var router = try app.server.router(.{});

    router.all(access_path_prefix ++ "/*", captureAccess, .{});
    router.get("/", serveDashboard, .{});

    app._api_middlewares = middlewares: {
        if (ctx.auth) |credential| {
            break :middlewares try ctx.allocator.dupe(httpz.Middleware(*Context), &.{
                try app.server.middleware(Authorization, .{ .credential = credential }),
            });
        } else {
            break :middlewares &.{};
        }
    };

    var api_router = router.group(
        "/api",
        .{ .middlewares = app._api_middlewares },
    );

    api_router.get("/bins", fetchBins, .{});
    api_router.put("/bins", createOrUpdateBin, .{});
    api_router.get("/bins/:bin", inspectBin, .{});
    api_router.delete("/bins/:bin", deleteBin, .{});
    api_router.get("/bins/:bin/captures", viewBin, .{});
    api_router.delete("/bins/:bin/captures", clearBin, .{});
    api_router.get("/bins/:bin/captures/:capture", inspectCapture, .{});
    api_router.delete("/bins/:bin/captures/:capture", deleteCapture, .{});

    return app;
}

pub fn listen(self: *App) !void {
    try self.server.listen();
}

pub fn deinit(self: *App) void {
    const allocator = self.server.handler.allocator;
    allocator.free(self._api_middlewares);

    self.server.deinit();
}

fn respondError(res: *httpz.Response, status: std.http.Status) void {
    res.setStatus(status);
    res.body = status.phrase() orelse "";
    res.content_type = .TEXT;
}

fn captureAccess(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    std.debug.assert(std.mem.eql(u8, req.url.path[0..access_path_prefix.len], access_path_prefix));

    const params = std.mem.trimStart(u8, req.url.path[access_path_prefix.len..], "/");
    const slash_idx = std.mem.indexOfScalar(u8, params, '/') orelse params.len;
    const bin_name = params[0..slash_idx];
    const subpath = params[slash_idx..];

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const bin = try sql_query.bins.get(ctx.db, allocator, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    if (bin.subpath == .reject and subpath.len != 0 and !std.mem.eql(u8, subpath, "/")) {
        respondError(res, .not_found);
        return;
    }

    const remote_addr = httpz_utils.retrieveRemoteAddr(req, ctx.trusted_proxies);
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
        for (methods.value) |method| {
            if (method == req.method) break;
        } else {
            respondError(res, .method_not_allowed);
            return;
        }
    }

    var capture = models.Capture{
        .bin = bin.id.?,
        .method = @tagName(req.method),
        .remote_addr = remote_addr_str,
        .headers = if (bin.headers) .{ .value = .{ .httpz = req.headers.* } } else null,
        .query = if (bin.query) .{ .value = .{ .httpz = (try req.query()).* } } else null,
        .subpath = if (bin.subpath == .accept) subpath else null,
        .body = if (bin.body) req.body() else null,
        .time = .{ .value = zdt.Datetime.nowUTC() },
    };

    try sql_query.captures.add(ctx.db, arena.allocator(), &capture);

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

            const context = response_template.Context{ .request = req, .subpath = subpath };

            response_template.render(parsed, &context, writer) catch |err| {
                try writer.print("Failed to render template: {any}", .{err});
                res.setStatus(.internal_server_error);
                res.content_type = .TEXT;
                return;
            };

            res.status = template.status;

            var it = template.headers.value.iterator();

            while (it.next()) |header| {
                res.header(header.key, header.value);
            }
        },
        .capture => {
            try res.json(capture, .{});
        },
    }
}

fn isValidBinName(name: []const u8) bool {
    if (name.len == 0) return false;

    for (name) |ch| {
        switch (ch) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => continue,
            else => return false,
        }
    }

    return true;
}

fn viewBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    const bin = try sql_query.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    const query = try req.query();
    const options = models.PageParams.parseFromStringKeyValue(query) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const total = try sql_query.captures.count(ctx.db, bin);
    const captures = captures: {
        if (query.has("desc")) {
            break :captures try sql_query.captures.fetchOrderedDesc(ctx.db, arena.allocator(), bin, options);
        } else {
            break :captures try sql_query.captures.fetchOrderedAsc(ctx.db, arena.allocator(), bin, options);
        }
    };
    const page = models.Page(models.Capture){ .total = total, .count = captures.len, .data = captures };

    try res.json(page, .{});
}

fn fetchBins(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    const options = models.PageParams.parseFromStringKeyValue(query) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const total = try sql_query.bins.count(ctx.db);
    const bins = try sql_query.bins.fetch(ctx.db, arena.allocator(), options);
    const page = models.Page(models.Bin){ .total = total, .count = bins.len, .data = bins };

    try res.json(page, .{});
}

fn createOrUpdateBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    var bin = req.json(models.Bin) catch null orelse {
        respondError(res, .bad_request);
        return;
    };

    if (!isValidBinName(bin.name)) {
        res.setStatus(.bad_request);
        res.body = "Name is not valid.";
        res.content_type = .TEXT;
        return;
    }

    const old_id = try sql_query.bins.getId(ctx.db, bin.name);
    if (old_id != null and old_id != bin.id) {
        respondError(res, .conflict);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    try sql_query.bins.addOrUpdate(ctx.db, arena.allocator(), &bin);

    try res.json(bin, .{});
}

fn inspectBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const bin = try sql_query.bins.get(ctx.db, arena.allocator(), bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    try res.json(bin, .{});
}

fn deleteBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    try sql_query.bins.delete(ctx.db, bin_name);

    res.setStatus(.no_content);
}

fn clearBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;
    const bin = try sql_query.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    try sql_query.captures.clear(ctx.db, bin);

    res.setStatus(.no_content);
}

fn inspectCapture(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;
    const capture_id = std.fmt.parseInt(i64, req.param("capture").?, 10) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const bin = try sql_query.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    const capture = try sql_query.captures.get(ctx.db, arena.allocator(), bin, capture_id) orelse {
        respondError(res, .not_found);
        return;
    };

    try res.json(capture, .{});
}

fn deleteCapture(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;
    const capture = std.fmt.parseInt(i64, req.param("capture").?, 10) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    const bin = try sql_query.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    try sql_query.captures.delete(ctx.db, bin, capture);

    res.setStatus(.no_content);
}

fn serveDashboard(_: *Context, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .HTML;

    if (builtin.mode == .Debug) {
        const file = try std.fs.cwd().openFile("assets/dashboard.html", .{ .mode = .read_only });

        var reader_buffer: [4096]u8 = undefined;
        var reader = file.reader(&reader_buffer);

        _ = try reader.interface.streamRemaining(res.writer());
    } else {
        res.body = @embedFile("dashboard");
    }
}
