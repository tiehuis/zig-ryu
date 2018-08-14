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

const common = @import("common.zig");
const table = @import("ryu64_table.zig");
const helper = common;
const DIGIT_TABLE = common.DIGIT_TABLE;

const ryu_optimize_size = builtin.mode == builtin.Mode.ReleaseSmall;

pub fn mulShift(m: u64, mul: []const u64, j: i32) u64 {
    const b0 = u128(m) * mul[0];
    const b2 = u128(m) * mul[1];
    return @truncate(u64, (((b0 >> 64) + b2) >> @intCast(u7, (j - 64))));
}

pub fn mulShiftAll(m: u64, mul: []const u64, j: i32, vp: *u64, vm: *u64, mm_shift: u32) u64 {
    vp.* = mulShift(4 * m + 2, mul, j);
    vm.* = mulShift(4 * m - 1 - mm_shift, mul, j);
    return mulShift(4 * m, mul, j);
}

const Decimal64 = struct {
    sign: bool,
    mantissa: u64,
    exponent: i32,
};

pub fn ryu64(f: f64, result: []u8) []u8 {
    std.debug.assert(result.len >= 25);

    const mantissa_bits = std.math.floatMantissaBits(f64);
    const exponent_bits = std.math.floatExponentBits(f64);

    const bits = @bitCast(u64, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

fn floatToDecimal(bits: u64, mantissa_bits: u6, exponent_bits: u6, explicit_leading_bit: bool) Decimal64 {
    const exponent_bias = (u64(1) << (exponent_bits - 1)) - 1;
    const sign = ((bits >> (mantissa_bits + exponent_bits)) & 1) != 0;
    const mantissa = bits & ((u64(1) << mantissa_bits) - 1);
    const exponent = (bits >> mantissa_bits) & ((u64(1) << exponent_bits) - 1);

    // Filter out special case nan and inf
    if (exponent == 0 and mantissa == 0) {
        return Decimal64{
            .sign = sign,
            .mantissa = 0,
            .exponent = 0,
        };
    }
    if (exponent == ((u64(1) << exponent_bits) - 1)) {
        return Decimal64{
            .sign = sign,
            .mantissa = if (explicit_leading_bit) mantissa & ((u64(1) << (mantissa_bits - 1)) - 1) else mantissa,
            .exponent = 0x7fffffff,
        };
    }

    var e2: i32 = undefined;
    var m2: u64 = undefined;

    // We subtract 2 so that the bounds computation has 2 additional bits.
    if (explicit_leading_bit) {
        // mantissa includes the explicit leading bit, so we need to correct for that here
        if (exponent == 0) {
            e2 = 1 - @intCast(i32, exponent_bias) - @intCast(i32, mantissa_bits) + 1 - 2;
        } else {
            e2 = @intCast(i32, exponent) - @intCast(i32, exponent_bias) - @intCast(i32, mantissa_bits) + 1 - 2;
        }
        m2 = mantissa;
    } else {
        if (exponent == 0) {
            e2 = 1 - @intCast(i32, exponent_bias) - @intCast(i32, mantissa_bits) - 2;
            m2 = mantissa;
        } else {
            e2 = @intCast(i32, exponent) - @intCast(i32, exponent_bias) - @intCast(i32, mantissa_bits) - 2;
            m2 = (u64(1) << mantissa_bits) | mantissa;
        }
    }

    const even = m2 & 1 == 0;
    const accept_bounds = even;

    // Step 2: Determine the interval of legal decimal representations.
    const mv = 4 * m2;
    // Implicit bool -> int conversion. True is 1, false is 0.
    const mm_shift = mantissa != 0 or exponent <= 1;
    // We would compute mp and mm like this:
    //  uint64_t mp = 4 * m2 + 2;
    //  uint64_t mm = mv - 1 - mm_shift;

    // Step 3: Convert to a decimal power base using 128-bit arithmetic.
    var vr: u64 = undefined;
    var vp: u64 = undefined;
    var vm: u64 = undefined;
    var e10: i32 = undefined;
    var vm_is_trailing_zeros = false;
    var vr_is_trailing_zeros = false;

    if (e2 >= 0) {
        // I tried special-casing q == 0, but there was no effect on performance.
        // This expression is slightly faster than max(0, log10Pow2(e2) - 1).
        const q = helper.log10Pow2(e2) - @intCast(i32, @boolToInt(e2 > 3));
        e10 = q;
        const k = table.double_pow5_inv_bitcount + helper.pow5Bits(q) - 1;
        const i = -e2 + @intCast(i32, q) + @intCast(i32, k);

        if (ryu_optimize_size) {
            var pow5: [2]u64 = undefined;
            table.computeInvPow5(@intCast(u32, q), pow5[0..]);
            vr = mulShiftAll(m2, pow5, i, &vp, &vm, @boolToInt(mm_shift));
        } else {
            vr = mulShiftAll(m2, table.double_pow5_inv_split[@intCast(usize, q)], i, &vp, &vm, @boolToInt(mm_shift));
        }

        if (q <= 21) {
            // This should use q <= 22, but I think 21 is also safe. Smaller values
            // may still be safe, but it's more difficult to reason about them.
            // Only one of mp, mv, and mm can be a multiple of 5, if any.
            if (mv % 5 == 0) {
                vr_is_trailing_zeros = helper.multipleOfPowerOf5(mv, q);
            } else if (accept_bounds) {
                // Same as min(e2 + (~mm & 1), pow5Factor(mm)) >= q
                // <=> e2 + (~mm & 1) >= q && pow5Factor(mm) >= q
                // <=> true && pow5Factor(mm) >= q, since e2 >= q.
                vm_is_trailing_zeros = helper.multipleOfPowerOf5(mv - 1 - @boolToInt(mm_shift), q);
            } else {
                // Same as min(e2 + 1, pow5Factor(mp)) >= q.
                vp -= @boolToInt(helper.multipleOfPowerOf5(mv + 2, q));
            }
        }
    } else {
        // This expression is slightly faster than max(0, log10Pow5(-e2) - 1).
        const q = helper.log10Pow5(-e2) - @intCast(i32, @boolToInt(-e2 > 1));
        e10 = q + e2;
        const i = -e2 - q;
        const k = @intCast(i32, helper.pow5Bits(i)) - table.double_pow5_bitcount;
        const j = q - k;

        if (ryu_optimize_size) {
            var pow5: [2]u64 = undefined;
            table.computePow5(@intCast(u32, i), pow5[0..]);
            vr = mulShiftAll(m2, pow5, j, &vp, &vm, @boolToInt(mm_shift));
        } else {
            vr = mulShiftAll(m2, table.double_pow5_split[@intCast(usize, i)], j, &vp, &vm, @boolToInt(mm_shift));
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
            vr_is_trailing_zeros = (mv & ((u64(1) << @intCast(u6, q - 1)) - 1)) == 0;
        }
    }

    // Step 4: Find the shortest decimal representation in the interval of legal representations.
    var removed: u32 = 0;
    var last_removed_digit: u8 = 0;
    var output: u64 = undefined;
    // On average, we remove ~2 digits.
    if (vm_is_trailing_zeros or vr_is_trailing_zeros) {
        // General case, which happens rarely (<1%).
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
            // Round even if the exact numbers is .....50..0.
            last_removed_digit = 4;
        }
        // We need to take vr+1 if vr is outside bounds or we need to round up.
        output = vr +
            @boolToInt((vr == vm and (!accept_bounds or !vm_is_trailing_zeros)) or (last_removed_digit >= 5));
    } else {
        // Specialized for the common case (~99.3%). Percentags below are relative to this.
        var round_up = false;
        if (vp / 100 > vm / 100) { // Optimization: remove two digits at a time (~86.2%)
            round_up = vr % 100 >= 50;
            vr /= 100;
            vp /= 100;
            vm /= 100;
            removed += 2;
        }

        // Loop iterations below (approximately), without optimization above:
        // 0: 0.03%, 1: 13.8%, 2: 70.6%, 3: 14.0%, 4: 1.40%, 5: 0.14%, 6+: 0.02%
        // Loop iterations below (approximately), with optimization above:
        // 0: 70.6%, 1: 27.8%, 2: 1.40%, 3: 0.14%, 4+: 0.02%
        while (vp / 10 > vm / 10) {
            round_up = vr % 10 >= 5;
            vr /= 10;
            vp /= 10;
            vm /= 10;
            removed += 1;
        }

        // We need to take vr+1 if vr is outside bounds or we need to round up.
        output = vr + @boolToInt(vr == vm or round_up);
    }

    var exp = e10 + @intCast(i32, removed);

    return Decimal64{
        .sign = sign,
        .mantissa = output,
        .exponent = exp,
    };
}

fn decimalToBuffer(v: Decimal64, result: []u8) usize {
    if (v.exponent == 0x7fffffff) {
        return common.copySpecialString(result, v);
    }

    // Step 5: Print the decimal representation.
    var index: usize = 0;
    if (v.sign) {
        result[index] = '-';
        index += 1;
    }

    var output = v.mantissa;
    const olength = common.decimalLength(true, 17, output);

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
    // We prefer 32-bit operations, even on 64-bit platforms.
    // We have at most 17 digits, and 32-bit unsigned int can store 9. We cut off
    // 8 in the first iteration, so the remainder will fit into a 32-bit int.
    if ((output >> 32) != 0) {
        var output2 = @truncate(u32, output % 100000000);
        output /= 100000000;

        const c = output2 % 10000;
        output2 /= 10000;
        const d = output2 % 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;
        const d0 = (d % 100) << 1;
        const d1 = (d / 100) << 1;

        // TODO: See https://github.com/ziglang/zig/issues/1329
        result[index + olength - i - 1 + 0] = DIGIT_TABLE[c0 + 0];
        result[index + olength - i - 1 + 1] = DIGIT_TABLE[c0 + 1];
        result[index + olength - i - 3 + 0] = DIGIT_TABLE[c1 + 0];
        result[index + olength - i - 3 + 1] = DIGIT_TABLE[c1 + 1];
        result[index + olength - i - 5 + 0] = DIGIT_TABLE[d0 + 0];
        result[index + olength - i - 5 + 1] = DIGIT_TABLE[d0 + 1];
        result[index + olength - i - 7 + 0] = DIGIT_TABLE[d1 + 0];
        result[index + olength - i - 7 + 1] = DIGIT_TABLE[d1 + 1];
        i += 8;
    }

    var output2 = @truncate(u32, output);
    while (output2 >= 10000) {
        const c = @truncate(u32, output2 % 10000);
        output2 /= 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;

        result[index + olength - i - 1 + 0] = DIGIT_TABLE[c0 + 0];
        result[index + olength - i - 1 + 1] = DIGIT_TABLE[c0 + 1];
        result[index + olength - i - 3 + 0] = DIGIT_TABLE[c1 + 0];
        result[index + olength - i - 3 + 1] = DIGIT_TABLE[c1 + 1];
        i += 4;
    }
    if (output2 >= 100) {
        const c = @truncate(u32, (output2 % 100) << 1);
        output2 /= 100;

        result[index + olength - i - 1 + 0] = DIGIT_TABLE[c + 0];
        result[index + olength - i - 1 + 1] = DIGIT_TABLE[c + 1];
        i += 2;
    }
    if (output2 >= 10) {
        const c = @truncate(u32, output2 << 1);
        // We can't use memcpy here: the decimal dot goes between these two digits.
        result[index + olength - i] = DIGIT_TABLE[c + 1];
        result[index] = DIGIT_TABLE[c];
    } else {
        result[index] = @intCast(u8, '0' + output2);
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
    index += 1;

    var exp = v.exponent + @intCast(i32, olength) - 1;
    if (exp < 0) {
        result[index] = '-';
        index += 1;
        exp = -exp;
    }

    const expu = @intCast(usize, exp);

    if (expu >= 100) {
        const c = @rem(expu, 10);
        const offset2 = @intCast(usize, 2 * @divTrunc(expu, 10));

        result[index + 0] = DIGIT_TABLE[offset2 + 0];
        result[index + 1] = DIGIT_TABLE[offset2 + 1];
        result[index + 2] = @intCast(u8, '0' + c);
        index += 3;
    } else if (expu >= 10) {
        const offset2 = @intCast(usize, 2 * expu);

        result[index + 0] = DIGIT_TABLE[offset2 + 0];
        result[index + 1] = DIGIT_TABLE[offset2 + 1];
        index += 2;
    } else {
        result[index] = @intCast(u8, '0' + expu);
        index += 1;
    }

    return index;
}

fn T(expected: []const u8, input: f64) void {
    var buffer: [53]u8 = undefined;
    const converted = ryu64(input, buffer[0..]);
    std.debug.assert(std.mem.eql(u8, expected, converted));
}

test "ryu64 basic" {
    T("0E0", 0.0);
    T("-0E0", -f64(0.0));
    T("1E0", 1.0);
    T("-1E0", -1.0);
    T("NaN", std.math.nan(f64));
    T("Infinity", std.math.inf(f64));
    T("-Infinity", -std.math.inf(f64));
}

test "ryu64 switch to subnormal" {
    T("2.2250738585072014E-308", 2.2250738585072014E-308);
}

test "ryu64 min and max" {
    T("1.7976931348623157E308", @bitCast(f64, u64(0x7fefffffffffffff)));
    T("5E-324", @bitCast(f64, u64(1)));
}

test "ryu64 lots of trailing zeros" {
    T("2.9802322387695312E-8", 2.98023223876953125E-8);
}

test "ryu64 looks like pow5" {
    // These numbers have a mantissa that is a multiple of the largest power of 5 that fits,
    // and an exponent that causes the computation for q to result in 22, which is a corner
    // case for Ryu.
    T("5.764607523034235E39", @bitCast(f64, u64(0x4830F0CF064DD592)));
    T("1.152921504606847E40", @bitCast(f64, u64(0x4840F0CF064DD592)));
    T("2.305843009213694E40", @bitCast(f64, u64(0x4850F0CF064DD592)));
}

test "ryu64 regression" {
    T("-2.109808898695963E16", -2.109808898695963E16);
    // TODO: Out of range?
    //T("4.940656E-318", 4.940656E-318);
    //T("1.18575755E-316", 1.18575755E-316);
    //T("2.989102097996E-312", 2.989102097996E-312);
    T("9.0608011534336E15", 9.0608011534336E15);
    T("4.708356024711512E18", 4.708356024711512E18);
    T("9.409340012568248E18", 9.409340012568248E18);
    T("1.2345678E0", 1.2345678);
}
