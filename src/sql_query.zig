const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");

const models = @import("models.zig");

pub const captures = struct {
    pub fn add(db: *sqlite.Db, allocator: Allocator, model: *models.Capture) !void {
        const query =
            \\INSERT INTO
            \\captures(id, bin, method, remote_addr, headers, query, body, time)
            \\VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.execAlloc(allocator, .{}, model.*);

        model.id = db.getLastInsertRowID();
    }

    pub fn fetchOrderedAsc(db: *sqlite.Db, allocator: Allocator, bin: i64, options: models.PageParams) ![]models.Capture {
        const query =
            \\SELECT id, bin, method, remote_addr, headers, query, body, time
            \\FROM captures
            \\WHERE bin = ?
            \\ORDER BY time ASC
            \\LIMIT $limit OFFSET $offset
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.all(models.Capture, allocator, .{}, .{ .bin = bin, .limit = options.limit, .offset = options.offset });
    }

    pub fn fetchOrderedDesc(db: *sqlite.Db, allocator: Allocator, bin: i64, options: models.PageParams) ![]models.Capture {
        const query =
            \\SELECT id, bin, method, remote_addr, headers, query, body, time
            \\FROM captures
            \\WHERE bin = ?
            \\ORDER BY time DESC
            \\LIMIT $limit OFFSET $offset
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.all(models.Capture, allocator, .{}, .{ .bin = bin, .limit = options.limit, .offset = options.offset });
    }

    pub fn get(db: *sqlite.Db, allocator: Allocator, bin: i64, capture: i64) !?models.Capture {
        const query =
            \\SELECT id, bin, method, remote_addr, headers, query, body, time
            \\FROM captures
            \\WHERE id = ? AND bin = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        return stmt.oneAlloc(models.Capture, allocator, .{}, .{ .id = capture, .bin = bin });
    }

    pub fn delete(db: *sqlite.Db, bin: i64, capture: i64) !void {
        const query =
            \\DELETE FROM captures WHERE id = ? AND bin = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.exec(.{}, .{ .id = capture, .bin = bin });
    }

    pub fn clear(db: *sqlite.Db, bin: i64) !void {
        const query =
            \\DELETE FROM captures WHERE bin = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.exec(.{}, .{ .bin = bin });
    }

    pub fn count(db: *sqlite.Db, bin: i64) !usize {
        const query =
            \\SELECT COUNT(*) FROM captures WHERE bin = ?
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        const result = try stmt.one(usize, .{}, .{ .bin = bin });
        return result.?;
    }
};

pub const bins = struct {
    pub fn addOrUpdate(db: *sqlite.Db, allocator: Allocator, model: *models.Bin) !void {
        const query =
            \\INSERT OR REPLACE INTO
            \\bins(id, name, body, query, header, ips, methods, responding)
            \\VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.execAlloc(allocator, .{}, model.*);

        if (model.id == null) {
            model.id = db.getLastInsertRowID();
        }
    }

    pub fn get(db: *sqlite.Db, allocator: Allocator, name: []const u8) !?models.Bin {
        const query =
            \\SELECT id, name, body, query, header, ips, methods, responding
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

    pub fn fetch(db: *sqlite.Db, allocator: Allocator, options: models.PageParams) ![]models.Bin {
        const query =
            \\SELECT id, name, body, query, header, ips, methods, responding
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
