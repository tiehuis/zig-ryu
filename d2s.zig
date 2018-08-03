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
//
// -DRYU_OPTIMIZE_SIZE Use smaller lookup tables. Instead of storing every
//     required power of 5, only store every 26th entry, and compute
//     intermediate values with a multiplication. This reduces the lookup table
//     size by about 10x (only one case, and only double) at the cost of some
//     performance. Currently requires MSVC intrinsics.

const std = @import("std");

const ryu_debug = false;
const ryu_optimize_size = false;

use @import("common.zig");
use @import("digit_table.zig");
use @import("d2s_full_table.zig");

const DOUBLE_POW5_INV_BITCOUNT = 122;
const DOUBLE_POW5_BITCOUNT = 121;

// Following are for compact table lookup.

const DOUBLE_POW5_TABLE = []const u64{
    1, 5, 25, 125, 625, 3125, 15625, 78125, 390625,
    1953125, 9765625, 48828125, 244140625, 1220703125, 6103515625, 30517578125, 152587890625, 762939453125,
    3814697265625, 19073486328125, 95367431640625, 476837158203125, 2384185791015625, 11920928955078125, 59604644775390625, 298023223876953125, //, 1490116119384765625
};

const POW5_TABLE_SIZE = DOUBLE_POW5_TABLE.len;

const DOUBLE_POW5_SPLIT2 = [][]const u64{
    []const u64{ 0, 72057594037927936 },
    []const u64{ 10376293541461622784, 93132257461547851 },
    []const u64{ 15052517733678820785, 120370621524202240 },
    []const u64{ 6258995034005762182, 77787690973264271 },
    []const u64{ 14893927168346708332, 100538234169297439 },
    []const u64{ 4272820386026678563, 129942622070561240 },
    []const u64{ 7330497575943398595, 83973451344588609 },
    []const u64{ 18377130505971182927, 108533142064701048 },
    []const u64{ 10038208235822497557, 140275798336537794 },
    []const u64{ 7017903361312433648, 90651109995611182 },
    []const u64{ 6366496589810271835, 117163813585596168 },
    []const u64{ 9264989777501460624, 75715339914673581 },
    []const u64{ 17074144231291089770, 97859783203563123 },
};

// Unfortunately, the results are sometimes off by one. We use an additional
// lookup table to store those cases and adjust the result.
const POW5_OFFSETS = []const u32{
    0x00000000, 0x00000000, 0x00000000, 0x033c55be, 0x03db77d8, 0x0265ffb2,
    0x00000800, 0x01a8ff56, 0x00000000, 0x0037a200, 0x00004000, 0x03fffffc,
    0x00003ffe,
};

const DOUBLE_POW5_INV_SPLIT2 = [][]const u64{
    []const u64{ 1, 288230376151711744 },
    []const u64{ 7661987648932456967, 223007451985306231 },
    []const u64{ 12652048002903177473, 172543658669764094 },
    []const u64{ 5522544058086115566, 266998379490113760 },
    []const u64{ 3181575136763469022, 206579990246952687 },
    []const u64{ 4551508647133041040, 159833525776178802 },
    []const u64{ 1116074521063664381, 247330401473104534 },
    []const u64{ 17400360011128145022, 191362629322552438 },
    []const u64{ 9297997190148906106, 148059663038321393 },
    []const u64{ 11720143854957885429, 229111231347799689 },
    []const u64{ 15401709288678291155, 177266229209635622 },
    []const u64{ 3003071137298187333, 274306203439684434 },
    []const u64{ 17516772882021341108, 212234145163966538 },
};

const POW5_INV_OFFSETS = []const u32{
    0x51505404, 0x55054514, 0x45555545, 0x05511411, 0x00505010, 0x00000004,
    0x00000000, 0x00000000, 0x55555040, 0x00505051, 0x00050040, 0x55554000,
    0x51659559, 0x00001000, 0x15000010, 0x55455555, 0x41404051, 0x00001010,
    0x00000014, 0x00000000,
};

