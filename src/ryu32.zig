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

// Runtime compiler options:
// -DRYU_DEBUG Generate verbose debugging output to stdout.

const std = @import("std");

const ryu_debug = false;

use @import("common.zig");
use @import("digit_table.zig");

// This table is generated by PrintFloatLookupTable.
const FLOAT_POW5_INV_BITCOUNT = 59;
const FLOAT_POW5_INV_SPLIT = []const u64{
    576460752303423489, 461168601842738791, 368934881474191033, 295147905179352826,
    472236648286964522, 377789318629571618, 302231454903657294, 483570327845851670,
    386856262276681336, 309485009821345069, 495176015714152110, 396140812571321688,
    316912650057057351, 507060240091291761, 405648192073033409, 324518553658426727,
    519229685853482763, 415383748682786211, 332306998946228969, 531691198313966350,
    425352958651173080, 340282366920938464, 544451787073501542, 435561429658801234,
    348449143727040987, 557518629963265579, 446014903970612463, 356811923176489971,
    570899077082383953, 456719261665907162, 365375409332725730,
};

const FLOAT_POW5_BITCOUNT = 61;
const FLOAT_POW5_SPLIT = []const u64{
    1152921504606846976, 1441151880758558720, 1801439850948198400, 2251799813685248000,
    1407374883553280000, 1759218604441600000, 2199023255552000000, 1374389534720000000,
    1717986918400000000, 2147483648000000000, 1342177280000000000, 1677721600000000000,
    2097152000000000000, 1310720000000000000, 1638400000000000000, 2048000000000000000,
    1280000000000000000, 1600000000000000000, 2000000000000000000, 1250000000000000000,
    1562500000000000000, 1953125000000000000, 1220703125000000000, 1525878906250000000,
    1907348632812500000, 1192092895507812500, 1490116119384765625, 1862645149230957031,
    1164153218269348144, 1455191522836685180, 1818989403545856475, 2273736754432320594,
    1421085471520200371, 1776356839400250464, 2220446049250313080, 1387778780781445675,
    1734723475976807094, 2168404344971008868, 1355252715606880542, 1694065894508600678,
    2117582368135750847, 1323488980084844279, 1654361225106055349, 2067951531382569187,
    1292469707114105741, 1615587133892632177, 2019483917365790221,
};

fn mulShift(m: u32, factor: u64, shift: i32) u32 {
    std.debug.assert(shift > 32);

    const factor_lo = @truncate(u32, factor);
    const factor_hi = @intCast(u32, factor >> 32);
    const bits0 = u64(m) * factor_lo;
    const bits1 = u64(m) * factor_hi;

    const sum = (bits0 >> 32) + bits1;
    const shifted_sum = sum >> @intCast(u6, shift - 32);
    return @intCast(u32, shifted_sum);
}

fn mulPow5InvDivPow2(m: u32, q: u32, j: i32) u32 {
    return mulShift(m, FLOAT_POW5_INV_SPLIT[q], j);
}

fn mulPow5DivPow2(m: u32, i: u32, j: i32) u32 {
    return mulShift(m, FLOAT_POW5_SPLIT[i], j);
}

fn decimalLength(v: u32) usize {
    // Function precondition: v is not a 10-digit number.
    // (9 digits are sufficient for round-tripping.)
    std.debug.assert(v < 1000000000);

    comptime var n = 100000000;
    comptime var i = 9;

    inline while (n != 1) : ({
        n /= 10;
        i -= 1;
    }) {
        if (v >= n) {
            return i;
        }
    }

    return i;
}

const mantissa_bits = std.math.floatMantissaBits(f32);
const exponent_bits = std.math.floatExponentBits(f32);
const exponent_bias = (1 << (exponent_bits - 1)) - 1;

const Decimal32 = struct {
    mantissa: u32,
    exponent: i32,
};

pub fn ryuAlloc32(allocator: *std.mem.Allocator, f: f32) ![]u8 {
    var result = try allocator.alloc(u8, 16);
    return ryu32(f, result);
}

