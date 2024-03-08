const std = @import("std");
const ryu128 = @import("ryu128.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    var buf: [10000]u8 = undefined;

    inline for (.{ f128, f80, c_longdouble, f64, f32, f16 }) |T| {
        var g = RandomGenerator(T).init(0);
        const f = g.next() orelse unreachable;
        const c = try ryu128.format(&buf, @as(T, f), .{});

        _ = try stdout.write(c);
        _ = try stdout.write(" :" ++ @typeName(T) ++ "\n");
    }
}

pub fn RandomGenerator(comptime F: type) type {
    return struct {
        const I = std.meta.Int(.unsigned, @bitSizeOf(F));
        rng: std.Random.DefaultPrng,

        pub fn init(seed: anytype) @This() {
            return .{
                .rng = std.Random.DefaultPrng.init(seed),
            };
        }

        pub fn next(g: *@This()) ?F {
            return @bitCast(g.rng.random().int(I));
        }
    };
}

pub fn panic(format: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = format;
    _ = trace;
    _ = ret_addr;
    @setCold(true);
    while (true) {}
}
