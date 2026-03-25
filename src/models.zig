const std = @import("std");
const Allocator = std.mem.Allocator;
const JsonValue = std.json.Value;

const zdt = @import("zdt");
const httpz = @import("httpz");

pub const Timestamp = struct {
    value: zdt.Datetime,

    pub const BaseType = i64;

    pub fn serialize(self: Timestamp) !BaseType {
        const converted = try self.value.tzConvert(.{ .tz = &zdt.Timezone.UTC });
        return @intCast(converted.toUnix(.second));
    }

    pub fn deserialize(value: BaseType) !Timestamp {
        const parsed = try zdt.Datetime.fromUnix(@as(i128, value), .second, .{ .tz = &zdt.Timezone.UTC });
        return .{ .value = parsed };
    }

    pub fn bindField(self: Timestamp, _: Allocator) !BaseType {
        return self.serialize();
    }

    pub fn readField(_: Allocator, value: BaseType) !Timestamp {
        return deserialize(value);
    }

    pub fn jsonStringify(self: Timestamp, jws: anytype) !void {
        const value = self.serialize() catch return error.WriteFailed;
        try jws.write(value);
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Timestamp {
        const value = std.json.innerParse(i64, allocator, source, options);
        return deserialize(value);
    }
};

pub const StringKeyValue = union(enum) {
    std: std.StringArrayHashMapUnmanaged([]const u8),
    httpz: httpz.key_value.StringKeyValue,

    pub const Iterator = union(enum) {
        std: std.StringArrayHashMapUnmanaged([]const u8).Iterator,
        httpz: httpz.key_value.StringKeyValue.Iterator,

        const KV = struct {
            key: []const u8,
            value: []const u8,
        };

        pub fn next(self: *Iterator) ?KV {
            switch (self.*) {
                .std => |*it| {
                    const kv = it.next() orelse return null;
                    return .{ .key = kv.key_ptr.*, .value = kv.value_ptr.* };
                },
                .httpz => |*it| {
                    const kv = it.next() orelse return null;
                    return .{ .key = kv.key, .value = kv.value };
                },
            }
        }
    };

    pub fn iterator(self: StringKeyValue) Iterator {
        switch (self) {
            .std => |map| return .{ .std = map.iterator() },
            .httpz => |map| return .{ .httpz = map.iterator() },
        }
    }

    pub fn jsonStringify(self: StringKeyValue, jws: anytype) !void {
        try jws.beginObject();

        var it = self.iterator();
        while (it.next()) |kv| {
            try jws.objectField(kv.key);
            try jws.write(kv.value);
        }

        try jws.endObject();
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!StringKeyValue {
        if (.object_begin != try source.next()) return error.UnexpectedToken;

        var map = std.StringArrayHashMapUnmanaged([]const u8){};
        errdefer map.deinit(allocator);

        while (true) {
            const key_token = try source.nextAlloc(allocator, options.allocate.?);
            switch (key_token) {
                inline .string, .allocated_string => |key| {
                    const value_token = try source.nextAlloc(allocator, options.allocate.?);
                    switch (value_token) {
                        inline .string, .allocated_string => |value| {
                            try map.put(allocator, key, value);
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .object_end => break,
                else => unreachable,
            }
        }

        return .{ .std = map };
    }

    pub fn deinit(self: StringKeyValue, allocator: Allocator) void {
        switch (self) {
            .std => |map| map.deinit(allocator),
            .httpz => |map| map.deinit(allocator),
        }
    }
};

pub const Capture = struct {
    id: ?i64 = null,

    bin: i64,

    method: []const u8,
    remote_addr: []const u8,

    headers: ?JsonField(StringKeyValue),

    query: ?JsonField(StringKeyValue),
    body: ?[]const u8,

    time: Timestamp,
};

pub const PageParams = struct {
    limit: u64 = 20,
    offset: u64 = 0,

    pub fn parseFromStringKeyValue(kv: *httpz.key_value.StringKeyValue) !PageParams {
        var options = PageParams{};

        if (kv.get("limit")) |limit| {
            options.limit = try std.fmt.parseInt(u64, limit, 10);
        }
        if (kv.get("offset")) |offset| {
            options.offset = try std.fmt.parseInt(u64, offset, 10);
        }

        return options;
    }
};

pub fn Page(comptime T: type) type {
    return struct {
        total: usize,
        count: usize,
        data: []T,
    };
}

pub fn Array(comptime T: type) type {
    return struct {
        value: []T,

        const Self = @This();

        pub const BaseType = []const u8;

        pub fn bindField(self: Self, allocator: Allocator) !BaseType {
            var out = std.Io.Writer.Allocating.init(allocator);
            defer out.deinit();

            var stringify = std.json.Stringify{ .writer = &out.writer };
            try stringify.write(self);

            return out.toOwnedSlice();
        }

        pub fn readField(allocator: Allocator, value: BaseType) !Self {
            const parsed = try std.json.parseFromSlice(Self, allocator, value, .{ .allocate = .alloc_always });
            return parsed.value;
        }

        pub fn jsonStringify(self: Self, jws: anytype) !void {
            try jws.write(self.value);
        }

        pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Self {
            const value = try std.json.innerParse([]T, allocator, source, options);
            return .{ .value = value };
        }
    };
}

fn Validate(comptime BaseType: type, comptime validate: *const fn (value: *const BaseType) bool) type {
    return struct {
        value: BaseType,

        const Self = @This();

        pub fn bindField(self: Self, _: Allocator) !BaseType {
            return self.value;
        }

        pub fn readField(_: Allocator, value: BaseType) !Self {
            if (!validate(&value)) return error.Validation;
            return .{ .value = value };
        }

        pub fn jsonStringify(self: Self, jws: anytype) !void {
            try jws.write(self.value);
        }

        pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Self {
            const value = try std.json.innerParse(BaseType, allocator, source, options);
            if (!validate(&value)) return error.InvalidCharacter;
            return .{ .value = value };
        }
    };
}

pub const IpString = Validate([]const u8, struct {
    fn validate(value: *const []const u8) bool {
        _ = std.net.Address.resolveIp(value.*, 0) catch return false;
        return true;
    }
}.validate);

fn JsonField(comptime ValueType: type) type {
    return struct {
        const Self = @This();

        value: ValueType,

        pub const BaseType = []const u8;

        pub fn bindField(self: Self, allocator: Allocator) !BaseType {
            var out = std.Io.Writer.Allocating.init(allocator);
            defer out.deinit();

            var stringify = std.json.Stringify{ .writer = &out.writer };
            try stringify.write(self);

            return out.toOwnedSlice();
        }

        pub fn readField(allocator: Allocator, value: BaseType) !Self {
            const parsed = try std.json.parseFromSlice(Self, allocator, value, .{ .allocate = .alloc_always });
            return parsed.value;
        }

        pub fn jsonStringify(self: Self, jws: anytype) !void {
            try jws.write(self.value);
        }

        pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Self {
            const parsed = try std.json.innerParse(ValueType, allocator, source, options);
            return .{ .value = parsed };
        }
    };
}

pub const Responding = union(enum) {
    pub const Static = struct {
        headers: JsonField(StringKeyValue),
        body: []const u8,
    };

    capture: void,
    static: Static,
};

pub const Bin = struct {
    id: ?i64 = null,

    name: []const u8,

    body: bool = true,
    query: bool = true,
    headers: bool = true,

    ips: ?Array(IpString) = null,
    methods: ?Array(httpz.Method) = null,

    responding: JsonField(Responding) = .{ .value = .capture },
};