pub fn ryu32(f: f32, result: []u8) []u8 {
    // Step 1: Decode the floating-point number, and unify normalized and subnormal cases.
    // This only works on little-endian architectures.
    const bits = @bitCast(u32, f);

    // Decode bits into sign, mantissa, and exponent.
    const sign = ((bits >> (mantissa_bits + exponent_bits)) & 1) != 0;
    const mantissa = bits & ((1 << mantissa_bits) - 1);
    const exponent = (bits >> mantissa_bits) & ((1 << exponent_bits) - 1);

    // Case distinction; exit early for the easy cases.
    if (exponent == ((1 << exponent_bits) - 1) or (exponent == 0 and mantissa == 0)) {
        const index = copySpecialString(result, sign, exponent != 0, mantissa != 0);
        return result[0..index];
    }

    const v = floatToDecimal(mantissa, exponent);
    const index = decimalToBuffer(v, sign, result);
    return result[0..index];
}

fn floatToDecimal(mantissa: u32, exponent: u32) Decimal32 {
    if (ryu_debug) {
        const bits = (exponent << mantissa_bits) | mantissa;
        std.debug.warn("IN={b}\n", bits);
    }

    var e2: i32 = undefined;
    var m2: u32 = undefined;

    if (exponent == 0) {
        // We subtract 2 so that the bounds computation has 2 additional bits.
        e2 = 1 - exponent_bias - mantissa_bits - 2;
        m2 = mantissa;
    } else {
        e2 = @intCast(i32, exponent) - exponent_bias - mantissa_bits - 2;
        m2 = (1 << mantissa_bits) | mantissa;
    }
    const even = (m2 & 1) == 0;
    const accept_bounds = even;

    if (ryu_debug) {
        std.debug.warn("E={} M={}\n", e2, m2);
    }

    // Step 2: Determine the interval of legal decimal representations.
    const mv = 4 * m2;
    const mp = 4 * m2 + 2;
    const mm = 4 * m2 - (if ((m2 != (1 << mantissa_bits)) or (exponent <= 1)) u32(2) else 1);

    // Step 3: Convert to a decimal power base using 64-bit arithmetic.
    var vr: u32 = undefined;
    var vp: u32 = undefined;
    var vm: u32 = undefined;
    var e10: i32 = undefined;
    var vm_is_trailing_zeros = false;
    var vr_is_trailing_zeros = false;
    var last_removed_digit: u8 = 0;

    if (e2 >= 0) {
        const q = log10Pow2(e2);
        e10 = q;
        const k = FLOAT_POW5_INV_BITCOUNT + pow5Bits(q) - 1;
        const i = -e2 + @intCast(i32, q) + @intCast(i32, k);
        vr = mulPow5InvDivPow2(mv, @intCast(u32, q), i);
        vp = mulPow5InvDivPow2(mp, @intCast(u32, q), i);
        vm = mulPow5InvDivPow2(mm, @intCast(u32, q), i);

        if (ryu_debug) {
            std.debug.warn("{} * 2^{} / 10^{}\n", mv, e2, q);
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        }

        if (q != 0 and ((vp - 1) / 10 <= vm / 10)) {
            // We need to know one removed digit even if we are not going to loop below. We could use
            // q = X - 1 above, except that would require 33 bits for the result, and we've found that
            // 32-bit arithmetic is faster even on 64-bit machines.
            const l = FLOAT_POW5_INV_BITCOUNT + pow5Bits(q - 1) - 1;
            last_removed_digit = @intCast(u8, (mulPow5InvDivPow2(mv, @intCast(u32, q - 1), -e2 + @intCast(i32, q) - 1 + @intCast(i32, l)) % 10));
        }
        if (q <= 9) {
            // Only one of mp, mv, and mm can be a multiple of 5, if any.
            if (mv % 5 == 0) {
                vr_is_trailing_zeros = multipleOfPowerOf5(mv, q);
            } else {
                if (accept_bounds) {
                    vm_is_trailing_zeros = multipleOfPowerOf5(mm, q);
                } else {
                    vp -= @boolToInt(multipleOfPowerOf5(mp, q));
                }
            }
        }
    } else {
        const q = log10Pow5(-e2);
        e10 = q + e2;
        const i = -e2 - q;
        const k = @intCast(i32, pow5Bits(i)) - FLOAT_POW5_BITCOUNT;
        var j = q - @intCast(i32, k);
        vr = mulPow5DivPow2(mv, @intCast(u32, i), j);
        vp = mulPow5DivPow2(mp, @intCast(u32, i), j);
        vm = mulPow5DivPow2(mm, @intCast(u32, i), j);

        if (ryu_debug) {
            std.debug.warn("{} * 5^{} / 10^{}\n", mv, -e2, q);
            std.debug.warn("{} {} {} {}\n", q, i, k, j);
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        }

        if (q != 0 and ((vp - 1) / 10 <= vm / 10)) {
            j = @intCast(i32, q) - 1 - (@intCast(i32, pow5Bits(i + 1)) - @intCast(i32, FLOAT_POW5_BITCOUNT));
            last_removed_digit = @intCast(u8, mulPow5DivPow2(mv, @intCast(u32, i + 1), j) % 10);
        }
        if (q <= 1) {
            vr_is_trailing_zeros = (~mv & 1) >= @intCast(u32, q);
            if (accept_bounds) {
                vm_is_trailing_zeros = (~mm & 1) >= @intCast(u32, q);
            } else {
                vp -= 1;
            }
        } else if (q < 31) { // TODO(ulfjack): Use a tighter bound here.
            vr_is_trailing_zeros = (mv & ((u32(1) << @intCast(u5, (q - 1))) - 1)) == 0;
        }
    }

    if (ryu_debug) {
        std.debug.warn("e10={}\n", e10);
        std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        std.debug.warn("vm is trailing zeros={}\n", vm_is_trailing_zeros);
        std.debug.warn("vr is trailing zeros={}\n", vr_is_trailing_zeros);
    }

    // Step 4: Find the shortest decimal representation in the interval of legal representations.
    var removed: u32 = 0;
    var output: u32 = undefined;
    if (vm_is_trailing_zeros or vr_is_trailing_zeros) {
        // General case, which happens rarely.
        while (vp / 10 > vm / 10) {
            vm_is_trailing_zeros = vm_is_trailing_zeros and vm % 10 == 0;
            vr_is_trailing_zeros = vr_is_trailing_zeros and last_removed_digit == 0;
            last_removed_digit = @intCast(u8, vr % 10);
            vr /= 10;
            vp /= 10;
            vm /= 10;
            removed += 1;
        }
        if (vm_is_trailing_zeros) {
            while (vm % 10 == 0) {
                vr_is_trailing_zeros = vr_is_trailing_zeros and last_removed_digit == 0;
                last_removed_digit = @intCast(u8, vr % 10);
                vr /= 10;
                vp /= 10;
                vm /= 10;
                removed += 1;
            }
        }
        if (vr_is_trailing_zeros and (last_removed_digit == 5) and (vr % 2 == 0)) {
            // Round down not up if the number ends in X50000.
            last_removed_digit = 4;
        }
        // We need to take vr+1 if vr is outside bounds or we need to round up.
        output = vr +
            @boolToInt((vr == vm and (!accept_bounds or !vm_is_trailing_zeros)) or (last_removed_digit >= 5));
    } else {
        // Common case.
        while (vp / 10 > vm / 10) {
            last_removed_digit = @intCast(u8, vr % 10);
            vr /= 10;
            vp /= 10;
            vm /= 10;
            removed += 1;
        }
        // We need to take vr+1 if vr is outside bounds or we need to round up.
        output = vr + @boolToInt((vr == vm) or (last_removed_digit >= 5));
    }

    return Decimal32{
        .mantissa = output,
        .exponent = e10 + @intCast(i32, removed) - 1,
    };
}

