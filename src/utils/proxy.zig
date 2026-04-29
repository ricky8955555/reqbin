const std = @import("std");
const http = std.http;

const httpz = @import("httpz");

const filtered_headers: []const []const u8 = &.{"host"};

pub const PathHandler = union(enum) {
    as_is: void,
    remove_prefix: []const u8,
    overwrite: []const u8,
};

pub const Options = struct {
    base_url: []const u8,
    path: PathHandler,
};

const TranslatedHeaders = struct {
    headers: http.Client.Request.Headers,
    extra_headers: []const http.Header,

    pub fn deinit(self: TranslatedHeaders, allocator: std.mem.Allocator) void {
        allocator.free(self.extra_headers);
    }
};

fn translateUrl(aux_buf: []u8, origin: httpz.Url, target: []const u8, path: PathHandler) ![]const u8 {
    const suffix = suffix: {
        switch (path) {
            .as_is => break :suffix origin.path,
            .remove_prefix => |prefix| {
                if (!std.mem.startsWith(u8, origin.path, prefix)) return error.UnexpectedPrefix;
                break :suffix origin.path[prefix.len..];
            },
            .overwrite => |suffix| break :suffix suffix,
        }
    };

    const url = try std.fmt.bufPrint(aux_buf, "{s}{s}", .{ target, suffix });
    return url;
}

fn translateMethod(method: httpz.Method) !http.Method {
    for (std.enums.values(http.Method)) |m| {
        if (std.mem.eql(u8, @tagName(m), @tagName(method))) {
            return m;
        }
    }

    return error.MethodNotSupported;
}

fn translateHeaders(allocator: std.mem.Allocator, headers: *const httpz.key_value.StringKeyValue) !TranslatedHeaders {
    var it = headers.iterator();

    var standard = http.Client.Request.Headers{};

    const extra = try allocator.alloc(http.Header, headers.len);
    var idx: usize = 0;

    while (it.next()) |header| {
        const filtered = filtered: {
            inline for (filtered_headers) |filtered| {
                if (std.mem.eql(u8, filtered, header.key)) break :filtered true;
            }
            break :filtered false;
        };

        if (filtered) continue;

        inline for (@typeInfo(@TypeOf(standard)).@"struct".fields) |field| {
            const name = comptime name: {
                var name: [field.name.len]u8 = undefined;

                for (0.., field.name) |i, c| {
                    name[i] = switch (c) {
                        '_' => '-',
                        else => c,
                    };
                }

                const result = name;
                break :name &result;
            };

            if (std.mem.eql(u8, header.key, name)) {
                @field(standard, field.name) = .{ .override = header.value };
                break;
            }
        } else {
            extra[idx] = .{ .name = header.key, .value = header.value };
            idx += 1;
        }
    }

    return .{
        .headers = standard,
        .extra_headers = allocator.remap(extra, idx) orelse extra,
    };
}

pub fn proxy(allocator: std.mem.Allocator, req: *httpz.Request, res: *httpz.Response, options: Options) !void {
    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    const method = try translateMethod(req.method);

    var url_buf: [2048]u8 = undefined;
    const url = try translateUrl(&url_buf, req.url, options.base_url, options.path);

    var headers = try translateHeaders(allocator, req.headers);
    defer headers.deinit(allocator);

    var request = try client.request(
        method,
        try .parse(url),
        .{ .headers = headers.headers, .extra_headers = headers.extra_headers },
    );
    defer request.deinit();

    if (req.body()) |body| {
        request.transfer_encoding = .{ .content_length = body.len };

        var buffer: [4096]u8 = undefined;
        var body_writer = try request.sendBody(&buffer);
        try body_writer.writer.writeAll(body);
        try body_writer.end();
    } else {
        try request.sendBodiless();
    }

    var redirect_buffer: [2048]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);

    var header_it = response.head.iterateHeaders();
    while (header_it.next()) |header| {
        try res.headerOpts(header.name, header.value, .{ .dupe_name = true, .dupe_value = true });
    }

    var transfer_buffer: [4096]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    const writer = res.writer();
    _ = try reader.streamRemaining(writer);
}
