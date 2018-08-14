// Copyright 2018 Ulf Adams
//
// The contents of this file may be used under the terms of the Apache License,
// Version 2.0.
//
//    (See accompanying file LICENSE-Apache or copy at
//     http://www.apache.org/licenses/LICENSE-2.0)
//
// Alternatively, the contents of this file may be used under the terms of
// the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE-Boost or copy at
//     https://www.boost.org/LICENSE_1_0.txt)
//
// Unless required by applicable law or agreed to in writing, this software
// is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

// A table of all two-digit numbers. This is used to speed up decimal digit
// generation by copying pairs of digits into the final output.
pub const DIGIT_TABLE = []const u8{
    '0', '0', '0', '1', '0', '2', '0', '3', '0', '4', '0', '5', '0', '6', '0', '7', '0', '8', '0', '9',
    '1', '0', '1', '1', '1', '2', '1', '3', '1', '4', '1', '5', '1', '6', '1', '7', '1', '8', '1', '9',
    '2', '0', '2', '1', '2', '2', '2', '3', '2', '4', '2', '5', '2', '6', '2', '7', '2', '8', '2', '9',
    '3', '0', '3', '1', '3', '2', '3', '3', '3', '4', '3', '5', '3', '6', '3', '7', '3', '8', '3', '9',
    '4', '0', '4', '1', '4', '2', '4', '3', '4', '4', '4', '5', '4', '6', '4', '7', '4', '8', '4', '9',
    '5', '0', '5', '1', '5', '2', '5', '3', '5', '4', '5', '5', '5', '6', '5', '7', '5', '8', '5', '9',
    '6', '0', '6', '1', '6', '2', '6', '3', '6', '4', '6', '5', '6', '6', '6', '7', '6', '8', '6', '9',
    '7', '0', '7', '1', '7', '2', '7', '3', '7', '4', '7', '5', '7', '6', '7', '7', '7', '8', '7', '9',
    '8', '0', '8', '1', '8', '2', '8', '3', '8', '4', '8', '5', '8', '6', '8', '7', '8', '8', '8', '9',
    '9', '0', '9', '1', '9', '2', '9', '3', '9', '4', '9', '5', '9', '6', '9', '7', '9', '8', '9', '9',
};

// Returns e == 0 ? 1 : ceil(log_2(5^e)).
pub fn pow5Bits(e: i32) u32 {
    // This approximation works up to the point that the multiplication overflows at e = 3529.
    // If the multiplication were done in 64 bits, it would fail at 5^4004 which is just greater
    // than 2^9297.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 3528);
    return ((@intCast(u32, e) * 1217359) >> 19) + 1;
}

// Returns floor(log_10(2^e)).
pub fn log10Pow2(e: i32) i32 {
    // The first value this approximation fails for is 2^1651 which is just greater than 10^297.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 1650);
    return @intCast(i32, (@intCast(u32, e) * 78913) >> 18);
}

// Returns floor(log_10(5^e)).
pub fn log10Pow5(e: i32) i32 {
    // The first value this approximation fails for is 5^2621 which is just greater than 10^1832.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 2620);
    return @intCast(i32, (@intCast(u32, e) * 732923) >> 20);
}

fn pow5Factor(n: var) i32 {
    var value = n;
    var count: i32 = 0;

    while (value > 0) : ({
        count += 1;
        value = @divTrunc(value, 5);
    }) {
        if (@mod(value, 5) != 0) {
            return count;
        }
    }
    return 0;
}

// Returns true if value is divisible by 5^p.
pub fn multipleOfPowerOf5(value: var, p: i32) bool {
    std.debug.assert(@typeId(@typeOf(value)) == builtin.TypeId.Int);
    std.debug.assert(!@typeOf(value).is_signed);

    return pow5Factor(value) >= p;
}

pub fn decimalLength(comptime unroll: bool, comptime factor: comptime_int, v: var) u32 {
    const T = @typeOf(v);

    // TODO: Integer pow in std.math
    comptime var pp = 1;
    comptime var j: usize = 1;
    inline while (j < factor) : (j += 1) {
        pp *= 10;
    }

    // TODO: Adjust bounds to fit, we don't need the top check that we are emitting
    // std.debug.assert(v < pp);

    if (unroll) {
        comptime var p10 = pp;
        comptime var i: u32 = factor;

        inline while (i > 0) : (i -= 1) {
            if (v >= p10) {
                return i;
            }
            p10 /= 10;
        }
        return 1;

    } else {
        var p10: T = pp;
        var i: u32 = factor;

        while (i > 0) : (i -= 1) {
            if (v >= p10) {
                return i;
            }
            p10 /= 10;
        }
        return 1;
    }
}

test "ryu.common decimalLength" {
    assert(decimalLength(false, 39, u128(1)) == 1);
    assert(decimalLength(false, 39, u128(9)) == 1);
    assert(decimalLength(false, 39, u128(10)) == 2);
    assert(decimalLength(false, 39, u128(99)) == 2);
    assert(decimalLength(false, 39, u128(100)) == 3);

    const tenPow38: u128 = 100000000000000000000000000000000000000;
    // 10^38 has 39 digits.
    assert(decimalLength(false, 39, tenPow38) == 39);
}

pub fn copySpecialString(result: []u8, d: var) usize {
    if (d.mantissa != 0) {
        std.mem.copy(u8, result, "NaN");
        return 3;
    }
    if (d.sign) {
        result[0] = '-';
    }

    const offset: usize = @boolToInt(d.sign);
    std.mem.copy(u8, result[offset..], "Infinity");
    return offset + 8;
}
