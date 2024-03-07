const std = @import("std");
const ryu128 = @import("ryu128.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    var buf: [10000]u8 = undefined;

    inline for (.{f64}) |T| {
        const f = 3.12345678910111213141516171819202122232425;
        const c = try ryu128.ryu128_format(&buf, @as(T, f), .{});

        _ = try stdout.write(c);
        _ = try stdout.write(" :" ++ @typeName(T) ++ "\n");
    }
}
