const std = @import("std");

const httpz = @import("httpz");
const sqlite = @import("sqlite");

const db = @import("../core/db.zig");
const models = @import("../core/models.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,

    db: *sqlite.Db,

    auth: ?[]const u8 = null,
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

    fn isAuthorized(self: *const Authorization, req: *httpz.Request) !bool {
        const scheme = "Basic ";
        const authorization = req.header("authorization") orelse return false;

        if (!std.mem.startsWith(u8, authorization, scheme)) return false;

        const encoded = authorization[scheme.len..];

        const decoder = std.base64.standard.Decoder;

        const bufsize = decoder.calcSizeForSlice(encoded) catch return false;
        if (bufsize != self.config.credential.len) return false;

        const got = try self.allocator.alloc(u8, bufsize);
        defer self.allocator.free(got);

        decoder.decode(got, encoded) catch return false;

        if (!std.mem.eql(u8, got, self.config.credential)) return false;

        return true;
    }

    pub fn execute(self: *const Authorization, req: *httpz.Request, res: *httpz.Response, executor: anytype) !void {
        if (!try self.isAuthorized(req)) {
            respondError(res, .unauthorized);
        }

        return executor.next();
    }
};

server: httpz.Server(*const Context),
_middlewares: []const httpz.Middleware(*const Context),

const App = @This();

pub fn init(ctx: *const Context, config: httpz.Config) !App {
    var app = App{
        .server = undefined,
        ._middlewares = undefined,
    };

    app.server = try httpz.Server(*const Context).init(ctx.io, ctx.allocator, config, ctx);

    app._middlewares = middlewares: {
        if (ctx.auth) |credential| {
            break :middlewares try ctx.allocator.dupe(httpz.Middleware(*const Context), &.{
                try app.server.middleware(Authorization, .{ .credential = credential }),
            });
        } else {
            break :middlewares &.{};
        }
    };

    var router = try app.server.router(.{ .middlewares = app._middlewares });

    router.get("/bins", fetchBins, .{});
    router.put("/bins", createOrUpdateBin, .{});
    router.get("/bins/:bin", inspectBin, .{});
    router.delete("/bins/:bin", deleteBin, .{});
    router.get("/bins/:bin/captures", viewBin, .{});
    router.delete("/bins/:bin/captures", clearBin, .{});
    router.get("/bins/:bin/captures/:capture", inspectCapture, .{});
    router.delete("/bins/:bin/captures/:capture", deleteCapture, .{});

    return app;
}

pub fn listen(self: *App) !std.Thread {
    return self.server.listenInNewThread();
}

pub fn deinit(self: *App) void {
    const allocator = self.server.handler.allocator;
    allocator.free(self._middlewares);

    self.server.deinit();
}

fn respondError(res: *httpz.Response, status: std.http.Status) void {
    res.setStatus(status);
    res.body = status.phrase() orelse "";
    res.content_type = .TEXT;
}

fn viewBin(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    const bin = try db.bins.getId(ctx.db, bin_name) orelse {
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

    const total = try db.captures.count(ctx.db, bin);
    const captures = captures: {
        if (query.has("desc")) {
            break :captures try db.captures.fetchOrderedDesc(ctx.db, arena.allocator(), bin, options);
        } else {
            break :captures try db.captures.fetchOrderedAsc(ctx.db, arena.allocator(), bin, options);
        }
    };
    const page = models.Page(models.Capture){ .total = total, .count = captures.len, .data = captures };

    try res.json(page, .{});
}

fn fetchBins(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    const options = models.PageParams.parseFromStringKeyValue(query) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const total = try db.bins.count(ctx.db);
    const bins = try db.bins.fetch(ctx.db, arena.allocator(), options);
    const page = models.Page(models.Bin){ .total = total, .count = bins.len, .data = bins };

    try res.json(page, .{});
}

fn createOrUpdateBin(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    var bin = req.json(models.Bin) catch null orelse {
        respondError(res, .bad_request);
        return;
    };

    bin.validate() catch |err| {
        res.body = switch (err) {
            error.InvalidName => "Name is not valid.",
        };
        res.setStatus(.bad_request);
        res.content_type = .TEXT;
        return;
    };

    const old_id = try db.bins.getId(ctx.db, bin.name);
    if (old_id != null and old_id != bin.id) {
        respondError(res, .conflict);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    try db.bins.addOrUpdate(ctx.db, arena.allocator(), &bin);

    try res.json(bin, .{});
}

fn inspectBin(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const bin = try db.bins.get(ctx.db, arena.allocator(), bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    try res.json(bin, .{});
}

fn deleteBin(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;

    try db.bins.delete(ctx.db, bin_name);

    res.setStatus(.no_content);
}

fn clearBin(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;
    const bin = try db.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    try db.captures.clear(ctx.db, bin);

    res.setStatus(.no_content);
}

fn inspectCapture(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;
    const capture_id = std.fmt.parseInt(i64, req.param("capture").?, 10) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    const bin = try db.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    const capture = try db.captures.get(ctx.db, arena.allocator(), bin, capture_id) orelse {
        respondError(res, .not_found);
        return;
    };

    try res.json(capture, .{});
}

fn deleteCapture(ctx: *const Context, req: *httpz.Request, res: *httpz.Response) !void {
    const bin_name = req.param("bin").?;
    const capture = std.fmt.parseInt(i64, req.param("capture").?, 10) catch {
        respondError(res, .unprocessable_entity);
        return;
    };

    const bin = try db.bins.getId(ctx.db, bin_name) orelse {
        respondError(res, .not_found);
        return;
    };

    try db.captures.delete(ctx.db, bin, capture);

    res.setStatus(.no_content);
}
