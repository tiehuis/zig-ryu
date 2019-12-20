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

const common = @import("common.zig");
const table = @import("ryu128_table.zig");
const helper = @import("ryu128_helper.zig");
const DIGIT_TABLE = common.DIGIT_TABLE;

const Decimal128 = struct {
    sign: bool,
    mantissa: u128,
    exponent: i32,
};

pub fn ryu80(f: c_longdouble, result: []u8) []u8 {
    std.debug.assert(c_longdouble.bit_count == 80);
    // TODO: This bound can be reduced
    std.debug.assert(result.len >= 53);

    const mantissa_bits = std.math.floatMantissaBits(c_longdouble);
    const exponent_bits = std.math.floatExponentBits(c_longdouble);

    const bits = @bitCast(u80, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, true);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

pub fn ryu128(f: f128, result: []u8) []u8 {
    std.debug.assert(result.len >= 53);

    const mantissa_bits = std.math.floatMantissaBits(f128);
    const exponent_bits = std.math.floatExponentBits(f128);

    const bits = @bitCast(u128, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

fn floatToDecimal(bits: u128, mantissa_bits: u7, exponent_bits: u7, explicit_leading_bit: bool) Decimal128 {
    const exponent_bias = (@as(u128, 1) << (exponent_bits - 1)) - 1;
    const sign = ((bits >> (mantissa_bits + exponent_bits)) & 1) != 0;
    const mantissa = bits & ((@as(u128, 1) << mantissa_bits) - 1);
    const exponent = (bits >> mantissa_bits) & ((@as(u128, 1) << exponent_bits) - 1);

    // Filter out special case nan and inf
    if (exponent == 0 and mantissa == 0) {
        return Decimal128{
            .sign = sign,
            .mantissa = 0,
            .exponent = 0,
        };
    }
    if (exponent == ((@as(u128, 1) << exponent_bits) - 1)) {
        return Decimal128{
            .sign = sign,
            .mantissa = if (explicit_leading_bit) mantissa & ((@as(u128, 1) << (mantissa_bits - 1)) - 1) else mantissa,
            .exponent = 0x7fffffff,
        };
    }

    var e2: i32 = undefined;
    var m2: u128 = undefined;

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
            m2 = (@as(u128, 1) << mantissa_bits) | mantissa;
        }
    }

    const even = m2 & 1 == 0;
    const accept_bounds = even;

    // Step 2: Determine the interval of legal decimal representations.
    const mv = 4 * m2;
    // Implicit bool -> int conversion. True is 1, false is 0.
    const mm_shift = mantissa != 0 or exponent <= 1;

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
        const q = helper.log10Pow2(e2) - @intCast(i32, @boolToInt(e2 > 3));
        e10 = q;
        const k = table.f128_pow5_inv_bitcount + helper.pow5Bits(q) - 1;
        const i = -e2 + @intCast(i32, q) + @intCast(i32, k);

        // No full table, always partial compute
        var pow5: [4]u64 = undefined;
        table.computeInvPow5(@intCast(u32, q), pow5[0..]);
        vr = helper.mulShift(4 * m2, pow5[0..], i);
        vp = helper.mulShift(4 * m2 + 2, pow5[0..], i);
        vm = helper.mulShift(4 * m2 - 1 - @boolToInt(mm_shift), pow5[0..], i);

        // floor(log_5(2^128)) = 55, this is very conservative
        if (q <= 55) {
            // Only one of mp, mv, and mm can be a multiple of 5, if any.
            if (mv % 5 == 0) {
                vr_is_trailing_zeros = helper.multipleOfPowerOf5(mv, q - 1);
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
        const k = @intCast(i32, helper.pow5Bits(i)) - table.f128_pow5_bitcount;
        const j = q - k;

        var pow5: [4]u64 = undefined;
        table.computePow5(@intCast(u32, i), pow5[0..]);
        vr = helper.mulShift(4 * m2, pow5[0..], j);
        vp = helper.mulShift(4 * m2 + 2, pow5[0..], j);
        vm = helper.mulShift(4 * m2 - 1 - @boolToInt(mm_shift), pow5[0..], j);

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
            vr_is_trailing_zeros = (mv & ((@as(u128, 1) << @intCast(u7, q - 1)) - 1)) == 0;
        }
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

    var exp = e10 + @intCast(i32, removed);

    return Decimal128{
        .sign = sign,
        .mantissa = output,
        .exponent = exp,
    };
}

fn decimalToBuffer(v: Decimal128, result: []u8) usize {
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
    const olength = common.decimalLength(false, 39, output);

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
    const elength = common.decimalLength(false, 39, @intCast(u128, expu));

    var j: usize = 0;
    while (j < elength) : (j += 1) {
        const c = expu % 10;
        expu /= 10;
        result[index + elength - 1 - j] = @intCast(u8, '0' + c);
    }

    index += elength;
    return index;
}

fn T32(expected: []const u8, input: f32) void {
    var buffer: [53]u8 = undefined;
    const converted = ryu32(input, buffer[0..]);
    std.debug.assert(std.mem.eql(u8, expected, converted));
}

fn T64(expected: []const u8, input: f64) void {
    var buffer: [53]u8 = undefined;
    const converted = ryu64(input, buffer[0..]);
    std.debug.assert(std.mem.eql(u8, expected, converted));
}

fn T80(expected: []const u8, input: c_longdouble) void {
    var buffer: [53]u8 = undefined;
    const converted = ryu80(input, buffer[0..]);
    std.debug.assert(std.mem.eql(u8, expected, converted));
}

// These are only to test the backend. The public definitions of ryu32 and ryu64 use the 32-bit
// and 64-bit backends respectively.
fn ryu32(f: f32, result: []u8) []u8 {
    std.debug.assert(result.len >= 16);
    const mantissa_bits = std.math.floatMantissaBits(f32);
    const exponent_bits = std.math.floatExponentBits(f32);

    const bits = @bitCast(u32, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

fn ryu64(f: f64, result: []u8) []u8 {
    std.debug.assert(result.len >= 25);

    const mantissa_bits = std.math.floatMantissaBits(f64);
    const exponent_bits = std.math.floatExponentBits(f64);

    const bits = @bitCast(u64, f);
    const v = floatToDecimal(bits, mantissa_bits, exponent_bits, false);
    const index = decimalToBuffer(v, result);
    return result[0..index];
}

test "ryu128 generic to char" {
    const d = Decimal128{
        .sign = false,
        .exponent = -2,
        .mantissa = 12345,
    };

    var result: [53]u8 = undefined;
    const index = decimalToBuffer(d, result[0..]);

    std.debug.assert(std.mem.eql(u8, "1.2345E2", result[0..index]));
}

test "ryu128 generic to char long" {
    const d = Decimal128{
        .sign = false,
        .exponent = -20,
        .mantissa = 100000000000000000000000000000000000000,
    };

    var result: [53]u8 = undefined;
    const index = decimalToBuffer(d, result[0..]);

    std.debug.assert(std.mem.eql(u8, "1.00000000000000000000000000000000000000E18", result[0..index]));
}

test "ryu128 generic (f32)" {
    T32("0E0", 0.0);
    T32("-0E0", -@as(f32, 0.0));
    T32("1E0", 1.0);
    T32("-1E0", -1.0);
    T32("NaN", std.math.nan(f32));
    T32("Infinity", std.math.inf(f32));
    T32("-Infinity", -std.math.inf(f32));
    T32("1.1754944E-38", 1.1754944E-38);
    T32("3.4028235E38", @bitCast(f32, @as(u32, 0x7f7fffff)));
    T32("1E-45", @bitCast(f32, @as(u32, 1)));
    T32("3.355445E7", 3.355445E7);
    T32("9E9", 8.999999E9);
    T32("3.436672E10", 3.4366717E10);
    T32("3.0540412E5", 3.0540412E5);
    T32("8.0990312E3", 8.0990312E3);
    // Pattern for the first test: 00111001100000000000000000000000
    T32("2.4414062E-4", 2.4414062E-4);
    T32("2.4414062E-3", 2.4414062E-3);
    T32("4.3945312E-3", 4.3945312E-3);
    T32("6.3476562E-3", 6.3476562E-3);
    T32("4.7223665E21", 4.7223665E21);
    T32("8.388608E6", 8388608.0);
    T32("1.6777216E7", 1.6777216E7);
    T32("3.3554436E7", 3.3554436E7);
    T32("6.7131496E7", 6.7131496E7);
    T32("1.9310392E-38", 1.9310392E-38);
    T32("-2.47E-43", -2.47E-43);
    T32("1.993244E-38", 1.993244E-38);
    T32("4.1039004E3", 4103.9003);
    T32("5.3399997E9", 5.3399997E9);
    T32("6.0898E-39", 6.0898E-39);
    T32("1.0310042E-3", 0.0010310042);
    T32("2.882326E17", 2.8823261E17);
    T32("7.038531E-26", 7.0385309E-26);
    T32("9.223404E17", 9.2234038E17);
    T32("6.710887E7", 6.7108872E7);
    T32("1E-44", 1.0E-44);
    T32("2.816025E14", 2.816025E14);
    T32("9.223372E18", 9.223372E18);
    T32("1.5846086E29", 1.5846085E29);
    T32("1.1811161E19", 1.1811161E19);
    T32("5.368709E18", 5.368709E18);
    T32("4.6143166E18", 4.6143165E18);
    T32("7.812537E-3", 0.007812537);
    T32("1E-45", 1.4E-45);
    T32("1.18697725E20", 1.18697724E20);
    T32("1.00014165E-36", 1.00014165E-36);
    T32("2E2", 200.0);
    T32("3.3554432E7", 3.3554432E7);
    T32("1.2E0", 1.2);
    T32("1.23E0", 1.23);
    T32("1.234E0", 1.234);
    T32("1.2345E0", 1.2345);
    T32("1.23456E0", 1.23456);
    T32("1.234567E0", 1.234567);
    T32("1.2345678E0", 1.2345678);
    T32("1.23456735E-36", 1.23456735E-36);
}

test "ryu128 generic (f64)" {
    T64("0E0", 0.0);
    T64("-0E0", -@as(f64, 0.0));
    T64("1E0", 1.0);
    T64("-1E0", -1.0);
    T64("NaN", std.math.nan(f64));
    T64("Infinity", std.math.inf(f64));
    T64("-Infinity", -std.math.inf(f64));
    T64("2.2250738585072014E-308", 2.2250738585072014E-308);
    T64("1.7976931348623157E308", @bitCast(f64, @as(u64, 0x7fefffffffffffff)));
    T64("5E-324", @bitCast(f64, @as(u64, 1)));
    T64("2.9802322387695312E-8", 2.98023223876953125E-8);
    T64("-2.109808898695963E16", -2.109808898695963E16);
    // TODO: Literal out of range
    //T64("4.940656E-318", 4.940656E-318);
    //T64("1.18575755E-316", 1.18575755E-316);
    //T64("2.989102097996E-312", 2.989102097996E-312);
    T64("9.0608011534336E15", 9.0608011534336E15);
    T64("4.708356024711512E18", 4.708356024711512E18);
    T64("9.409340012568248E18", 9.409340012568248E18);
    T64("1.2345678E0", 1.2345678);
    T64("5.764607523034235E39", @bitCast(f64, @as(u64, 0x4830F0CF064DD592)));
    T64("1.152921504606847E40", @bitCast(f64, @as(u64, 0x4840F0CF064DD592)));
    T64("2.305843009213694E40", @bitCast(f64, @as(u64, 0x4850F0CF064DD592)));

    T64("1E0", 1); // already tested in Basic
    T64("1.2E0", 1.2);
    T64("1.23E0", 1.23);
    T64("1.234E0", 1.234);
    T64("1.2345E0", 1.2345);
    T64("1.23456E0", 1.23456);
    T64("1.234567E0", 1.234567);
    T64("1.2345678E0", 1.2345678); // already tested in Regression
    T64("1.23456789E0", 1.23456789);
    T64("1.234567895E0", 1.234567895); // 1.234567890 would be trimmed
    T64("1.2345678901E0", 1.2345678901);
    T64("1.23456789012E0", 1.23456789012);
    T64("1.234567890123E0", 1.234567890123);
    T64("1.2345678901234E0", 1.2345678901234);
    T64("1.23456789012345E0", 1.23456789012345);
    T64("1.234567890123456E0", 1.234567890123456);
    T64("1.2345678901234567E0", 1.2345678901234567);

    // Test 32-bit chunking
    T64("4.294967294E0", 4.294967294); // 2^32 - 2
    T64("4.294967295E0", 4.294967295); // 2^32 - 1
    T64("4.294967296E0", 4.294967296); // 2^32
    T64("4.294967297E0", 4.294967297); // 2^32 + 1
    T64("4.294967298E0", 4.294967298); // 2^32 + 2
}

// TODO: unreachable: /home/me/src/zig/src/ir.cpp:eval_const_expr_implicit_cast:9320
// See https://github.com/ziglang/zig/issues/1188.
test "ryu128 generic (f80/c_longdouble)" {
    if (true) { // c_longdouble.bit_count != 80) {
        return error.SkipZigTest;
    }

    T80("0E0", 0.0);
    T80("-0E0", -c_longdouble(0.0));
    T80("1E0", 1.0);
    T80("-1E0", -1.0);
    T80("NaN", std.math.nan(c_longdouble));
    T80("Infinity", std.math.inf(c_longdouble));
    T80("-Infinity", -std.math.inf(c_longdouble));

    T80("2.2250738585072014E-308", 2.2250738585072014E-308);
    T80("2.98023223876953125E-8", 2.98023223876953125E-8);
    T80("-2.109808898695963E16", -2.109808898695963E16);
    // TODO: Literal out of range
    //T80("4.940656E-318", 4.940656E-318);
    //T80("1.18575755E-316", 1.18575755E-316);
    //T80("2.989102097996E-312", 2.989102097996E-312);
    T80("9.0608011534336E15", 9.0608011534336E15);
    T80("4.708356024711512E18", 4.708356024711512E18);
    T80("9.409340012568248E18", 9.409340012568248E18);
    T80("1.2345678E0", 1.2345678);
}
