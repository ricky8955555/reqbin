const std = @import("std");

const httpz = @import("httpz");
const sqlite = @import("sqlite");
const zdt = @import("zdt");

const models = @import("models.zig");
const sql_query = @import("sql_query.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    db: *sqlite.Db,
    auth: ?[]const u8 = null,
};

server: httpz.Server(*Context),

const App = @This();

pub fn init(ctx: *Context, config: httpz.Config) !App {
    var app = App{ .server = undefined };
    app.server = try httpz.Server(*Context).init(ctx.allocator, config, ctx);

    var router = try app.server.router(.{});
    router.all("/access/:bin", catchRequest, .{});
    router.get("/view/:bin", viewBin, .{});
    router.get("/bins", fetchBins, .{});
    router.put("/bins", createOrUpdateBin, .{});
    router.get("/bins/:bin", inspectBin, .{});
    router.delete("/bins/:bin", deleteBin, .{});

    try sql_query.bins.initTable(ctx.db);
    try sql_query.requests.initTable(ctx.db);

    return app;
}

pub fn listen(self: *App) !void {
    try self.server.listen();
}

pub fn deinit(self: *App) void {
    self.server.deinit();
}

fn respondError(res: *httpz.Response, status: std.http.Status) void {
    res.setStatus(status);
    res.body = status.phrase() orelse "";
    res.content_type = .TEXT;
}

fn catchRequest(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const bin = try sql_query.bins.get(ctx.db, allocator, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    var addr_buf: [64]u8 = undefined;
    const address = std.fmt.bufPrint(&addr_buf, "{f}", .{req.address}) catch unreachable;

    if (bin.ips) |ips| {
        for (ips.value) |ip| {
            const pos = std.mem.lastIndexOfScalar(u8, address, ':').?;
            const remote_ip = address[0..pos];

            if (std.mem.eql(u8, ip.value, remote_ip)) {
                break;
            }
        } else {
            respondError(res, .forbidden);
            return;
        }
    }

    if (bin.methods) |methods| {
        for (methods.value) |method| {
            if (method == req.method) {
                break;
            }
        } else {
            respondError(res, .method_not_allowed);
            return;
        }
    }

    const query = if (bin.query) models.StringKeyValue{ .map = (try req.query()).* } else null;
    const headers = if (bin.headers) models.StringKeyValue{ .map = req.headers.* } else null;

    const body = if (bin.body) body: {
        const body = models.Body.parseFromRequest(req, bin.content_type) catch {
            respondError(res, .bad_request);
            return;
        };
        break :body body;
    } else null;

    var model = models.Request{
        .bin = bin.id.?,
        .method = @tagName(req.method),
        .remote_addr = address,
        .headers = headers,
        .query = query,
        .body = body,
        .time = .{ .value = zdt.Datetime.nowUTC() },
    };

    try sql_query.requests.add(ctx.db, arena.allocator(), &model);

    try res.json(model, .{});
}

fn authorize(ctx: *Context, req: *httpz.Request) !bool {
    if (ctx.auth) |auth| {
        const scheme = "Basic ";
        const optional_authorization = req.header("authorization");

        if (optional_authorization) |authorization| {
            if (std.mem.startsWith(u8, authorization, scheme)) {
                const enc_cred = authorization[scheme.len..];

                const decoder = std.base64.url_safe.Decoder;

                const bufsize = decoder.calcSizeForSlice(enc_cred) catch return false;
                const cred = try ctx.allocator.alloc(u8, bufsize);
                defer ctx.allocator.free(cred);

                decoder.decode(cred, enc_cred) catch return false;

                if (!std.mem.eql(u8, cred, auth)) return false;

                return true;
            }
        }

        return false;
    } else {
        return true;
    }
}

fn viewBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    if (!try authorize(ctx, req)) {
        respondError(res, .unauthorized);
        return;
    }

    const bin_name = req.param("bin").?;

    const bin = try sql_query.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    const query = try req.query();
    const options = models.FetchOptions.parseFromStringKeyValue(query) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const requests = try sql_query.requests.fetchOrdered(ctx.db, arena.allocator(), bin, options);

    try res.json(requests, .{});
}

fn fetchBins(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    if (!try authorize(ctx, req)) {
        respondError(res, .unauthorized);
        return;
    }

    const query = try req.query();
    const options = models.FetchOptions.parseFromStringKeyValue(query) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const bins = try sql_query.bins.fetch(ctx.db, arena.allocator(), options);

    try res.json(bins, .{});
}

fn createOrUpdateBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    if (!try authorize(ctx, req)) {
        respondError(res, .unauthorized);
        return;
    }

    var model = req.json(models.Bin) catch null orelse {
        respondError(res, .bad_request);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    try sql_query.bins.addOrUpdate(ctx.db, arena.allocator(), &model);

    try res.json(model, .{});
}

fn inspectBin(ctx: *Context, req: *httpz.Request, res: *httpz.Response) !void {
    if (!try authorize(ctx, req)) {
        respondError(res, .unauthorized);
        return;
    }

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
    if (!try authorize(ctx, req)) {
        respondError(res, .unauthorized);
        return;
    }

    const bin_name = req.param("bin").?;

    try sql_query.bins.delete(ctx.db, bin_name);
}
