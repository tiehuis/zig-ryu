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

const ryu_debug = false;
const ryu_optimize_size = false;

const common = @import("common.zig");

const ryu128_table = @import("ryu128_table.zig");

const log10Pow2 = ryu128_table.log10Pow2;
const pow5Bits = ryu128_table.pow5Bits;
const multipleOfPowerOf5 = ryu128_table.multipleOfPowerOf5;
const log10Pow5 = ryu128_table.log10Pow5;

const computeInvPow5 = ryu128_table.computeInvPow5;
const computePow5 = ryu128_table.computePow5;
const decimalLength = ryu128_table.decimalLength;

const mulShift = ryu128_table.mulShift;

const F128_POW5_INV_BITCOUNT = ryu128_table.F128_POW5_INV_BITCOUNT;
const F128_POW5_BITCOUNT = ryu128_table.F128_POW5_BITCOUNT;
const POW5_TABLE_SIZE = ryu128_table.POW5_TABLE_SIZE;

const DIGIT_TABLE = @import("digit_table.zig").DIGIT_TABLE;

const Decimal128 = struct {
    sign: bool,
    mantissa: u128,
    exponent: i32,
};

pub fn ryuAlloc32(allocator: *std.mem.Allocator, f: f32) ![]u8 {
    var result = try allocator.alloc(u8, 16);
    return ryu32(f, result);
}

