const std = @import("std");

const httpz = @import("httpz");

const net_utils = @import("net.zig");

pub fn retrieveRemoteAddr(request: *httpz.Request, trusted_proxies: []const net_utils.Network) std.net.Address {
    const trusted = trusted: {
        for (trusted_proxies) |network| {
            if (network.isHost(request.address)) break :trusted true;
        } else break :trusted false;
    };

    var address: std.net.Address = request.address;

    if (trusted) {
        if (request.header("x-forwarded-for")) |x_forwarded_for| x_forwarded_for: {
            var ip_iter = std.mem.splitBackwardsScalar(u8, x_forwarded_for, ',');

            while (ip_iter.next()) |ip| {
                address = std.net.Address.parseIp(ip, 0) catch break :x_forwarded_for;

                for (trusted_proxies) |network| {
                    if (network.isHost(address)) break;
                } else break :x_forwarded_for;
            }
        }

        if (request.header("x-real-ip")) |x_real_ip| x_real_ip: {
            address = std.net.Address.parseIp(x_real_ip, 0) catch break :x_real_ip;
        }
    }

    return address;
}
