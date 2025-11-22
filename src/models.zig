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

pub const StringKeyValue = struct {
    map: httpz.key_value.StringKeyValue,

    pub const BaseType = []const u8;

    pub fn bindField(self: StringKeyValue, allocator: Allocator) !BaseType {
        var out = std.Io.Writer.Allocating.init(allocator);
        defer out.deinit();

        var stringify = std.json.Stringify{ .writer = &out.writer };
        try stringify.write(self);

        return out.toOwnedSlice();
    }

    pub fn readField(allocator: Allocator, value: BaseType) !StringKeyValue {
        const parsed = try std.json.parseFromSlice(StringKeyValue, allocator, value, .{ .allocate = .alloc_always });
        return parsed.value;
    }

    pub fn jsonStringify(self: StringKeyValue, jws: anytype) !void {
        try jws.beginObject();
        var it = self.map.iterator();
        while (it.next()) |kv| {
            try jws.objectField(kv.key);
            try jws.write(kv.value);
        }
        try jws.endObject();
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!StringKeyValue {
        if (.object_begin != try source.next()) return error.UnexpectedToken;

        var kvs = try std.ArrayList(struct { key: []const u8, value: []const u8 }).initCapacity(allocator, 32);
        defer kvs.deinit(allocator);

        while (true) {
            const key_token = try source.nextAlloc(allocator, options.allocate.?);
            switch (key_token) {
                inline .string, .allocated_string => |key| {
                    const value_token = try source.nextAlloc(allocator, options.allocate.?);
                    switch (value_token) {
                        inline .string, .allocated_string => |value| {
                            try kvs.append(allocator, .{ .key = key, .value = value });
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                .object_end => break,
                else => unreachable,
            }
        }

        var map = try httpz.key_value.StringKeyValue.init(allocator, kvs.items.len);
        errdefer map.deinit(allocator);

        for (kvs.items) |item| {
            map.add(item.key, item.value);
        }

        return .{ .map = map };
    }

    pub fn deinit(self: StringKeyValue, allocator: Allocator) void {
        self.map.deinit(allocator);
    }
};

pub const ContentType = enum(u2) {
    raw = 0,
    form = 1,
    json = 2,

    pub const BaseType = u2;

    pub fn bindField(self: ContentType, _: Allocator) !BaseType {
        return @intFromEnum(self);
    }

    pub fn readField(_: Allocator, value: BaseType) !ContentType {
        return @enumFromInt(value);
    }
};

pub const Body = struct {
    const InnerBody = union(enum) {
        raw: []const u8,
        form: StringKeyValue,
        json: JsonValue,
    };

    value: InnerBody,

    pub const BaseType = []const u8;

    pub fn bindField(self: Body, allocator: Allocator) !BaseType {
        var out = std.Io.Writer.Allocating.init(allocator);
        defer out.deinit();

        var stringify = std.json.Stringify{ .writer = &out.writer };
        try stringify.write(self);

        return out.toOwnedSlice();
    }

    pub fn readField(allocator: Allocator, value: BaseType) !Body {
        const parsed = try std.json.parseFromSlice(Body, allocator, value, .{ .allocate = .alloc_always });
        return parsed.value;
    }

    pub fn jsonStringify(self: Body, jws: anytype) !void {
        try jws.write(self.value);
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!Body {
        const parsed = try std.json.innerParse(InnerBody, allocator, source, options);
        return .{ .value = parsed };
    }

    pub fn parseFromRequest(request: *httpz.Request, expected_content_type: ?ContentType) !?Body {
        const content_type = typ: {
            if (expected_content_type) |content_type| break :typ content_type;

            const optional_content_type = request.header("content-type");

            if (optional_content_type) |content_type| {
                if (std.mem.eql(u8, content_type, "application/json")) break :typ .json;
                if (std.mem.eql(u8, content_type, "application/x-www-form-urlencoded")) break :typ .form;
            }

            break :typ .raw;
        };

        switch (content_type) {
            .json => {
                const json = try request.jsonValue() orelse return null;
                return .{ .value = .{ .json = json } };
            },
            .form => {
                const form = try request.formData();
                return .{ .value = .{ .form = .{ .map = form.* } } };
            },
            .raw => {
                const body = request.body() orelse return null;
                return .{ .value = .{ .raw = body } };
            },
        }
    }
};

pub const Request = struct {
    id: ?i64 = null,

    bin: i64,

    method: []const u8,
    remote_addr: []const u8,

    headers: ?StringKeyValue,

    query: ?StringKeyValue,
    body: ?Body,

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

pub const Bin = struct {
    id: ?i64 = null,

    name: []const u8,

    body: bool = true,
    query: bool = true,
    headers: bool = true,

    ips: ?Array(IpString) = null,
    methods: ?Array(httpz.Method) = null,

    content_type: ?ContentType = null,
};
