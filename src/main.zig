const builtin = @import("builtin");
const std = @import("std");

const sqlite = @import("sqlite");

const reqbin = @import("reqbin");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    const allocator, const is_debug = allocator: {
        if (builtin.link_libc) {
            if (@alignOf(std.c.max_align_t) < @max(@alignOf(i128), std.atomic.cache_line)) {
                break :allocator .{ std.heap.c_allocator, false };
            }
            break :allocator .{ std.heap.raw_c_allocator, false };
        }
        break :allocator switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator, true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var envs = try std.process.getEnvMap(allocator);
    defer envs.deinit();

    const config = try reqbin.Config.parseFromEnvMap(envs);

    const database = try allocator.dupeZ(u8, config.database);
    defer allocator.free(database);

    var db = try sqlite.Db.init(.{
        .mode = .{ .File = database },
        .open_flags = .{ .create = true, .write = true },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    var ctx = reqbin.App.Context{
        .allocator = allocator,
        .db = &db,
        .auth = config.auth,
    };

    var app = try reqbin.App.init(&ctx, .{
        .address = config.address,
        .port = config.port,
        .request = .{
            .max_body_size = config.max_body_size,
            .max_header_count = config.max_header_count,
            .max_query_count = config.max_query_count,
            .max_form_count = config.max_form_count,
        },
    });
    defer app.deinit();

    try app.listen();
}