fn decimalToBuffer(v: Decimal32, sign: bool, result: []u8) usize {
    var output = v.mantissa;
    const olength = decimalLength(output);

    // Step 5: Print the decimal representation.
    var index: usize = 0;
    if (sign) {
        result[index] = '-';
        index += 1;
    }

    // Print the decimal digits. The following code is equivalent to:
    //
    // var i: usize = 0;
    // while (i < olength - 1) : (i += 1) {
    //     const c = output % 10;
    //     output /= 10;
    //     result[index + olength - i] = @intCast(u8, '0' + c);
    // }
    // result[index] = @intCast(u8, '0' + output % 10);
    var i: usize = 0;
    while (output >= 10000) {
        const c = output % 10000;
        output /= 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;

        // TODO: See https://github.com/ziglang/zig/issues/1329
        result[index + olength - i - 1 + 0] = DIGIT_TABLE[c0 + 0];
        result[index + olength - i - 1 + 1] = DIGIT_TABLE[c0 + 1];
        result[index + olength - i - 3 + 0] = DIGIT_TABLE[c1 + 0];
        result[index + olength - i - 3 + 1] = DIGIT_TABLE[c1 + 1];
        i += 4;
    }
    if (output >= 100) {
        const c = (output % 100) << 1;
        output /= 100;

        result[index + olength - i - 1 + 0] = DIGIT_TABLE[c + 0];
        result[index + olength - i - 1 + 1] = DIGIT_TABLE[c + 1];
        i += 2;
    }
    if (output >= 10) {
        const c = output << 1;
        result[index + olength - i] = DIGIT_TABLE[c + 1];
        result[index] = DIGIT_TABLE[c];
    } else {
        result[index] = @intCast(u8, '0' + output);
    }

    // Print decimal point if needed.
    if (olength > 1) {
        result[index + 1] = '.';
        index += olength + 1;
    } else {
        index += 1;
    }

    // Print the exponent.
    result[index] = 'E';
    var exp = v.exponent + @intCast(i32, olength);
    index += 1;
    if (exp < 0) {
        result[index] = '-';
        index += 1;
        exp = -exp;
    }

    var expu = @intCast(usize, exp);

    if (exp >= 10) {
        result[index + 0] = DIGIT_TABLE[2 * expu + 0];
        result[index + 1] = DIGIT_TABLE[2 * expu + 1];
        index += 2;
    } else {
        result[index] = @intCast(u8, '0' + expu);
        index += 1;
    }

    return index;
}

