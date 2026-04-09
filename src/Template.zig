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
        print: *const fn (context: *anyopaque, writer: *std.Io.Writer, name: []const u8) anyerror!bool,
    };

    context: *anyopaque,
    vtable: *const VTable,

    pub fn print(self: Variables, writer: *std.Io.Writer, name: []const u8) !bool {
        return try self.vtable.print(self.context, writer, name);
    }
};

blocks: []const Block,

const space_chars = " \t\r\n";

fn isVariableChar(ch: u8) bool {
    return switch (ch) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '-', '_', '[', ']' => true,
        else => false,
    };
}

fn isSpace(ch: u8) bool {
    return std.mem.indexOfScalar(u8, space_chars, ch) != null;
}

pub fn parse(allocator: std.mem.Allocator, template: []const u8) !Template {
    var blocks = std.ArrayList(Block){};
    defer blocks.deinit(allocator);

    var state: enum { raw, variable, escape } = .raw;
    var start_index: usize = 0;

    for (0.., template) |index, ch| {
        switch (state) {
            .raw => {
                switch (ch) {
                    '{', '\\' => {
                        if (index > start_index) {
                            try blocks.append(allocator, .{ .raw = template[start_index..index] });
                        }

                        state = switch (ch) {
                            '{' => .variable,
                            '\\' => .escape,
                            else => unreachable,
                        };
                        start_index = index + 1;
                    },
                    '}' => return error.UnexpectedToken,
                    else => continue,
                }
            },
            .variable => {
                if (ch == '}') {
                    const name = std.mem.trim(u8, template[start_index..index], space_chars);

                    if (name.len == 0 or std.mem.indexOfAny(u8, name, space_chars) != null) {
                        return error.UnexpectedToken;
                    }

                    try blocks.append(allocator, .{ .variable = name });

                    state = .raw;
                    start_index = index + 1;
                } else if (!isVariableChar(ch) and !isSpace(ch)) {
                    return error.UnexpectedToken;
                }
            },
            .escape => {
                try blocks.append(allocator, .{ .raw = template[index .. index + 1] });

                state = .raw;
                start_index = index + 1;
            },
        }
    }

    switch (state) {
        .raw => {
            if (start_index < template.len) {
                try blocks.append(allocator, .{ .raw = template[start_index..] });
            }
        },
        else => return error.UnexpectedToken,
    }

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
