const std = @import("std");
const ryu128 = @import("ryu128.zig");

pub fn main() !void {
    const F = f64;
    const method: Method = .random;
    const seed = 0;
    const format_mode: ryu128.Format = .scientific;
    const precision: Precision = .shortest;
    const test_mode: TestMode = .round_trip;

    std.debug.print("fuzzing: type={s} method={s} seed={}\n\n", .{ @typeName(F), @tagName(method), seed });

    var g = switch (method) {
        .exhaustive => ExhaustiveGenerator(F).init(),
        .random => RandomGenerator(F).init(seed),
    };
    try fuzzRoundTrip(F, &g, test_mode, seed, format_mode, precision);
}

const Method = enum {
    exhaustive,
    random,
};

const Precision = union(enum) {
    shortest,
    fixed: usize,
    random: usize,
};

pub fn ExhaustiveGenerator(comptime F: type) type {
    return struct {
        const I = std.meta.Int(.unsigned, @bitSizeOf(F));
        current: I,
        done: bool = false,

        pub fn init() @This() {
            return .{
                .current = 0,
            };
        }

        pub fn next(g: *@This()) ?F {
            if (g.done) return null;
            const v: F = @bitCast(g.current);
            if (g.current != std.math.maxInt(I)) g.current += 1 else g.done = true;
            return v;
        }
    };
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

const TestMode = enum {
    round_trip,
    crash_check,
    // std_compare, // Annoying to compare since printing a fixed precision at runtime with std is difficult
};

fn fuzzRoundTrip(comptime F: type, generator: anytype, comptime test_mode: TestMode, comptime seed: usize, comptime format_mode: ryu128.Format, comptime precision: Precision) !void {
    const I = std.meta.Int(.unsigned, @bitSizeOf(F));
    var buf: [ryu128.bufferSize(format_mode, F)]u8 = undefined;
    var rng = std.Random.DefaultPrng.init(seed);

    var test_num: usize = 0;
    while (generator.next()) |f| : (test_num += 1) {
        if (test_num % 50_000 == 0) {
            std.debug.print("\x1b[A\x1b[K", .{});
            std.debug.print("{}\n", .{test_num});
        }

        const p = switch (precision) {
            .shortest => null,
            .fixed => |v| v,
            .random => |upper_bound| rng.random().intRangeLessThan(usize, 0, upper_bound),
        };

        const f_bits: I = @bitCast(f);
        const ser = try ryu128.format(&buf, f, .{ .mode = format_mode, .precision = p });

        switch (test_mode) {
            .round_trip => {
                const deser = try std.fmt.parseFloat(F, ser);
                const deser_bits: I = @bitCast(deser);

                if (!std.math.isNan(f) and f_bits != deser_bits) {
                    std.debug.print(
                        \\{s} {}: {}
                        \\==========
                        \\ input: bits=0x{x} float={}
                        \\output: bits=0x{x} float={}
                        \\
                        \\ ryu string: {s}
                        \\
                    , .{
                        @typeName(F),
                        test_num,
                        f,
                        f_bits,
                        f,
                        deser_bits,
                        deser,
                        ser,
                    });
                    return error.Failed;
                }
            },
            .crash_check => {
                for (ser) |c| {
                    if (!std.ascii.isPrint(c)) {
                        std.debug.print(
                            \\{s} {}: {}
                            \\==========
                            \\ input: bits=0x{x} float={}
                            \\
                            \\ ryu string: {s}
                            \\
                        , .{
                            @typeName(F),
                            test_num,
                            f,
                            f_bits,
                            f,
                            ser,
                        });
                        return error.Failed;
                    }
                }
            },
        }
    }

    std.debug.print("\x1b[A\x1b[K", .{});
    std.debug.print("{} tests completed\n", .{test_num});
}