// Computes 5^i in the form required by Ryu, and stores it in the given pointer.
inline fn double_computePow5(i: u32, result: []u64) void {
    const base = i / POW5_TABLE_SIZE;
    const base2 = base * POW5_TABLE_SIZE;
    const offset = i - base2;
    const mul = DOUBLE_POW5_SPLIT2[base];
    if (offset == 0) {
        result[0] = mul[0];
        result[1] = mul[1];
        return;
    }
    const m = DOUBLE_POW5_TABLE[offset];
    const b0 = u128(m) * mul[0];
    const b2 = u128(m) * mul[1];
    const delta = pow5bits(@intCast(i32, i)) - pow5bits(@intCast(i32, base2));
    const shiftedSum = (b0 >> @intCast(u7, delta)) + (b2 << @intCast(u7, 64 - delta)) + ((POW5_OFFSETS[base] >> @intCast(u5, offset)) & 1);
    result[0] = @truncate(u64, shiftedSum);
    result[1] = @intCast(u64, shiftedSum >> 64);
}

// Computes 5^-i in the form required by Ryu, and stores it in the given pointer.
inline fn double_computeInvPow5(i: u32, result: []u64) void {
    const base = (i + POW5_TABLE_SIZE - 1) / POW5_TABLE_SIZE;
    const base2 = base * POW5_TABLE_SIZE;
    const offset = base2 - i;
    const mul = DOUBLE_POW5_INV_SPLIT2[base]; // 1/5^base2
    if (offset == 0) {
        result[0] = mul[0];
        result[1] = mul[1];
        return;
    }
    const m = DOUBLE_POW5_TABLE[offset]; // 5^offset
    const b0 = u128(m) * (mul[0] - 1);
    const b2 = u128(m) * mul[1]; // 1/5^base2 * 5^offset = 1/5^(base2-offset) = 1/5^i
    const delta = pow5bits(@intCast(i32, base2)) - pow5bits(@intCast(i32, i));
    const shiftedSum = ((b0 >> @intCast(u7, delta)) + (b2 << @intCast(u7, 64 - delta))) + 1 + ((POW5_INV_OFFSETS[i / 16] >> @intCast(u5, ((i % 16) << 1))) & 3);
    result[0] = @truncate(u64, shiftedSum);
    result[1] = @intCast(u64, shiftedSum >> 64);
}

// Best case: use 128-bit type.
inline fn mulShift(m: u64, mul: []const u64, j: i32) u64 {
    const b0 = u128(m) * mul[0];
    const b2 = u128(m) * mul[1];
    return @truncate(u64, (((b0 >> 64) + b2) >> @intCast(u7, (j - 64))));
}

inline fn mulShiftAll(m: u64, mul: []const u64, j: i32, vp: *u64, vm: *u64, mmShift: u32) u64 {
    vp.* = mulShift(4 * m + 2, mul, j);
    vm.* = mulShift(4 * m - 1 - mmShift, mul, j);
    return mulShift(4 * m, mul, j);
}

