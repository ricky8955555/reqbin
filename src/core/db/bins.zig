const std = @import("std");
const Allocator = std.mem.Allocator;

const sqlite = @import("sqlite");

const models = @import("../models.zig");

pub fn addOrUpdate(db: *sqlite.Db, allocator: Allocator, model: *models.Bin) !void {
    const query =
        \\INSERT OR REPLACE INTO
        \\bins(id, name, body, query, header, subpath, ips, methods, responding)
        \\VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        \\SELECT id, name, body, query, header, subpath, ips, methods, responding
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
        \\SELECT id, name, body, query, header, subpath, ips, methods, responding
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