const assert = std.debug.assert;
const al = std.debug.global_allocator;
const eql = std.mem.eql;

test "ryu32 basic" {
    assert(eql(u8, "0E0", try ryuAlloc32(al, 0.0)));
    assert(eql(u8, "-0E0", try ryuAlloc32(al, -f32(0.0))));
    assert(eql(u8, "1E0", try ryuAlloc32(al, 1.0)));
    assert(eql(u8, "-1E0", try ryuAlloc32(al, -1.0)));
    assert(eql(u8, "NaN", try ryuAlloc32(al, std.math.nan(f32))));
    assert(eql(u8, "Infinity", try ryuAlloc32(al, std.math.inf(f32))));
    assert(eql(u8, "-Infinity", try ryuAlloc32(al, -std.math.inf(f32))));
}

test "ryu32 switch to subnormal" {
    assert(eql(u8, "1.1754944E-38", try ryuAlloc32(al, 1.1754944e-38)));
}

test "ryu32 min and max" {
    assert(eql(u8, "3.4028235E38", try ryuAlloc32(al, @bitCast(f32, u32(0x7f7fffff)))));
    assert(eql(u8, "1E-45", try ryuAlloc32(al, @bitCast(f32, u32(1)))));
}

// Check that we return the exact boundary if it is the shortest
// representation, but only if the original floating point number is even.
test "ryu32 boundary round even" {
    assert(eql(u8, "3.355445E7", try ryuAlloc32(al, 3.355445e7)));
    assert(eql(u8, "9E9", try ryuAlloc32(al, 8.999999e9)));
    assert(eql(u8, "3.436672E10", try ryuAlloc32(al, 3.4366717e10)));
}

