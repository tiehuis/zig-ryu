const std = @import("std");
const ryu = @import("ryu128.zig");

pub fn main() !void {
    const F = f64;
    const backend: Backend = .errol;
    const seed = 1;
    const trials = 1_000_000;

    std.debug.print("perf: type={s} backend={s} seed={}\n", .{ @typeName(F), @tagName(backend), seed });

    var g = RandomGenerator(F).init(seed);
    try perf(F, &g, backend, trials);
}

const Backend = enum {
    errol,
    ryu,
};

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

fn perf(comptime F: type, generator: anytype, backend: Backend, trials: usize) !void {
    var buf: [6000]u8 = undefined;

    var sw = try std.time.Timer.start();
    var sum: usize = 0;

    var test_num: usize = 0;
    while (test_num < trials) : (test_num += 1) {
        const f: F = generator.next() orelse unreachable;
        const ser = switch (backend) {
            .ryu => try ryu.format(&buf, f, .{}),
            .errol => try std.fmt.bufPrint(&buf, "{}", .{f}),
        };
        sum +%= ser[0];
    }

    const elapsed = sw.read();
    const ns_per_trial = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(trials));
    std.debug.print("{d:.2}ns per trial ({} trials) (check 0x{x})\n", .{ ns_per_trial, trials, sum });
}
