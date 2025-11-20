const std = @import("std");

pub const Ip4Network = struct {
    addr: u32,
    prefix_len: u8,

    pub fn network_mask(self: Ip4Network) u32 {
        return ~self.host_mask();
    }

    fn host_mask(self: Ip4Network) u32 {
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

        if (addr & self.host_mask() != 0) return error.HostBitsSet;

        return self;
    }

    pub fn parse(network: []const u8) !Ip4Network {
        const slash_pos = std.mem.indexOfScalar(u8, network, '/') orelse return error.InvalidCharacter;

        const addr = try std.net.Ip4Address.parse(network[0..slash_pos], 0);
        const prefix_len = try std.fmt.parseInt(u8, network[slash_pos + 1 ..], 10);

        return Ip4Network.init(addr, prefix_len);
    }

    pub fn isHost(self: Ip4Network, host: std.net.Ip4Address) bool {
        const addr = addrToInt(host);
        return (addr & self.network_mask()) == self.addr;
    }
};

pub const Ip6Network = struct {
    addr: u128,
    prefix_len: u8,

    fn network_mask(self: Ip6Network) u128 {
        return ~self.host_mask();
    }

    fn host_mask(self: Ip6Network) u128 {
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

        if (addr & self.host_mask() != 0) return error.HostBitsSet;

        return self;
    }

    pub fn parse(network: []const u8) !Ip6Network {
        const slash_pos = std.mem.indexOfScalar(u8, network, '/') orelse return error.InvalidCharacter;

        const addr = try std.net.Ip6Address.parse(network[0..slash_pos], 0);
        const prefix_len = try std.fmt.parseInt(u8, network[slash_pos + 1 ..], 10);

        return Ip6Network.init(addr, prefix_len);
    }

    pub fn isHost(self: Ip6Network, host: std.net.Ip6Address) bool {
        const addr = addrToInt(host);
        return (addr & self.network_mask()) == self.addr;
    }
};

pub const Network = union(enum) {
    ip4: Ip4Network,
    ip6: Ip6Network,

    pub fn parse(network: []const u8) !Network {
        const slash_pos = std.mem.indexOfScalar(u8, network, '/') orelse return error.InvalidCharacter;

        const addr = try std.net.Address.parseIp(network[0..slash_pos], 0);
        const prefix_len = try std.fmt.parseInt(u8, network[slash_pos + 1 ..], 10);

        switch (addr.any.family) {
            std.posix.AF.INET => {
                const ip4_network = try Ip4Network.init(addr.in, prefix_len);
                return .{ .ip4 = ip4_network };
            },
            std.posix.AF.INET6 => {
                const ip6_network = try Ip6Network.init(addr.in6, prefix_len);
                return .{ .ip6 = ip6_network };
            },
            else => unreachable,
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