inline fn decimalLength(v: u64) u32 {
    // This is slightly faster than a loop.
    // The average output length is 16.38 digits, so we check high-to-low.
    // Function precondition: v is not an 18, 19, or 20-digit number.
    // (17 digits are sufficient for round-tripping.)
    std.debug.assert(v < 100000000000000000);

    comptime var n = 10000000000000000;
    comptime var i = 17;

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

fn d2s_buffered_n(f: f64, result: []u8) usize {
    // Step 1: Decode the floating-point number, and unify normalized and subnormal cases.
    const mantissaBits = std.math.floatMantissaBits(f64);
    const exponentBits = std.math.floatExponentBits(f64);
    const offset = (1 << (exponentBits - 1)) - 1;

    // This only works on little-endian architectures.
    const bits = @bitCast(u64, f);

    // Decode bits into sign, mantissa, and exponent.
    const sign = ((bits >> (mantissaBits + exponentBits)) & 1) != 0;
    const ieeeMantissa = bits & ((1 << mantissaBits) - 1);
    const ieeeExponent = (bits >> mantissaBits) & ((1 << exponentBits) - 1);

    if (ryu_debug) {
        std.debug.warn("IN={b}\n", bits);
    }

    var e2: i32 = undefined;
    var m2: u64 = undefined;

    // Case distinction; exit early for the easy cases.
    if (ieeeExponent == ((1 << exponentBits) - 1) or (ieeeExponent == 0 and ieeeMantissa == 0)) {
        return copy_special_str(result, sign, ieeeExponent != 0, ieeeMantissa != 0);
    } else if (ieeeExponent == 0) {
        // We subtract 2 so that the bounds computation has 2 additional bits.
        e2 = 1 - offset - mantissaBits - 2;
        m2 = ieeeMantissa;
    } else {
        e2 = @intCast(i32, ieeeExponent) - offset - mantissaBits - 2;
        m2 = (1 << mantissaBits) | ieeeMantissa;
    }
    const even = (m2 & 1) == 0;
    const acceptBounds = even;

    if (ryu_debug) {
        std.debug.warn("S={} E={} M={}\n", if (sign) "-" else "+", e2 + 2, m2);
    }

    // Step 2: Determine the interval of legal decimal representations.
    const mv = 4 * m2;
    // Implicit bool -> int conversion. True is 1, false is 0.
    const mmShift = (m2 != (1 << mantissaBits)) or (ieeeExponent <= 1);
    // We would compute mp and mm like this:
    //  uint64_t mp = 4 * m2 + 2;
    //  uint64_t mm = mv - 1 - mmShift;

    // Step 3: Convert to a decimal power base using 128-bit arithmetic.
    var vr: u64 = undefined;
    var vp: u64 = undefined;
    var vm: u64 = undefined;
    var e10: i32 = undefined;
    var vmIsTrailingZeros = false;
    var vrIsTrailingZeros = false;

    if (e2 >= 0) {
        // I tried special-casing q == 0, but there was no effect on performance.
        // This expression is slightly faster than max(0, log10Pow2(e2) - 1).
        const q = log10Pow2(e2) - @intCast(i32, @boolToInt(e2 > 3));
        e10 = q;
        const k = DOUBLE_POW5_INV_BITCOUNT + pow5bits(q) - 1;
        const i = -e2 + @intCast(i32, q) + @intCast(i32, k);

        if (ryu_optimize_size) {
            var pow5: [2]u64 = undefined;
            double_computeInvPow5(@intCast(u32, q), pow5[0..]);
            vr = mulShiftAll(m2, pow5, i, &vp, &vm, @boolToInt(mmShift));
        } else {
            vr = mulShiftAll(m2, DOUBLE_POW5_INV_SPLIT[@intCast(usize, q)], i, &vp, &vm, @boolToInt(mmShift));
        }

        if (ryu_debug) {
            std.debug.warn("%{} * 2^{} / 10^{}\n", mv, e2, q);
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        }
        if (q <= 21) {
            // Only one of mp, mv, and mm can be a multiple of 5, if any.
            if (mv % 5 == 0) {
                vrIsTrailingZeros = multipleOfPowerOf5(mv, q);
            } else {
                if (acceptBounds) {
                    // Same as min(e2 + (~mm & 1), pow5Factor(mm)) >= q
                    // <=> e2 + (~mm & 1) >= q && pow5Factor(mm) >= q
                    // <=> true && pow5Factor(mm) >= q, since e2 >= q.
                    vmIsTrailingZeros = multipleOfPowerOf5(mv - 1 - @boolToInt(mmShift), q);
                } else {
                    // Same as min(e2 + 1, pow5Factor(mp)) >= q.
                    vp -= @boolToInt(multipleOfPowerOf5(mv + 2, q));
                }
            }
        }
    } else {
        // This expression is slightly faster than max(0, log10Pow5(-e2) - 1).
        const q = log10Pow5(-e2) - @intCast(i32, @boolToInt(-e2 > 1));
        e10 = q + e2;
        const i = -e2 - q;
        const k = @intCast(i32, pow5bits(i)) - DOUBLE_POW5_BITCOUNT;
        const j = q - k;

        if (ryu_optimize_size) {
            var pow5: [2]u64 = undefined;
            double_computePow5(@intCast(u32, i), pow5[0..]);
            vr = mulShiftAll(m2, pow5, j, &vp, &vm, @boolToInt(mmShift));
        } else {
            vr = mulShiftAll(m2, DOUBLE_POW5_SPLIT[@intCast(usize, i)], j, &vp, &vm, @boolToInt(mmShift));
        }

        if (ryu_debug) {
            std.debug.warn("{} * 5^{} / 10^{}\n", mv, -e2, q);
            std.debug.warn("{} {} {} {}\n", q, i, k, j);
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        }

        if (q <= 1) {
            vrIsTrailingZeros = (~@truncate(u32, mv) & 1) >= @intCast(u32, q);
            if (acceptBounds) {
                vmIsTrailingZeros = (~@truncate(u32, mv - 1 - @boolToInt(mmShift)) & 1) >= @intCast(u32, q);
            } else {
                vp -= 1;
            }
        } else if (q < 63) { // TODO(ulfjack): Use a tighter bound here.
            // We need to compute min(ntz(mv), pow5Factor(mv) - e2) >= q-1
            // <=> ntz(mv) >= q-1  &&  pow5Factor(mv) - e2 >= q-1
            // <=> ntz(mv) >= q-1
            // <=> (mv & ((1 << (q-1)) - 1)) == 0
            // We also need to make sure that the left shift does not overflow.
            vrIsTrailingZeros = (mv & ((u64(1) << @intCast(u6, q - 1)) - 1)) == 0;

            if (ryu_debug) {
                std.debug.warn("vr is trailing zeros={}\n", vrIsTrailingZeros);
            }
        }
    }

    if (ryu_debug) {
        std.debug.warn("e10={}\n", e10);
        std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        std.debug.warn("vm is trailing zeros={}\n", vmIsTrailingZeros);
        std.debug.warn("vr is trailing zeros={}\n", vrIsTrailingZeros);
    }

    // Step 4: Find the shortest decimal representation in the interval of legal representations.
    var removed: u32 = 0;
    var lastRemovedDigit: u8 = 0;
    var output: u64 = undefined;
    // On average, we remove ~2 digits.
    if (vmIsTrailingZeros or vrIsTrailingZeros) {
        // General case, which happens rarely (<1%).
        while (vp / 10 > vm / 10) {
            vmIsTrailingZeros = vmIsTrailingZeros and vm % 10 == 0;
            vrIsTrailingZeros = vrIsTrailingZeros and lastRemovedDigit == 0;
            lastRemovedDigit = @intCast(u8, vr % 10);
            vr /= 10;
            vp /= 10;
            vm /= 10;
            removed += 1;
        }

        if (ryu_debug) {
            std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
            std.debug.warn("d-10={}\n", vmIsTrailingZeros);
        }

        if (vmIsTrailingZeros) {
            while (vm % 10 == 0) {
                vrIsTrailingZeros = vrIsTrailingZeros and lastRemovedDigit == 0;
                lastRemovedDigit = @intCast(u8, vr % 10);
                vr /= 10;
                vp /= 10;
                vm /= 10;
                removed += 1;
            }
        }

        if (ryu_debug) {
            std.debug.warn("{} %d\n", vr, lastRemovedDigit);
            std.debug.warn("vr is trailing zeros={}\n", vrIsTrailingZeros);
        }

        if (vrIsTrailingZeros and (lastRemovedDigit == 5) and (vr % 2 == 0)) {
            // Round down not up if the number ends in X50000.
            lastRemovedDigit = 4;
        }
        // We need to take vr+1 if vr is outside bounds or we need to round up.
        output = vr +
            @boolToInt((vr == vm and (!acceptBounds or !vmIsTrailingZeros)) or (lastRemovedDigit >= 5));
    } else {
        // Specialized for the common case (>99%).
        while (vp / 10 > vm / 10) {
            lastRemovedDigit = @intCast(u8, vr % 10);
            vr /= 10;
            vp /= 10;
            vm /= 10;
            removed += 1;
        }

        if (ryu_debug) {
            std.debug.warn("{} {}\n", vr, lastRemovedDigit);
            std.debug.warn("vr is trailing zeros={}\n", vrIsTrailingZeros);
        }

        // We need to take vr+1 if vr is outside bounds or we need to round up.
        output = vr + @boolToInt((vr == vm) or (lastRemovedDigit >= 5));
    }
    // The average output length is 16.38 digits.
    const olength = decimalLength(output);
    var exp = e10 + @intCast(i32, removed) - 1;

    if (ryu_debug) {
        std.debug.warn("V+={}\nV ={}\nV-={}\n", vp, vr, vm);
        std.debug.warn("O={}\n", output);
        std.debug.warn("EXP={}\n", exp);
    }

    // Step 5: Print the decimal representation.
    var index: usize = 0;
    if (sign) {
        result[index] = '-';
        index += 1;
    }

    if (ryu_debug) {
        std.debug.warn("DIGITS={}\n", output);
        std.debug.warn("OLEN={}\n", olength);
        std.debug.warn("EXP={}\n", exp + olength);
    }

    // Print the decimal digits.
    // The following code is equivalent to:
    // for (uint32_t i = 0; i < olength - 1; ++i) {
    //   const uint32_t c = output % 10; output /= 10;
    //   result[index + olength - i] = (char) ('0' + c);
    // }
    // result[index] = '0' + output % 10;

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

        std.mem.copy(u8, result[index + olength - i - 1 ..], DIGIT_TABLE[c0 .. c0 + 2]);
        std.mem.copy(u8, result[index + olength - i - 3 ..], DIGIT_TABLE[c1 .. c1 + 2]);
        std.mem.copy(u8, result[index + olength - i - 5 ..], DIGIT_TABLE[d0 .. d0 + 2]);
        std.mem.copy(u8, result[index + olength - i - 7 ..], DIGIT_TABLE[d1 .. d1 + 2]);
        i += 8;
    }

    var output2 = @truncate(u32, output);
    while (output2 >= 10000) {
        const c = @truncate(u32, output2 % 10000);
        output2 /= 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;

        std.mem.copy(u8, result[index + olength - i - 1 ..], DIGIT_TABLE[c0 .. c0 + 2]);
        std.mem.copy(u8, result[index + olength - i - 3 ..], DIGIT_TABLE[c1 .. c1 + 2]);
        i += 4;
    }
    if (output2 >= 100) {
        const c = @truncate(u32, (output2 % 100) << 1);
        output2 /= 100;
        std.mem.copy(u8, result[index + olength - i - 1 ..], DIGIT_TABLE[c .. c + 2]);
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

    exp += @intCast(i32, olength);
    if (exp < 0) {
        result[index] = '-';
        index += 1;
        exp = -exp;
    }

    if (exp >= 100) {
        const c = @rem(exp, 10);
        const offset2 = @intCast(usize, 2 * @divTrunc(exp, 10));
        std.mem.copy(u8, result[index..], DIGIT_TABLE[offset2 .. offset2 + 2]);
        result[index + 2] = @intCast(u8, '0' + c);
        index += 3;
    } else if (exp >= 10) {
        const offset2 = @intCast(usize, 2 * exp);
        std.mem.copy(u8, result[index..], DIGIT_TABLE[offset2 .. offset2 + 2]);
        index += 2;
    } else {
        result[index] = @intCast(u8, '0' + exp);
        index += 1;
    }

    return index;
}

fn d2s_buffered(f: f64, result: []u8) []u8 {
    const index = d2s_buffered_n(f, result);
    return result[0..index];
}

fn d2s(allocator: *std.mem.Allocator, f: f64) ![]u8 {
    var result = try allocator.alloc(u8, 25);
    return d2s_buffered(f, result);
}

const assert = std.debug.assert;
const al = std.debug.global_allocator;
const eql = std.mem.eql;

test "d2s basic" {
    assert(eql(u8, "0E0", try d2s(al, 0.0)));
    assert(eql(u8, "-0E0", try d2s(al, -f64(0.0))));
    assert(eql(u8, "1E0", try d2s(al, 1.0)));
    assert(eql(u8, "-1E0", try d2s(al, -1.0)));
    assert(eql(u8, "nan", try d2s(al, std.math.nan(f64))));
    assert(eql(u8, "inf", try d2s(al, std.math.inf(f64))));
    assert(eql(u8, "-inf", try d2s(al, -std.math.inf(f64))));
}

test "d2s switch to subnormal" {
    assert(eql(u8, "2.2250738585072014E-308", try d2s(al, 2.2250738585072014E-308)));
}

test "d2s min and max" {
    assert(eql(u8, "1.7976931348623157E308", try d2s(al, @bitCast(f64, u64(0x7fefffffffffffff)))));
    assert(eql(u8, "5E-324", try d2s(al, @bitCast(f64, u64(1)))));
}

test "d2s lots of trailing zeros" {
    assert(eql(u8, "2.9802322387695312E-8", try d2s(al, 2.98023223876953125E-8)));
}

test "d2s regression" {
    assert(eql(u8, "-2.109808898695963E16", try d2s(al, -2.109808898695963E16)));
    // TODO: Out of range?
    //assert(eql(u8, "4.940656E-318", try d2s(al, 4.940656E-318)));
    //assert(eql(u8, "1.18575755E-316", try d2s(al, 1.18575755E-316)));
    //assert(eql(u8, "2.989102097996E-312", try d2s(al, 2.989102097996E-312)));
    assert(eql(u8, "9.0608011534336E15", try d2s(al, 9.0608011534336E15)));
    assert(eql(u8, "4.708356024711512E18", try d2s(al, 4.708356024711512E18)));
    assert(eql(u8, "9.409340012568248E18", try d2s(al, 9.409340012568248E18)));
    assert(eql(u8, "1.2345678E0", try d2s(al, 1.2345678)));
}
