const builtin = @import("builtin");
const std = @import("std");

const sqlite = @import("sqlite");

const reqbin = @import("reqbin");
const Network = reqbin.utils.network.Network;

const Config = struct {
    max_body_size: ?usize = null,
    max_query_count: ?usize = null,
    max_header_count: ?usize = null,

    database: []const u8 = "data.db",

    address: []const u8 = "127.0.0.1",
    port: u16 = 7280,

    auth: ?[]const u8 = null,
    trusted_proxies: ?[]const u8 = null,

    pub fn parseFromEnvMap(envs: *std.process.Environ.Map) !Config {
        var config = Config{};

        inline for (@typeInfo(Config).@"struct".fields) |field| {
            const env_name = comptime makeEnvName(field.name);
            if (envs.get(env_name)) |value| {
                try parseField(&config, field.name, field.type, value);
            }
        }

        return config;
    }

    fn makeEnvName(comptime field_name: []const u8) []const u8 {
        comptime {
            var upper_name: [field_name.len]u8 = undefined;
            for (field_name, 0..) |c, i| {
                upper_name[i] = std.ascii.toUpper(c);
            }
            return "REQBIN_" ++ upper_name;
        }
    }

    fn parseField(config: *Config, comptime field_name: []const u8, comptime FieldType: type, value: []const u8) !void {
        const field_ptr = &@field(config, field_name);

        switch (@typeInfo(FieldType)) {
            .optional => |optional| try parseField(config, field_name, optional.child, value),
            .int => field_ptr.* = try std.fmt.parseInt(FieldType, value, 10),
            .pointer => |ptr| {
                if (ptr.size == .slice and ptr.child == u8) {
                    field_ptr.* = value;
                } else {
                    @compileError("Unsupported pointer type for field: " ++ field_name);
                }
            },
            else => @compileError("Unsupported field type: " ++ @typeName(FieldType)),
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const config = try Config.parseFromEnvMap(init.environ_map);
    const allocator = init.arena.allocator();

    const trusted_proxies = trusted_proxies: {
        if (config.trusted_proxies) |trusted_proxies_str| {
            var trusted_proxies = try std.ArrayList(Network).initCapacity(allocator, 16);
            defer trusted_proxies.deinit(allocator);

            var proxy_iter = std.mem.splitScalar(u8, trusted_proxies_str, ',');
            while (proxy_iter.next()) |proxy| {
                const network = try Network.parse(proxy);
                try trusted_proxies.append(allocator, network);
            }

            break :trusted_proxies try trusted_proxies.toOwnedSlice(allocator);
        } else {
            break :trusted_proxies &.{};
        }
    };

    const database = try allocator.dupeZ(u8, config.database);

    var db = try sqlite.Db.init(.{
        .mode = .{ .File = database },
        .open_flags = .{ .create = true, .write = true },
        .threading_mode = .Serialized,
    });
    defer db.deinit();

    var ctx = reqbin.App.Context{
        .allocator = allocator,
        .io = io,
        .db = &db,
        .auth = config.auth,
        .trusted_proxies = trusted_proxies,
    };

    var app = try reqbin.App.init(&ctx, .{
        .address = .{ .ip = try .parse(config.address, config.port) },
        .request = .{
            .max_body_size = config.max_body_size,
            .max_header_count = config.max_header_count,
            .max_query_count = config.max_query_count,
        },
    });
    defer app.deinit();

    try app.listen();
}
