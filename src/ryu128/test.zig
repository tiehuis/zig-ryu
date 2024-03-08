// Document differences between std and ryu

const std = @import("std");
const ryu = @import("ryu128.zig");

fn toString(comptime precision: anytype) []const u8 {
    std.debug.assert(precision < 100);
    var pbuf: [2]u8 = undefined;
    if (precision > 10) {
        pbuf[0] = ((precision / 10) % 10) + '0';
        pbuf[1] = (precision % 10) + '0';
        return pbuf[0..2];
    } else {
        pbuf[0] = (precision % 10) + '0';
        return pbuf[0..1];
    }
}

fn checkRound(comptime T: type, f: T, comptime precision: usize) !void {
    const precision_string = comptime toString(precision);

    var ryu_buf3: [6000]u8 = undefined;
    const ryu_shortest = try ryu.format(&ryu_buf3, f, .{});
    var std_buf3: [6000]u8 = undefined;
    const std_shortest = try std.fmt.bufPrint(&std_buf3, "{}", .{f});

    var ryu_buf1: [6000]u8 = undefined;
    const ryu_dec = try ryu.format(&ryu_buf1, f, .{ .mode = .decimal, .precision = precision });
    var ryu_buf2: [6000]u8 = undefined;
    const ryu_exp = try ryu.format(&ryu_buf2, f, .{ .mode = .scientific, .precision = precision });

    var std_buf1: [6000]u8 = undefined;
    const std_dec = try std.fmt.bufPrint(&std_buf1, "{d:." ++ precision_string ++ "}", .{f});
    var std_buf2: [6000]u8 = undefined;
    const std_exp = try std.fmt.bufPrint(&std_buf2, "{e:." ++ precision_string ++ "}", .{f});

    if (!std.mem.eql(u8, ryu_dec, std_dec) or !std.mem.eql(u8, ryu_exp, std_exp)) {
        std.debug.print(
            \\# precision:    {}
            \\# std_shortest: {s}
            \\# ryu_shortest: {s}
            \\# type:         {s}
            \\|
            \\|std_dec: {s}
            \\|ryu_dec: {s}
            \\|
            \\|std_exp: {s}
            \\|ryu_exp: {s}
            \\===================
            \\
        , .{ precision, std_shortest, ryu_shortest, @typeName(T), std_dec, ryu_dec, std_exp, ryu_exp });
    }
}

test "round-trip" {
    try checkRound(f16, @bitCast(@as(u16, 15361)), 2);
    try checkRound(f16, @bitCast(@as(u16, 5145)), 4);
    try checkRound(f32, @bitCast(@as(u32, 431064)), 3);

    try checkRound(f16, @bitCast(@as(u16, 15259)), 0);
    try checkRound(f16, @bitCast(@as(u16, 6955)), 3);
    try checkRound(f16, @bitCast(@as(u16, 4121)), 3);
    try checkRound(f32, @bitCast(@as(u32, 7137)), 3);

    //try checkRound(f128, u128, 170135019233645109897966048701273983376);
    try checkRound(f64, 302.456789e10, 5);
    try checkRound(f64, 0.12999, 5);

    try checkRound(f64, 123e-40, 5);
    try checkRound(f32, 0, 5);
    try checkRound(f32, 9.9999, 5);

    try checkRound(f32, @bitCast(@as(u32, 0)), 5);

    try checkRound(f64, 1234e40, 2);
}

pub fn main() !void {
    const F = f32;
    const I = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @bitSizeOf(F) } });

    inline for (3..4) |precision| {
        const precision_string = comptime toString(precision);

        var i: I = 0;
        while (true) : (i += 1) {
            const f: F = @bitCast(i);
            if (i % 100_000 == 0) {
                std.debug.print("{}\n", .{i});
            }

            var ryu_buf3: [6000]u8 = undefined;
            const ryu_shortest = try ryu.format(&ryu_buf3, f, .{});
            var std_buf3: [6000]u8 = undefined;
            const std_shortest = try std.fmt.bufPrint(&std_buf3, "{}", .{f});

            var ryu_buf1: [6000]u8 = undefined;
            const ryu_dec = try ryu.format(&ryu_buf1, f, .{ .mode = .decimal, .precision = precision });
            var ryu_buf2: [6000]u8 = undefined;
            const ryu_exp = try ryu.format(&ryu_buf2, f, .{ .mode = .scientific, .precision = precision });

            var std_buf1: [6000]u8 = undefined;
            const std_dec = try std.fmt.bufPrint(&std_buf1, "{d:." ++ precision_string ++ "}", .{f});
            var std_buf2: [6000]u8 = undefined;
            const std_exp = try std.fmt.bufPrint(&std_buf2, "{e:." ++ precision_string ++ "}", .{f});

            if (!std.mem.eql(u8, ryu_dec, std_dec) or !std.mem.eql(u8, ryu_exp, std_exp)) {
                std.debug.print(
                    \\# bits:         {}
                    \\# precision:    {}
                    \\# std_shortest: {s}
                    \\# ryu_shortest: {s}
                    \\# type:         {s}
                    \\|
                    \\| std_dec: {s}
                    \\| ryu_dec: {s}
                    \\|
                    \\| std_exp: {s}
                    \\| ryu_exp: {s}
                    \\===================
                    \\
                , .{ i, precision, std_shortest, ryu_shortest, @typeName(F), std_dec, ryu_dec, std_exp, ryu_exp });
                //break;
            }

            if (i == std.math.maxInt(I)) break;
        }
    }
}
