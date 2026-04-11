const builtin = @import("builtin");
const std = @import("std");

const native_endian = builtin.target.cpu.arch.endian();

pub const Ip4Network = struct {
    addr: u32,
    prefix_len: u8,

    pub fn networkMask(self: Ip4Network) u32 {
        return ~self.hostMask();
    }

    fn hostMask(self: Ip4Network) u32 {
        if (self.prefix_len == 32) return 0;
        return @as(u32, std.math.maxInt(u32)) >> @intCast(self.prefix_len);
    }

    fn addrToInt(addr: std.net.Ip4Address) u32 {
        return std.mem.nativeToBig(u32, addr.sa.addr);
    }

    pub fn init(network: std.net.Ip4Address, prefix_len: u8) !Ip4Network {
        if (prefix_len > 32) return error.Overflow;

        const addr = addrToInt(network);
        const self = Ip4Network{ .addr = addr, .prefix_len = prefix_len };

        if (addr & self.hostMask() != 0) return error.HostBitsSet;

        return self;
    }

    pub fn parse(network: []const u8) !Ip4Network {
        if (std.mem.indexOfScalar(u8, network, '/')) |slash_pos| {
            const addr = try std.net.Ip4Address.parse(network[0..slash_pos], 0);
            const prefix_len = try std.fmt.parseInt(u8, network[slash_pos + 1 ..], 10);

            return Ip4Network.init(addr, prefix_len);
        } else {
            const addr = try std.net.Ip4Address.parse(network, 0);

            return Ip4Network.init(addr, 32);
        }
    }

    pub fn format(self: Ip4Network, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const nativeAddr = std.mem.bigToNative(u32, self.addr);
        const bytes: *const [4]u8 = @ptrCast(&nativeAddr);
        try w.print("{d}.{d}.{d}.{d}/{d}", .{ bytes[0], bytes[1], bytes[2], bytes[3], self.prefix_len });
    }

    pub fn isHost(self: Ip4Network, host: std.net.Ip4Address) bool {
        const addr = addrToInt(host);
        return (addr & self.networkMask()) == self.addr;
    }
};

pub const Ip6Network = struct {
    addr: u128,
    prefix_len: u8,

    fn networkMask(self: Ip6Network) u128 {
        return ~self.hostMask();
    }

    fn hostMask(self: Ip6Network) u128 {
        if (self.prefix_len == 128) return 0;
        return @as(u128, std.math.maxInt(u128)) >> @intCast(self.prefix_len);
    }

    fn addrToInt(addr: std.net.Ip6Address) u128 {
        return std.mem.readInt(u128, &addr.sa.addr, .big);
    }

    pub fn init(network: std.net.Ip6Address, prefix_len: u8) !Ip6Network {
        if (prefix_len > 128) return error.Overflow;

        const addr = addrToInt(network);
        const self = Ip6Network{ .addr = addr, .prefix_len = prefix_len };

        if (addr & self.hostMask() != 0) return error.HostBitsSet;

        return self;
    }

    pub fn parse(network: []const u8) !Ip6Network {
        if (std.mem.indexOfScalar(u8, network, '/')) |slash_pos| {
            const addr = try std.net.Ip6Address.parse(network[0..slash_pos], 0);
            const prefix_len = try std.fmt.parseInt(u8, network[slash_pos + 1 ..], 10);

            return Ip6Network.init(addr, prefix_len);
        } else {
            const addr = try std.net.Ip6Address.parse(network, 0);

            return Ip6Network.init(addr, 128);
        }
    }

    pub fn format(self: Ip6Network, w: *std.Io.Writer) std.Io.Writer.Error!void {
        // This function is modified from `std.net.Ip6Address.format`.

        const nativeAddr = std.mem.bigToNative(u128, self.addr);
        const bytes: *const [16]u8 = @ptrCast(&nativeAddr);

        if (std.mem.eql(u8, bytes[0..12], &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff })) {
            try w.print("::ffff:{d}.{d}.{d}.{d}/{d}", .{ bytes[12], bytes[13], bytes[14], bytes[15], self.prefix_len });
            return;
        }

        const big_endian_parts = @as(*align(1) const [8]u16, @ptrCast(bytes));
        const native_endian_parts = switch (native_endian) {
            .big => big_endian_parts.*,
            .little => blk: {
                var buf: [8]u16 = undefined;
                for (big_endian_parts, 0..) |part, i| {
                    buf[i] = std.mem.bigToNative(u16, part);
                }
                break :blk buf;
            },
        };

        // Find the longest zero run
        var longest_start: usize = 8;
        var longest_len: usize = 0;
        var current_start: usize = 0;
        var current_len: usize = 0;

        for (native_endian_parts, 0..) |part, i| {
            if (part == 0) {
                if (current_len == 0) {
                    current_start = i;
                }
                current_len += 1;
                if (current_len > longest_len) {
                    longest_start = current_start;
                    longest_len = current_len;
                }
            } else {
                current_len = 0;
            }
        }

        // Only compress if the longest zero run is 2 or more
        if (longest_len < 2) {
            longest_start = 8;
            longest_len = 0;
        }

        var i: usize = 0;
        var abbrv = false;
        while (i < native_endian_parts.len) : (i += 1) {
            if (i == longest_start) {
                // Emit "::" for the longest zero run
                if (!abbrv) {
                    try w.writeAll(if (i == 0) "::" else ":");
                    abbrv = true;
                }
                i += longest_len - 1; // Skip the compressed range
                continue;
            }
            if (abbrv) {
                abbrv = false;
            }
            try w.print("{x}", .{native_endian_parts[i]});
            if (i != native_endian_parts.len - 1) {
                try w.writeAll(":");
            }
        }

        try w.print("/{d}", .{self.prefix_len});
    }

    pub fn isHost(self: Ip6Network, host: std.net.Ip6Address) bool {
        const addr = addrToInt(host);
        return (addr & self.networkMask()) == self.addr;
    }
};

pub const Network = union(enum) {
    ip4: Ip4Network,
    ip6: Ip6Network,

    pub fn parse(network: []const u8) !Network {
        const addr, const prefix_len = parse: {
            if (std.mem.indexOfScalar(u8, network, '/')) |slash_pos| {
                const addr = try std.net.Address.parseIp(network[0..slash_pos], 0);
                const prefix_len = try std.fmt.parseInt(u8, network[slash_pos + 1 ..], 10);

                break :parse .{ addr, prefix_len };
            } else {
                const addr = try std.net.Address.parseIp(network, 0);

                break :parse .{ addr, null };
            }
        };

        switch (addr.any.family) {
            std.posix.AF.INET => {
                const ip4_network = try Ip4Network.init(addr.in, prefix_len orelse 32);
                return .{ .ip4 = ip4_network };
            },
            std.posix.AF.INET6 => {
                const ip6_network = try Ip6Network.init(addr.in6, prefix_len orelse 128);
                return .{ .ip6 = ip6_network };
            },
            else => unreachable,
        }
    }

    pub fn format(self: Network, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .ip4 => |network| try network.format(w),
            .ip6 => |network| try network.format(w),
        }
    }

    pub fn isHost(self: Network, host: std.net.Address) bool {
        switch (self) {
            .ip4 => |network| {
                if (host.any.family != std.posix.AF.INET) return false;
                return network.isHost(host.in);
            },
            .ip6 => |network| {
                if (host.any.family != std.posix.AF.INET6) return false;
                return network.isHost(host.in6);
            },
        }
    }
};
