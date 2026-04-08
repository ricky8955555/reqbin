const std = @import("std");

const Template = @This();

pub const Block = union(enum) {
    raw: []const u8,
    variable: []const u8,
};

pub const PrintOptions = struct {
    ignore_undefined_variables: bool = true,
};

pub const Variables = struct {
    pub const VTable = struct {
        write: *const fn (context: *anyopaque, writer: *std.Io.Writer, name: []const u8) anyerror!bool,
    };

    context: *anyopaque,
    vtable: *const VTable,

    pub fn print(self: Variables, writer: *std.Io.Writer, name: []const u8) !bool {
        return try self.vtable.write(self.context, writer, name);
    }
};

blocks: []const Block,

pub fn parse(allocator: std.mem.Allocator, template: []const u8) !Template {
    var blocks = std.ArrayList(Block){};
    defer blocks.deinit(allocator);

    var state: enum { raw, variable, escape } = .raw;
    var start_index: usize = 0;

    for (0.., template) |index, ch| {
        const optional_next: ?struct { state: @TypeOf(state), block: ?Block } = next: {
            if (state == .escape) {
                break :next .{
                    .state = .raw,
                    .block = .{ .raw = template[start_index .. index + 1] },
                };
            }

            switch (ch) {
                '{' => {
                    if (state != .raw) return error.UnexpectedToken;

                    if (start_index == index) {
                        break :next .{ .state = .variable, .block = null };
                    }

                    break :next .{
                        .state = .variable,
                        .block = .{ .raw = template[start_index..index] },
                    };
                },
                '}' => {
                    if (state != .variable or start_index == index) return error.UnexpectedToken;

                    const name = std.mem.trim(u8, template[start_index..index], " ");
                    break :next .{
                        .state = .raw,
                        .block = .{ .variable = name },
                    };
                },
                '\\' => {
                    if (state != .raw) return error.UnexpectedToken;
                    break :next .{
                        .state = .escape,
                        .block = .{ .raw = template[start_index..index] },
                    };
                },
                else => {
                    if (index != template.len - 1) break :next null;

                    if (state != .raw) return error.UnexpectedToken;
                    break :next .{
                        .state = .raw,
                        .block = .{ .raw = template[start_index .. index + 1] },
                    };
                },
            }
        };

        if (optional_next) |next| {
            if (next.block) |block| {
                try blocks.append(allocator, block);
            }

            state = next.state;
            start_index = index + 1;
        }
    }

    std.debug.assert(state == .raw and start_index == template.len);

    return .{ .blocks = try blocks.toOwnedSlice(allocator) };
}

pub fn deinit(self: Template, allocator: std.mem.Allocator) void {
    allocator.free(self.blocks);
}

pub fn render(self: Template, writer: *std.Io.Writer, variables: Variables, options: PrintOptions) !void {
    for (self.blocks) |block| {
        switch (block) {
            .raw => |string| try writer.writeAll(string),
            .variable => |name| {
                const written = try variables.print(writer, name);
                if (!written and !options.ignore_undefined_variables) return error.UndefinedVariable;
            },
        }
    }
}
