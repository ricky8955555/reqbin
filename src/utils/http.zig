const std = @import("std");

const httpz = @import("httpz");

const net_utils = @import("net.zig");

inline fn isTrustedProxy(address: std.net.Address, trusted_proxies: []const net_utils.Network) bool {
    for (trusted_proxies) |network| {
        if (network.isHost(address)) return true;
    }

    return false;
}

pub fn retrieveRemoteAddr(request: *httpz.Request, trusted_proxies: []const net_utils.Network) std.net.Address {
    var address = request.address;

    if (isTrustedProxy(address, trusted_proxies)) trusted: {
        if (request.header("x-forwarded-for")) |x_forwarded_for| {
            var ip_iter = std.mem.splitBackwardsScalar(u8, x_forwarded_for, ',');

            while (ip_iter.next()) |part| {
                const ip = std.mem.trim(u8, part, " ");
                address = std.net.Address.parseIp(ip, 0) catch break :trusted;
                if (!isTrustedProxy(address, trusted_proxies)) break :trusted;
            }
        }

        if (request.header("x-real-ip")) |x_real_ip| {
            address = std.net.Address.parseIp(x_real_ip, 0) catch break :trusted;
        }
    }

    return address;
}
