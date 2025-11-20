const std = @import("std");

const sqlite = @import("sqlite");

const models = @import("models.zig");

pub const requests = struct {
    pub fn initTable(db: *sqlite.Db) !void {
        const query =
            \\CREATE TABLE IF NOT EXISTS requests(
            \\  id INTEGER PRIMARY KEY,
            \\  bin INTEGER NOT NULL,
            \\  method TEXT NOT NULL,
            \\  remote_addr TEXT NOT NULL,
            \\  headers TEXT,
            \\  query TEXT,
            \\  body TEXT,
            \\  time INTEGER NOT NULL,
            \\  FOREIGN KEY(bin) REFERENCES bins(id) ON DELETE CASCADE
            \\);
            \\
            \\CREATE INDEX IF NOT EXISTS idx_requests_bin ON requests(bin);
        ;

        try db.execMulti(query, .{});
    }

    pub fn add(db: *sqlite.Db, allocator: std.mem.Allocator, model: *models.Request) !void {
        const query =
            \\INSERT INTO requests(id, bin, method, remote_addr, headers, query, body, time) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try db.prepare(query);
        defer stmt.deinit();

        try stmt.execAlloc(allocator, .{}, model.*);

        model.id = db.getLastInsertRowID();
    }

    pub fn fetchOrdered(db: *sqlite.Db, allocator: std.mem.Allocator, bin: i64, options: models.FetchOptions) ![]models.Request {
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
};

pub const bins = struct {
    pub fn initTable(db: *sqlite.Db) !void {
        const query =
            \\CREATE TABLE IF NOT EXISTS bins(
            \\  id INTEGER PRIMARY KEY,
            \\  name TEXT NOT NULL,
            \\  body INTEGER NOT NULL,
            \\  query INTEGER NOT NULL,
            \\  header INTEGER NOT NULL,
            \\  ips TEXT,
            \\  methods TEXT,
            \\  content_type INTEGER
            \\);
            \\
            \\CREATE UNIQUE INDEX IF NOT EXISTS idx_bins_name ON bins(name);
        ;

        try db.execMulti(query, .{});
    }

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

    pub fn fetch(db: *sqlite.Db, allocator: std.mem.Allocator, options: models.FetchOptions) ![]models.Bin {
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
};
