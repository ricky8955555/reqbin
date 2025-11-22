const std = @import("std");

const sqlite = @import("sqlite");

const models = @import("models.zig");

pub const requests = struct {
    pub fn add(db: *sqlite.Db, allocator: std.mem.Allocator, model: *models.Request) !void {
        const query =
            \\INSERT INTO requests(id, bin, method, remote_addr, headers, query, body, time) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.execAlloc(allocator, .{}, model.*);

        model.id = db.getLastInsertRowID();
    }

    pub fn fetchOrdered(db: *sqlite.Db, allocator: std.mem.Allocator, bin: i64, options: models.PageParams) ![]models.Request {
        const query =
            \\SELECT id, bin, method, remote_addr, headers, query, body, time FROM requests
            \\WHERE bin = ?
            \\ORDER BY time
            \\LIMIT $limit OFFSET $offset
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.all(models.Request, allocator, .{}, .{ .bin = bin, .limit = options.limit, .offset = options.offset });
    }

    pub fn clear(db: *sqlite.Db, bin: i64) !void {
        const query =
            \\DELETE FROM requests WHERE bin = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.exec(.{}, .{ .bin = bin });
    }

    pub fn count(db: *sqlite.Db, bin: i64) !usize {
        const query =
            \\SELECT COUNT(*) FROM requests WHERE bin = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        const result = try stmt.one(usize, .{}, .{ .bin = bin });
        return result.?;
    }
};

pub const bins = struct {
    pub fn addOrUpdate(db: *sqlite.Db, allocator: std.mem.Allocator, model: *models.Bin) !void {
        const query =
            \\INSERT OR REPLACE INTO
            \\bins(id, name, body, query, header, ips, methods, content_type)
            \\VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.execAlloc(allocator, .{}, model.*);

        if (model.id == null) {
            model.id = db.getLastInsertRowID();
        }
    }

    pub fn get(db: *sqlite.Db, allocator: std.mem.Allocator, name: []const u8) !?models.Bin {
        const query =
            \\SELECT id, name, body, query, header, ips, methods, content_type
            \\FROM bins
            \\WHERE name = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.oneAlloc(models.Bin, allocator, .{}, .{ .name = name });
    }

    pub fn getId(db: *sqlite.Db, name: []const u8) !?i64 {
        const query =
            \\SELECT id FROM bins WHERE name = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.one(i64, .{}, .{ .name = name });
    }

    pub fn fetch(db: *sqlite.Db, allocator: std.mem.Allocator, options: models.PageParams) ![]models.Bin {
        const query =
            \\SELECT id, name, body, query, header, ips, methods, content_type
            \\FROM bins
            \\LIMIT $limit OFFSET $offset
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.all(models.Bin, allocator, .{}, .{ .limit = options.limit, .offset = options.offset });
    }

    pub fn delete(db: *sqlite.Db, name: []const u8) !void {
        const query =
            \\DELETE FROM bins WHERE name = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.exec(.{}, .{ .name = name });
    }

    pub fn count(db: *sqlite.Db) !usize {
        const query =
            \\SELECT COUNT(*) FROM bins
        ;

        const result = try db.one(usize, query, .{}, .{});
        return result.?;
    }
};
