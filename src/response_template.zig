const std = @import("std");

const httpz = @import("httpz");

const Template = @import("Template.zig");

const RequestVariables = struct {
    request: *httpz.Request,

    fn print(context: *const anyopaque, writer: *std.Io.Writer, name: []const u8) anyerror!bool {
        const self: *const RequestVariables = @ptrCast(@alignCast(context));
        var split = std.mem.splitScalar(u8, name, '.');

        const first = split.next().?;
        const optional_second = split.next();
        if (split.next() != null) return false;

        if (std.mem.eql(u8, first, "method")) {
            if (optional_second != null) return false;
            if (self.request.method == .OTHER) {
                try writer.writeAll(self.request.method_string);
            } else {
                try writer.writeAll(@tagName(self.request.method));
            }
        } else if (std.mem.eql(u8, first, "body")) {
            if (optional_second != null) return false;
            if (self.request.body()) |body| {
                try writer.writeAll(body);
            }
        } else if (std.mem.eql(u8, first, "headers")) {
            if (optional_second) |second| {
                const value = self.request.header(second) orelse return false;
                try writer.writeAll(value);
            } else {
                var it = self.request.headers.iterator();
                while (it.next()) |header| {
                    try writer.print("{s}: {s}", .{ header.key, header.value });
                }
            }
        } else if (std.mem.eql(u8, first, "query")) {
            var query = try self.request.query();

            if (optional_second) |second| {
                const value = query.get(second) orelse return false;
                try writer.writeAll(value);
            } else {
                var i: usize = 0;
                var it = query.iterator();
                while (it.next()) |kv| : (i += 1) {
                    try writer.print("{s}={s}", .{ kv.key, kv.value });
                    if (i != it.keys.len) {
                        try writer.writeByte('&');
                    }
                }
            }
        } else if (std.mem.eql(u8, first, "cookies")) {
            var cookies = self.request.cookies();
            if (optional_second) |second| {
                const value = cookies.get(second) orelse return false;
                try writer.writeAll(value);
            } else {
                try writer.writeAll(cookies.header);
            }
        } else {
            return false;
        }

        return true;
    }

    fn variables(self: *const RequestVariables) Template.Variables {
        return .{
            .context = @ptrCast(self),
            .vtable = &.{
                .print = print,
            },
        };
    }
};

pub fn render(template: Template, request: *httpz.Request, writer: *std.Io.Writer) !void {
    const request_variables = RequestVariables{ .request = request };
    const variables = request_variables.variables();

    try template.render(writer, variables, .{});
}