// If the exact value is exactly halfway between two shortest representations,
// then we round to even. It seems like this only makes a difference if the
// last two digits are ...2|5 or ...7|5, and we cut off the 5.
test "ryu32 exact value round even" {
    assert(eql(u8, "3.0540412E5", try ryuAlloc32(al, 3.0540412E5)));
    assert(eql(u8, "8.0990312E3", try ryuAlloc32(al, 8.0990312E3)));
}

test "ryu32 lots of trailing zeros" {
    // Pattern for the first test: 00111001100000000000000000000000
    assert(eql(u8, "2.4414062E-4", try ryuAlloc32(al, 2.4414062E-4)));
    assert(eql(u8, "2.4414062E-3", try ryuAlloc32(al, 2.4414062E-3)));
    assert(eql(u8, "4.3945312E-3", try ryuAlloc32(al, 4.3945312E-3)));
    assert(eql(u8, "6.3476562E-3", try ryuAlloc32(al, 6.3476562E-3)));
}

test "ryu32 regression" {
    assert(eql(u8, "4.7223665E21", try ryuAlloc32(al, 4.7223665E21)));
    assert(eql(u8, "8.388608E6", try ryuAlloc32(al, 8388608.0)));
    assert(eql(u8, "1.6777216E7", try ryuAlloc32(al, 1.6777216E7)));
    assert(eql(u8, "3.3554436E7", try ryuAlloc32(al, 3.3554436E7)));
    assert(eql(u8, "6.7131496E7", try ryuAlloc32(al, 6.7131496E7)));
    assert(eql(u8, "1.9310392E-38", try ryuAlloc32(al, 1.9310392E-38)));
    assert(eql(u8, "-2.47E-43", try ryuAlloc32(al, -2.47E-43)));
    assert(eql(u8, "1.993244E-38", try ryuAlloc32(al, 1.993244E-38)));
    assert(eql(u8, "4.1039004E3", try ryuAlloc32(al, 4103.9003)));
    assert(eql(u8, "5.3399997E9", try ryuAlloc32(al, 5.3399997E9)));
    assert(eql(u8, "6.0898E-39", try ryuAlloc32(al, 6.0898E-39)));
    assert(eql(u8, "1.0310042E-3", try ryuAlloc32(al, 0.0010310042)));
    assert(eql(u8, "2.882326E17", try ryuAlloc32(al, 2.8823261E17)));
    // MSVC rounds this up to the next higher floating point number
    //assert(eql(u8, "7.038531E-26", try ryuAlloc32(al, 7.038531E-26)));
    assert(eql(u8, "7.038531E-26", try ryuAlloc32(al, 7.0385309E-26)));
    assert(eql(u8, "9.223404E17", try ryuAlloc32(al, 9.2234038E17)));
    assert(eql(u8, "6.710887E7", try ryuAlloc32(al, 6.7108872E7)));
    assert(eql(u8, "1E-44", try ryuAlloc32(al, 1.0E-44)));
    assert(eql(u8, "2.816025E14", try ryuAlloc32(al, 2.816025E14)));
    assert(eql(u8, "9.223372E18", try ryuAlloc32(al, 9.223372E18)));
    assert(eql(u8, "1.5846086E29", try ryuAlloc32(al, 1.5846085E29)));
    assert(eql(u8, "1.1811161E19", try ryuAlloc32(al, 1.1811161E19)));
    assert(eql(u8, "5.368709E18", try ryuAlloc32(al, 5.368709E18)));
    assert(eql(u8, "4.6143166E18", try ryuAlloc32(al, 4.6143165E18)));
    assert(eql(u8, "7.812537E-3", try ryuAlloc32(al, 0.007812537)));
    assert(eql(u8, "1E-45", try ryuAlloc32(al, 1.4E-45)));
    assert(eql(u8, "1.18697725E20", try ryuAlloc32(al, 1.18697724E20)));
    assert(eql(u8, "1.00014165E-36", try ryuAlloc32(al, 1.00014165E-36)));
    assert(eql(u8, "2E2", try ryuAlloc32(al, 200.0)));
    assert(eql(u8, "3.3554432E7", try ryuAlloc32(al, 3.3554432E7)));
}
