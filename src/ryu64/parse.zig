const std = @import("std");

usingnamespace struct {
    pub usingnamespace @import("../internal.zig");
    pub usingnamespace @import("tables_shortest.zig");
};

inline fn floor_log2(x: u64) u32 {
    return 63 - @clz(u64, x);
}

pub const ParseError = error{
    TooShort,
    TooLong,
    Malformed,
};

pub fn parse(s: []const u8) ParseError!f64 {
    if (s.len == 0) {
        return error.TooShort;
    }

    var m10digits: usize = 0;
    var e10digits: usize = 0;
    var dot_index = s.len;
    var e_index = s.len;
    var m10: u64 = 0;
    var e10: i32 = 0;
    var signed_m = false;
    var signed_e = false;

    var i: usize = 0;

    if (s[i] == '-') {
        signed_m = true;
        i += 1;
    }

    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c == '.') {
            if (dot_index != s.len) {
                return error.Malformed;
            }
            dot_index = i;
            continue;
        }
        if (c < '0' or c > '9') {
            break;
        }
        if (m10digits >= 17) {
            return error.TooLong;
        }
        m10 = 10 * m10 + (c - '0');
        if (m10 != 0) {
            m10digits += 1;
        }
    }

    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        e_index = i;
        i += 1;
        if (i < s.len and (s[i] == '-' or s[i] == '+')) {
            signed_e = s[i] == '-';
            i += 1;
        }

        while (i < s.len) : (i += 1) {
            const c = s[i];
            if (c < '0' or c > '9') {
                return error.Malformed;
            }
            if (e10digits > 3) {
                // TODO: Be more lenient, return +-inf or +-0 instead.
                return error.TooLong;
            }
            e10 = 10 * e10 + @intCast(i32, c - '0');
            if (e10 != 0) {
                e10digits += 1;
            }
        }
    }

    if (i < s.len) {
        return error.Malformed;
    }

    if (signed_e) {
        e10 = -e10;
    }
    e10 -= if (dot_index < e_index) @intCast(i32, e_index - dot_index - 1) else 0;
    if (m10 == 0) {
        return if (signed_m) -0.0 else 0.0;
    }

    if (@intCast(i32, m10digits) + e10 <= -324 or m10 == 0) {
        // Number is less than 1e-324, which should be rounded down to 0
        const ieee = @as(u64, @boolToInt(signed_m)) << (DOUBLE_EXPONENT_BITS + DOUBLE_MANTISSA_BITS);
        return @bitCast(f64, ieee);
    }
    if (@intCast(i32, m10digits) + e10 >= 310) {
        // Number is larger than 1e+309, which should be rounded to inf
        const ieee = (@as(u64, @boolToInt(signed_m)) << (DOUBLE_EXPONENT_BITS + DOUBLE_MANTISSA_BITS)) | (0x7ff << DOUBLE_MANTISSA_BITS);
        return @bitCast(f64, ieee);
    }

    // Convert to binary float m2 * 2^e2, while retaining information about whether conversion was
    // exact (trailing_zeros).
    var e2: i32 = undefined;
    var m2: u64 = undefined;
    var trailing_zeros: bool = undefined;

    if (e10 >= 0) {
        // The length of m * 10^e in bits is:
        //   log2(m10 * 10^e10) = log2(m10) + e10 log2(10) = log2(m10) + e10 + e10 * log2(5)
        //
        // We want to compute the DOUBLE_MANTISSA_BITS + 1 top-most bits (+1 for the implicit leading
        // one in IEEE format). We therefore choose a binary output exponent of
        //   log2(m10 * 10^e10) - (DOUBLE_MANTISSA_BITS + 1).
        //
        // We use floor(log2(5^e10)) so that we get at least this many bits; better to
        // have an additional bit than to not have enough bits.
        e2 = @intCast(i32, floor_log2(m10)) + e10 + @intCast(i32, log2pow5(@intCast(u32, e10))) - (DOUBLE_MANTISSA_BITS + 1);

        // We now compute [m10 * 10^e10 / 2^e2] = [m10 * 5^e10 / 2^(e2-e10)].
        // To that end, we use the DOUBLE_POW5_SPLIT table.
        const j = e2 - e10 - @intCast(i32, ceil_log2pow5(@intCast(u32, e10))) + DOUBLE_POW5_BITCOUNT;
        std.debug.assert(j >= 0);
        std.debug.assert(e10 < DOUBLE_POW5_TABLE_SIZE);
        m2 = mulShift64(m10, DOUBLE_POW5_SPLIT[@intCast(usize, e10)], @intCast(u32, j));

        // We also compute if the result is exact, i.e.,
        //   [m10 * 10^e10 / 2^e2] == m10 * 10^e10 / 2^e2.
        // This can only be the case if 2^e2 divides m10 * 10^e10, which in turn requires that the
        // largest power of 2 that divides m10 + e10 is greater than e2. If e2 is less than e10, then
        // the result must be exact. Otherwise we use the existing multipleOfPowerOf2 function.
        trailing_zeros = e2 < e10 or multipleOfPowerOf2(m10, @intCast(u32, e2 - e10));
    } else {
        e2 = @intCast(i32, floor_log2(m10)) + e10 - @intCast(i32, ceil_log2pow5(@intCast(u32, -e10))) - (DOUBLE_MANTISSA_BITS + 1);
        const j = e2 - e10 + @intCast(i32, ceil_log2pow5(@intCast(u32, -e10))) - 1 + DOUBLE_POW5_INV_BITCOUNT;
        std.debug.assert(-e10 < DOUBLE_POW5_INV_TABLE_SIZE);
        m2 = mulShift64(m10, DOUBLE_POW5_INV_SPLIT[@intCast(u32, -e10)], @intCast(u32, j));
        trailing_zeros = multipleOfPowerOf5(m10, @intCast(u32, -e10));
    }

    // Compute the final IEEE exponent
    const ieee_e2: i32 = std.math.max(0, e2 + DOUBLE_BIAS + @intCast(i32, floor_log2(m2)));

    if (ieee_e2 > 0x7fe) {
        // Final IEEE exponent is larger than the maximum representable, +-infinity
        const ieee = (@as(u64, @boolToInt(signed_m)) << (DOUBLE_EXPONENT_BITS + DOUBLE_MANTISSA_BITS)) | (0x7ff << DOUBLE_MANTISSA_BITS);
        return @bitCast(f64, ieee);
    }

    // We need to figure out how much we need to shift m2. The tricky part is that we need to take
    // the final IEEE exponent into account, so we need to reverse the bias and also special-case
    // the value 0.
    const shift = (if (ieee_e2 == 0) 1 else ieee_e2) - e2 - DOUBLE_BIAS - DOUBLE_MANTISSA_BITS;
    std.debug.assert(shift >= 0);

    // We need to round up if the exact value is more than 0.5 above the value we computed. That's
    // equivalent to checking if the last removed bit was 1 and either the value was not just
    // trailing zeros or the result would otherwise be odd.
    //
    // We need to update trailingZeros given that we have the exact output exponent ieee_e2 now.
    trailing_zeros = trailing_zeros and ((m2 & (@as(u64, 1) << @intCast(u6, shift - 1)) - 1)) == 0;
    const last_removed_bit = (m2 >> @intCast(u6, shift - 1)) & 1;
    const round_up = last_removed_bit != 0 and (!trailing_zeros or (((m2 >> @intCast(u6, shift)) & 1) != 0));

    var ieee_m2 = (m2 >> @intCast(u6, shift)) + @boolToInt(round_up);
    if (ieee_m2 == (1 << (DOUBLE_MANTISSA_BITS + 1))) {
        // Due to how the IEEE represents +-inf, we don't need to check for overflow here
        ieee_m2 += 1;
    }
    ieee_m2 &= (1 << DOUBLE_MANTISSA_BITS) - 1;

    const ieee = (@as(u64, @boolToInt(signed_m)) << DOUBLE_EXPONENT_BITS) | (@intCast(u64, ieee_e2) << DOUBLE_MANTISSA_BITS) | ieee_m2;
    return @bitCast(f64, ieee);
}

