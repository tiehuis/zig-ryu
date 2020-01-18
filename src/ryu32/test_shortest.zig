const std = @import("std");
const ryu32 = @import("../ryu.zig").ryu32;

fn testShortest(expected: []const u8, input: f32) void {
    var buffer: [ryu32.max_buf_size.shortest]u8 = undefined;
    const converted = ryu32.printShortest(buffer[0..], input);
    std.debug.assert(std.mem.eql(u8, expected, converted));
}

test "basic" {
    testShortest("0E0", 0.0);
    testShortest("-0E0", -@as(f32, 0.0));
    testShortest("1E0", 1.0);
    testShortest("-1E0", -1.0);
    testShortest("NaN", std.math.nan(f32));
    testShortest("Infinity", std.math.inf(f32));
    testShortest("-Infinity", -std.math.inf(f32));
}

test "switch to subnormal" {
    testShortest("1.1754944E-38", 1.1754944e-38);
}

test "min and max" {
    testShortest("3.4028235E38", @bitCast(f32, @as(u32, 0x7f7fffff)));
    testShortest("1E-45", @bitCast(f32, @as(u32, 1)));
}

// Check that we return the exact boundary if it is the shortest
// representation, but only if the original floating point number is even.
test "boundary round even" {
    testShortest("3.355445E7", 3.355445e7);
    testShortest("9E9", 8.999999e9);
    testShortest("3.436672E10", 3.4366717e10);
}

// If the exact value is exactly halfway between two shortest representations,
// then we round to even. It seems like this only makes a difference if the
// last two digits are ...2|5 or ...7|5, and we cut off the 5.
test "exact value round even" {
    testShortest("3.0540412E5", 3.0540412E5);
    testShortest("8.0990312E3", 8.0990312E3);
}

test "lots of trailing zeros" {
    // Pattern for the first test: 00111001100000000000000000000000
    testShortest("2.4414062E-4", 2.4414062E-4);
    testShortest("2.4414062E-3", 2.4414062E-3);
    testShortest("4.3945312E-3", 4.3945312E-3);
    testShortest("6.3476562E-3", 6.3476562E-3);
}

test "looks like pow5" {
    // These numbers have a mantissa that is the largest power of 5 that fits,
    // and an exponent that causes the computation for q to result in 10, which is a corner
    // case for Ryu.
    testShortest("6.7108864E17", @bitCast(f32, @as(u32, 0x5D1502F9)));
    testShortest("1.3421773E18", @bitCast(f32, @as(u32, 0x5D9502F9)));
    testShortest("2.6843546E18", @bitCast(f32, @as(u32, 0x5E1502F9)));
}

test "regression" {
    testShortest("4.7223665E21", 4.7223665E21);
    testShortest("8.388608E6", 8388608.0);
    testShortest("1.6777216E7", 1.6777216E7);
    testShortest("3.3554436E7", 3.3554436E7);
    testShortest("6.7131496E7", 6.7131496E7);
    testShortest("1.9310392E-38", 1.9310392E-38);
    testShortest("-2.47E-43", -2.47E-43);
    testShortest("1.993244E-38", 1.993244E-38);
    testShortest("4.1039004E3", 4103.9003);
    testShortest("5.3399997E9", 5.3399997E9);
    testShortest("6.0898E-39", 6.0898E-39);
    testShortest("1.0310042E-3", 0.0010310042);
    testShortest("2.882326E17", 2.8823261E17);
    testShortest("7.038531E-26", 7.0385309E-26);
    testShortest("9.223404E17", 9.2234038E17);
    testShortest("6.710887E7", 6.7108872E7);
    testShortest("1E-44", 1.0E-44);
    testShortest("2.816025E14", 2.816025E14);
    testShortest("9.223372E18", 9.223372E18);
    testShortest("1.5846086E29", 1.5846085E29);
    testShortest("1.1811161E19", 1.1811161E19);
    testShortest("5.368709E18", 5.368709E18);
    testShortest("4.6143166E18", 4.6143165E18);
    testShortest("7.812537E-3", 0.007812537);
    testShortest("1E-45", 1.4E-45);
    testShortest("1.18697725E20", 1.18697724E20);
    testShortest("1.00014165E-36", 1.00014165E-36);
    testShortest("2E2", 200.0);
    testShortest("3.3554432E7", 3.3554432E7);
}
