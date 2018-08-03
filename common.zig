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

// Returns e == 0 ? 1 : ceil(log_2(5^e)).
pub inline fn pow5bits(e: i32) u32 {
    // This approximation works up to the point that the multiplication overflows at e = 3529.
    // If the multiplication were done in 64 bits, it would fail at 5^4004 which is just greater
    // than 2^9297.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 3528);
    return ((@intCast(u32, e) * 1217359) >> 19) + 1;
}

// Returns floor(log_10(2^e)).
pub inline fn log10Pow2(e: i32) i32 {
    // The first value this approximation fails for is 2^1651 which is just greater than 10^297.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 1650);
    return @intCast(i32, (@intCast(u32, e) * 78913) >> 18);
}

// Returns floor(log_10(5^e)).
pub inline fn log10Pow5(e: i32) i32 {
    // The first value this approximation fails for is 5^2621 which is just greater than 10^1832.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 2620);
    return @intCast(i32, (@intCast(u32, e) * 732923) >> 20);
}

inline fn pow5Factor(n: var) i32 {
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
pub inline fn multipleOfPowerOf5(value: var, p: i32) bool {
    std.debug.assert(@typeId(@typeOf(value)) == builtin.TypeId.Int);
    std.debug.assert(!@typeOf(value).is_signed);

    return pow5Factor(value) >= p;
}

pub inline fn copy_special_str(result: []u8, sign: bool, exponent: bool, mantissa: bool) usize {
    if (mantissa) {
        std.mem.copy(u8, result, "NaN");
        return 3;
    }
    if (sign) {
        result[0] = '-';
    }

    const offset: usize = @boolToInt(sign);

    if (exponent) {
        std.mem.copy(u8, result[offset..], "Infinity");
        return offset + 8;
    }
    std.mem.copy(u8, result[offset..], "0E0");
    return offset + 3;
}