fn expectParse(expected: f64, x: []const u8) void {
    std.testing.expectEqual(parse(x) catch unreachable, expected);
}

test "bad input" {}

test "basic" {
    expectParse(0.0, "0");
    expectParse(-0.0, "-0");
    expectParse(1.0, "1");
    expectParse(2.0, "2");
    expectParse(123456789.0, "123456789");
    expectParse(123.456, "123.456");
    expectParse(123.456, "123456e-3");
    expectParse(123.456, "1234.56e-1");
    expectParse(1.453, "1.453");
    expectParse(1453.0, "1.453e+3");
    expectParse(0.0, ".0");
    expectParse(1.0, "1e0");
    expectParse(1.0, "1E0");
    expectParse(1.0, "000001.000000");
}

test "min/max" {
    expectParse(1.7976931348623157e308, "1.7976931348623157e308");
    expectParse(5E-324, "5E-324");
}

test "mantissa rounding overflow" {
    if (true) {
        return error.SkipZigTest;
    }

    // This results in binary mantissa that is all ones and requires rounding up
    // because it is closer to 1 than to the next smaller float. This is a
    // regression test that the mantissa overflow is handled correctly by
    // increasing the exponent.
    expectParse(1.0, "0.99999999999999999");
    // This number overflows the mantissa *and* the IEEE exponent.
    expectParse(std.math.inf(f64), "1.7976931348623159e308");
}

test "underflow" {
    expectParse(0.0, "2.4e-324");
    expectParse(0.0, "1e-324");
    expectParse(0.0, "9.99999e-325");
    // These are just about halfway between 0 and the smallest float.
    // The first is just below the halfway point, the second just above.
    expectParse(0.0, "2.4703282292062327e-324");
    expectParse(5e-324, "2.4703282292062328e-324");
}

test "overflow" {
    expectParse(std.math.inf(f64), "2e308");
    expectParse(std.math.inf(f64), "1e309");
}

test "table size denormal" {
    expectParse(5e-324, "4.9406564584124654e-324");
}