pub fn ryu32(f: f32, result: []u8) []u8 {
    const mantissa_bits = std.math.floatMantissaBits(f32);
    const exponent_bits = std.math.floatExponentBits(f32);

    const bits = @bitCast(u32, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

pub fn ryuAlloc64(allocator: *std.mem.Allocator, f: f64) ![]u8 {
    var result = try allocator.alloc(u8, 25);
    return ryu64(f, result);
}

pub fn ryu64(f: f64, result: []u8) []u8 {
    const mantissa_bits = std.math.floatMantissaBits(f64);
    const exponent_bits = std.math.floatExponentBits(f64);

    const bits = @bitCast(u64, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

pub fn ryuAlloc80(allocator: *std.mem.Allocator, f: c_longdouble) ![]u8 {
    // TODO: This bound can be reduced
    var result = try allocator.alloc(u8, 55);
    return ryu80(f, result);
}

pub fn ryu80(f: c_longdouble, result: []u8) []u8 {
    std.debug.assert(c_longdouble.bit_count == 80);

    const mantissa_bits = std.math.floatMantissaBits(c_longdouble);
    const exponent_bits = std.math.floatExponentBits(c_longdouble);

    const bits = @bitCast(u80, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, true);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

pub fn ryuAlloc128(allocator: *std.mem.Allocator, f: f128) ![]u8 {
    var result = try allocator.alloc(u8, 53);
    return ryu128(f, result);
}

pub fn ryu128(f: f128, result: []u8) []u8 {
    const mantissa_bits = std.math.floatMantissaBits(f128);
    const exponent_bits = std.math.floatExponentBits(f128);

    const bits = @bitCast(u128, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

// TODO: Don't accept values as comptime, specialization is likely too costly for code size.
fn floatToDecimal(bits: u128, comptime mantissa_bits: comptime_int, comptime exponent_bits: comptime_int, comptime explicit_leading_bit: bool) Decimal128 {
    if (ryu_debug) {
        std.debug.warn("IN={b}\n", bits);
    }

    const exponent_bias = (1 << (exponent_bits - 1)) - 1;
    const sign = ((bits >> (mantissa_bits + exponent_bits)) & 1) != 0;
    const mantissa = bits & ((1 << mantissa_bits) - 1);
    const exponent = (bits >> mantissa_bits) & ((1 << exponent_bits) - 1);

    // Filter out special case nan and inf
    if (exponent == 0 and mantissa == 0) {
        return Decimal128{
            .sign = sign,
            .mantissa = 0,
            .exponent = 0,
        };
    }
    if (exponent == ((1 << exponent_bits) - 1)) {
        return Decimal128{
            .sign = sign,
            .mantissa = if (explicit_leading_bit) mantissa & ((1 << (mantissa_bits - 1)) - 1) else mantissa,
            .exponent = 0x7fffffff,
        };
    }

    var e2: i32 = undefined;
    var m2: u128 = undefined;

    // We subtract 2 so that the bounds computation has 2 additional bits.
    if (explicit_leading_bit) {
        // mantissa includes the explicit leading bit, so we need to correct for that here
        if (exponent == 0) {
            e2 = 1 - exponent_bias - mantissa_bits + 1 - 2;
        } else {
            e2 = exponent - exponent_bias - mantissa_bits + 1 - 2;
        }
        m2 = mantissa;
    } else {
        if (exponent == 0) {
            e2 = 1 - exponent_bias - mantissa_bits - 2;
            m2 = mantissa;
        } else {
            e2 = @intCast(i32, exponent) - exponent_bias - mantissa_bits - 2;
            m2 = (1 << mantissa_bits) | mantissa;
        }
    }

    const even = m2 & 1 == 0;
    const accept_bounds = even;

    if (ryu_debug) {
        std.debug.warn("-> {} * 2^{}\n", m2, e2 + 2);
    }

    // Step 2: Determine the interval of legal decimal representations.
    const mv = 4 * m2;
    // Implicit bool -> int conversion. True is 1, false is 0.
    const mm_shift = (mantissa != 0) or (exponent <= 1);

    // Step 3: Convert to a decimal power base using 128-bit arithmetic.
    var vr: u128 = undefined;
    var vp: u128 = undefined;
    var vm: u128 = undefined;
    var e10: i32 = undefined;
    var vm_is_trailing_zeros = false;
    var vr_is_trailing_zeros = false;

    if (e2 >= 0) {
        // I tried special-casing q == 0, but there was no effect on performance.
        // This expression is slightly faster than max(0, log10Pow2(e2) - 1).
        const q = log10Pow2(e2) - @intCast(i32, @boolToInt(e2 > 3));
        e10 = q;
        const k = F128_POW5_INV_BITCOUNT + pow5Bits(q) - 1;
        const i = -e2 + @intCast(i32, q) + @intCast(i32, k);

        // No full table, always partial compute
        var pow5: [4]u64 = undefined;
        computeInvPow5(@intCast(u32, q), pow5[0..]);
        vr = mulShift(4 * m2, pow5[0..], i);
        vp = mulShift(4 * m2 + 2, pow5[0..], i);
        vm = mulShift(4 * m2 - 1 - @boolToInt(mm_shift), pow5, i);

        if (ryu_debug) {
            std.debug.warn("{} * 2^{} / 10^{}\n", mv, e2, q);
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        }

        // floor(log_5(2^128)) = 55, this is very conservative
        if (q <= 55) {
            // Only one of mp, mv, and mm can be a multiple of 5, if any.
            if (mv % 5 == 0) {
                vr_is_trailing_zeros = multipleOfPowerOf5(mv, q - 1);
            } else if (accept_bounds) {
                // Same as min(e2 + (~mm & 1), pow5Factor(mm)) >= q
                // <=> e2 + (~mm & 1) >= q && pow5Factor(mm) >= q
                // <=> true && pow5Factor(mm) >= q, since e2 >= q.
                vm_is_trailing_zeros = multipleOfPowerOf5(mv - 1 - @boolToInt(mm_shift), q);
            } else {
                // Same as min(e2 + 1, pow5Factor(mp)) >= q.
                vp -= @boolToInt(multipleOfPowerOf5(mv + 2, q));
            }
        }
    } else {
        // This expression is slightly faster than max(0, log10Pow5(-e2) - 1).
        const q = log10Pow5(-e2) - @intCast(i32, @boolToInt(-e2 > 1));
        e10 = q + e2;
        const i = -e2 - q;
        const k = @intCast(i32, pow5Bits(i)) - F128_POW5_BITCOUNT;
        const j = q - k;

        var pow5: [4]u64 = undefined;
        computePow5(@intCast(u32, i), pow5[0..]);
        vr = mulShift(4 * m2, pow5[0..], j);
        vp = mulShift(4 * m2 + 2, pow5[0..], j);
        vm = mulShift(4 * m2 - 1 - @boolToInt(mm_shift), pow5, j);

        if (ryu_debug) {
            std.debug.warn("{} * 5^{} / 10^{}\n", mv, -e2, q);
            std.debug.warn("{} {} {} {}\n", q, i, k, j);
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        }

        if (q <= 1) {
            // {vr,vp,vm} is trailing zeros if {mv,mp,mm} has at least q trailing 0 bits.
            // mv = 4 m2, so it always has at least two trailing 0 bits.
            vr_is_trailing_zeros = true;
            if (accept_bounds) {
                // mm = mv - 1 - mmShift, so it has 1 trailing 0 bit iff mmShift == 1.
                vm_is_trailing_zeros = mm_shift;
            } else {
                vp -= 1;
            }
        } else if (q < 63) { // TODO(ulfjack): Use a tighter bound here.
            // We need to compute min(ntz(mv), pow5Factor(mv) - e2) >= q-1
            // <=> ntz(mv) >= q-1  &&  pow5Factor(mv) - e2 >= q-1
            // <=> ntz(mv) >= q-1    (e2 is negative and -e2 >= q)
            // <=> (mv & ((1 << (q-1)) - 1)) == 0
            // We also need to make sure that the left shift does not overflow.
            vr_is_trailing_zeros = (mv & ((u128(1) << @intCast(u7, q - 1)) - 1)) == 0;

            if (ryu_debug) {
                std.debug.warn("vr is trailing zeros={}\n", vr_is_trailing_zeros);
            }
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
    var last_removed_digit: u8 = 0;
    var output: u128 = undefined;

    while (vp / 10 > vm / 10) {
        vm_is_trailing_zeros = vm_is_trailing_zeros and vm % 10 == 0;
        vr_is_trailing_zeros = vr_is_trailing_zeros and last_removed_digit == 0;
        last_removed_digit = @intCast(u8, vr % 10);
        vr /= 10;
        vp /= 10;
        vm /= 10;
        removed += 1;
    }

    if (ryu_debug) {
        std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        std.debug.warn("d-10={}\n", vm_is_trailing_zeros);
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

    if (ryu_debug) {
        std.debug.warn("{} %d\n", vr, last_removed_digit);
        std.debug.warn("vr is trailing zeros={}\n", vr_is_trailing_zeros);
    }

    if (vr_is_trailing_zeros and (last_removed_digit == 5) and (vr % 2 == 0)) {
        // Round even if the exact numbers is .....50..0.
        last_removed_digit = 4;
    }
    // We need to take vr+1 if vr is outside bounds or we need to round up.
    output = vr +
        @boolToInt((vr == vm and (!accept_bounds or !vm_is_trailing_zeros)) or (last_removed_digit >= 5));

    var exp = e10 + @intCast(i32, removed);

    if (ryu_debug) {
        std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        std.debug.warn("O={}\n", output);
        std.debug.warn("EXP={}\n", exp);
    }

    return Decimal128{
        .sign = sign,
        .mantissa = output,
        .exponent = exp,
    };
}

inline fn copySpecialString(result: []u8, d: Decimal128) usize {
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

fn decimalToBuffer(v: Decimal128, result: []u8) usize {
    if (v.exponent == 0x7fffffff) {
        return copySpecialString(result, v);
    }

    // Step 5: Print the decimal representation.
    var index: usize = 0;
    if (v.sign) {
        result[index] = '-';
        index += 1;
    }

    var output = v.mantissa;
    const olength = decimalLength(output);

    if (ryu_debug) {
        std.debug.warn("DIGITS={}\n", v.mantissa);
        std.debug.warn("OLEN={}\n", olength);
        std.debug.warn("EXP={}\n", v.exponent + olength);
    }

    // Print the decimal digits.
    var i: usize = 0;
    while (i < olength - 1) : (i += 1) {
        const c = output % 10;
        output /= 10;
        result[index + olength - i] = @intCast(u8, '0' + c);
    }
    result[index] = @intCast(u8, '0' + output % 10);

    // Print decimal point if needed.
    if (olength > 1) {
        result[index + 1] = '.';
        index += olength + 1;
    } else {
        index += 1;
    }

    // Print the exponent.
    result[index] = 'E';
    index += 1;

    var exp = v.exponent + @intCast(i32, olength) - 1;
    if (exp < 0) {
        result[index] = '-';
        index += 1;
        exp = -exp;
    }

    var expu = @intCast(usize, exp);
    const elength = decimalLength(expu);

    var j: usize = 0;
    while (j < elength) : (j += 1) {
        const c = expu % 10;
        expu /= 10;
        result[index + elength - 1 - j] = @intCast(u8, '0' + c);
    }

    index += elength;
    return index;
}

const assert = std.debug.assert;
const al = std.debug.global_allocator;
const eql = std.mem.eql;

test "ryu128 generic to char" {
    const d = Decimal128{
        .sign = false,
        .exponent = -2,
        .mantissa = 12345,
    };

    var result: [53]u8 = undefined;
    const index = decimalToBuffer(d, result[0..]);

    assert(eql(u8, "1.2345E2", result[0..index]));
}

test "ryu128 generic to char long" {
    const d = Decimal128{
        .sign = false,
        .exponent = -20,
        .mantissa = 100000000000000000000000000000000000000,
    };

    var result: [53]u8 = undefined;
    const index = decimalToBuffer(d, result[0..]);

    assert(eql(u8, "1.00000000000000000000000000000000000000E18", result[0..index]));
}

test "ryu128 generic (f32)" {
    assert(eql(u8, "0E0", try ryuAlloc32(al, 0.0)));
    assert(eql(u8, "-0E0", try ryuAlloc32(al, -f32(0.0))));
    assert(eql(u8, "1E0", try ryuAlloc32(al, 1.0)));
    assert(eql(u8, "-1E0", try ryuAlloc32(al, -1.0)));
    assert(eql(u8, "NaN", try ryuAlloc32(al, std.math.nan(f32))));
    assert(eql(u8, "Infinity", try ryuAlloc32(al, std.math.inf(f32))));
    assert(eql(u8, "-Infinity", try ryuAlloc32(al, -std.math.inf(f32))));
    assert(eql(u8, "1.1754944E-38", try ryuAlloc32(al, 1.1754944E-38)));
    assert(eql(u8, "3.4028235E38", try ryuAlloc32(al, @bitCast(f32, u32(0x7f7fffff)))));
    assert(eql(u8, "1E-45", try ryuAlloc32(al, @bitCast(f32, u32(1)))));
    assert(eql(u8, "3.355445E7", try ryuAlloc32(al, 3.355445E7)));
    assert(eql(u8, "9E9", try ryuAlloc32(al, 8.999999E9)));
    assert(eql(u8, "3.436672E10", try ryuAlloc32(al, 3.4366717E10)));
    assert(eql(u8, "3.0540412E5", try ryuAlloc32(al, 3.0540412E5)));
    assert(eql(u8, "8.0990312E3", try ryuAlloc32(al, 8.0990312E3)));
    // Pattern for the first test: 00111001100000000000000000000000
    assert(eql(u8, "2.4414062E-4", try ryuAlloc32(al, 2.4414062E-4)));
    assert(eql(u8, "2.4414062E-3", try ryuAlloc32(al, 2.4414062E-3)));
    assert(eql(u8, "4.3945312E-3", try ryuAlloc32(al, 4.3945312E-3)));
    assert(eql(u8, "6.3476562E-3", try ryuAlloc32(al, 6.3476562E-3)));
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
    assert(eql(u8, "1.2E0", try ryuAlloc32(al, 1.2)));
    assert(eql(u8, "1.23E0", try ryuAlloc32(al, 1.23)));
    assert(eql(u8, "1.234E0", try ryuAlloc32(al, 1.234)));
    assert(eql(u8, "1.2345E0", try ryuAlloc32(al, 1.2345)));
    assert(eql(u8, "1.23456E0", try ryuAlloc32(al, 1.23456)));
    assert(eql(u8, "1.234567E0", try ryuAlloc32(al, 1.234567)));
    assert(eql(u8, "1.2345678E0", try ryuAlloc32(al, 1.2345678)));
    assert(eql(u8, "1.23456735E-36", try ryuAlloc32(al, 1.23456735E-36)));
}

test "ryu128 generic (f64)" {
    assert(eql(u8, "0E0", try ryuAlloc64(al, 0.0)));
    assert(eql(u8, "-0E0", try ryuAlloc64(al, -f64(0.0))));
    assert(eql(u8, "1E0", try ryuAlloc64(al, 1.0)));
    assert(eql(u8, "-1E0", try ryuAlloc64(al, -1.0)));
    assert(eql(u8, "NaN", try ryuAlloc64(al, std.math.nan(f64))));
    assert(eql(u8, "Infinity", try ryuAlloc64(al, std.math.inf(f64))));
    assert(eql(u8, "-Infinity", try ryuAlloc64(al, -std.math.inf(f64))));
    assert(eql(u8, "2.2250738585072014E-308", try ryuAlloc64(al, 2.2250738585072014E-308)));
    assert(eql(u8, "1.7976931348623157E308", try ryuAlloc64(al, @bitCast(f64, u64(0x7fefffffffffffff)))));
    assert(eql(u8, "5E-324", try ryuAlloc64(al, @bitCast(f64, u64(1)))));
    assert(eql(u8, "2.9802322387695312E-8", try ryuAlloc64(al, 2.98023223876953125E-8)));
    assert(eql(u8, "-2.109808898695963E16", try ryuAlloc64(al, -2.109808898695963E16)));
    // TODO: Literal out of range
    //assert(eql(u8, "4.940656E-318", try ryuAlloc64(al, 4.940656E-318)));
    //assert(eql(u8, "1.18575755E-316", try ryuAlloc64(al, 1.18575755E-316)));
    //assert(eql(u8, "2.989102097996E-312", try ryuAlloc64(al, 2.989102097996E-312)));
    assert(eql(u8, "9.0608011534336E15", try ryuAlloc64(al, 9.0608011534336E15)));
    assert(eql(u8, "4.708356024711512E18", try ryuAlloc64(al, 4.708356024711512E18)));
    assert(eql(u8, "9.409340012568248E18", try ryuAlloc64(al, 9.409340012568248E18)));
    assert(eql(u8, "1.2345678E0", try ryuAlloc64(al, 1.2345678)));
    assert(eql(u8, "5.764607523034235E39", try ryuAlloc64(al, @bitCast(f64, u64(0x4830F0CF064DD592)))));
    assert(eql(u8, "1.152921504606847E40", try ryuAlloc64(al, @bitCast(f64, u64(0x4840F0CF064DD592)))));
    assert(eql(u8, "2.305843009213694E40", try ryuAlloc64(al, @bitCast(f64, u64(0x4850F0CF064DD592)))));

    assert(eql(u8, "1E0", try ryuAlloc64(al, 1))); // already tested in Basic
    assert(eql(u8, "1.2E0", try ryuAlloc64(al, 1.2)));
    assert(eql(u8, "1.23E0", try ryuAlloc64(al, 1.23)));
    assert(eql(u8, "1.234E0", try ryuAlloc64(al, 1.234)));
    assert(eql(u8, "1.2345E0", try ryuAlloc64(al, 1.2345)));
    assert(eql(u8, "1.23456E0", try ryuAlloc64(al, 1.23456)));
    assert(eql(u8, "1.234567E0", try ryuAlloc64(al, 1.234567)));
    assert(eql(u8, "1.2345678E0", try ryuAlloc64(al, 1.2345678))); // already tested in Regression
    assert(eql(u8, "1.23456789E0", try ryuAlloc64(al, 1.23456789)));
    assert(eql(u8, "1.234567895E0", try ryuAlloc64(al, 1.234567895))); // 1.234567890 would be trimmed
    assert(eql(u8, "1.2345678901E0", try ryuAlloc64(al, 1.2345678901)));
    assert(eql(u8, "1.23456789012E0", try ryuAlloc64(al, 1.23456789012)));
    assert(eql(u8, "1.234567890123E0", try ryuAlloc64(al, 1.234567890123)));
    assert(eql(u8, "1.2345678901234E0", try ryuAlloc64(al, 1.2345678901234)));
    assert(eql(u8, "1.23456789012345E0", try ryuAlloc64(al, 1.23456789012345)));
    assert(eql(u8, "1.234567890123456E0", try ryuAlloc64(al, 1.234567890123456)));
    assert(eql(u8, "1.2345678901234567E0", try ryuAlloc64(al, 1.2345678901234567)));

    // Test 32-bit chunking
    assert(eql(u8, "4.294967294E0", try ryuAlloc64(al, 4.294967294))); // 2^32 - 2
    assert(eql(u8, "4.294967295E0", try ryuAlloc64(al, 4.294967295))); // 2^32 - 1
    assert(eql(u8, "4.294967296E0", try ryuAlloc64(al, 4.294967296))); // 2^32
    assert(eql(u8, "4.294967297E0", try ryuAlloc64(al, 4.294967297))); // 2^32 + 1
    assert(eql(u8, "4.294967298E0", try ryuAlloc64(al, 4.294967298))); // 2^32 + 2
}

// TODO: unreachable: /home/me/src/zig/src/ir.cpp:eval_const_expr_implicit_cast:9320
// See https://github.com/ziglang/zig/issues/1188.
test "ryu128 generic (f80/c_longdouble)" {
    if (true) { // c_longdouble.bit_count != 80) {
        return error.SkipZigTest;
    }

    assert(eql(u8, "0E0", try ryuAlloc80(al, 0.0)));
    assert(eql(u8, "-0E0", try ryuAlloc80(al, -c_longdouble(0.0))));
    assert(eql(u8, "1E0", try ryuAlloc80(al, 1.0)));
    assert(eql(u8, "-1E0", try ryuAlloc80(al, -1.0)));
    assert(eql(u8, "NaN", try ryuAlloc80(al, std.math.nan(c_longdouble))));
    assert(eql(u8, "Infinity", try ryuAlloc80(al, std.math.inf(c_longdouble))));
    assert(eql(u8, "-Infinity", try ryuAlloc80(al, -std.math.inf(c_longdouble))));

    assert(eql(u8, "2.2250738585072014E-308", try ryuAlloc80(al, 2.2250738585072014E-308)));
    assert(eql(u8, "2.98023223876953125E-8", try ryuAlloc80(al, 2.98023223876953125E-8)));
    assert(eql(u8, "-2.109808898695963E16", try ryuAlloc80(al, -2.109808898695963E16)));
    // TODO: Literal out of range
    //assert(eql(u8, "4.940656E-318", try ryuAlloc80(al, 4.940656E-318)));
    //assert(eql(u8, "1.18575755E-316", try ryuAlloc80(al, 1.18575755E-316)));
    //assert(eql(u8, "2.989102097996E-312", try ryuAlloc80(al, 2.989102097996E-312)));
    assert(eql(u8, "9.0608011534336E15", try ryuAlloc80(al, 9.0608011534336E15)));
    assert(eql(u8, "4.708356024711512E18", try ryuAlloc80(al, 4.708356024711512E18)));
    assert(eql(u8, "9.409340012568248E18", try ryuAlloc80(al, 9.409340012568248E18)));
    assert(eql(u8, "1.2345678E0", try ryuAlloc80(al, 1.2345678)));
}
