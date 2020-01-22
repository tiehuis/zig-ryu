//! Low-level math intrinsics used during float printing. These may tuned with certain
//! constraints and mind and should not be considered general purpose.

const std = @import("std");

/// Return the length of a number in base-10.
///
/// Input must be less than 10 digits:
///  f2s: 9 digits are sufficient for round-tripping.
///  d2fixed: We print 9-digit blocks.
pub inline fn decimalLength9(x: u32) u32 {
    std.debug.assert(x < 1000000000);
    if (x >= 100000000) return 9;
    if (x >= 10000000) return 8;
    if (x >= 1000000) return 7;
    if (x >= 100000) return 6;
    if (x >= 10000) return 5;
    if (x >= 1000) return 4;
    if (x >= 100) return 3;
    if (x >= 10) return 2;
    return 1;
}

/// Return the length of a number in base-10.
///
/// Input must be less than 17 digits.
pub inline fn decimalLength17(x: u64) u32 {
    // This is slightly faster than a loop.
    // The average output length is 16.38 digits, so we check high-to-low.
    // Function precondition: v is not an 18, 19, or 20-digit number.
    // (17 digits are sufficient for round-tripping.)
    std.debug.assert(x < 100000000000000000);
    if (x >= 10000000000000000) return 17;
    if (x >= 1000000000000000) return 16;
    if (x >= 100000000000000) return 15;
    if (x >= 10000000000000) return 14;
    if (x >= 1000000000000) return 13;
    if (x >= 100000000000) return 12;
    if (x >= 10000000000) return 11;
    if (x >= 1000000000) return 10;
    if (x >= 100000000) return 9;
    if (x >= 10000000) return 8;
    if (x >= 1000000) return 7;
    if (x >= 100000) return 6;
    if (x >= 10000) return 5;
    if (x >= 1000) return 4;
    if (x >= 100) return 3;
    if (x >= 10) return 2;
    return 1;
}

/// Returns floor(log_10(2^x)) where 0 <= x <= 1650.
pub inline fn log10Pow2(x: u32) u32 {
    std.debug.assert(x >= 0);
    std.debug.assert(x <= 1650);
    return (x *% 78913) >> 18;
}

/// Returns floor(log_10(5^x)) where 0 <= x <= 2620
pub inline fn log10Pow5(x: u32) u32 {
    std.debug.assert(x >= 0);
    std.debug.assert(x <= 2620);
    return (x *% 732923) >> 20;
}

/// Returns log_2(5^x) where 0 <= x <= 3528.
pub inline fn log2pow5(x: u32) u32 {
    std.debug.assert(x >= 0);
    std.debug.assert(x <= 3528);
    return (x *% 1217359) >> 19;
}

/// Returns ceil(log_2(5^e)) where 0 <= x <= 3528
pub inline fn pow5Bits(x: u32) u32 {
    std.debug.assert(x >= 0);
    std.debug.assert(x <= 3528);
    return ((x *% 1217359) >> 19) + 1;
}

/// Returns ceil(log_2(5^x)) where 0 <= x <= 3528.
pub inline fn ceil_log2pow5(x: u32) u32 {
    return log2pow5(x) + 1;
}

/// Returns true if 2^p | x for some integer p.
pub inline fn multipleOfPowerOf2(x: u64, p: u32) bool {
    std.debug.assert(x != 0);
    return x & (std.math.shl(u64, 1, p) -% 1) == 0;
}

/// Returns the number of factors of 5 in x.
pub inline fn pow5Factor(x: u64) u32 {
    var y = x;
    var c: u32 = 0;
    while (true) : (c += 1) {
        std.debug.assert(y != 0);
        const q = y / 5;
        const r = y - 5 * q;
        if (r != 0) break;
        y = q;
    }

    return c;
}

/// Returns true if 5^p | x for some integer p.
pub inline fn multipleOfPowerOf5(x: u64, p: u32) bool {
    return pow5Factor(x) >= p;
}

/// Performs a 128x128 bit multiplication. The high bits of the 256-bit product are stored
/// in the input productHi. The low bits are returned directly from the function.
pub inline fn umul256(a: u128, bHi: u64, bLo: u64, productHi: *u128) u128 {
    const aLo = @truncate(u64, a);
    const aHi = @truncate(u64, a >> 64);

    const b00 = @as(u128, aLo) *% bLo;
    const b01 = @as(u128, aLo) *% bHi;
    const b10 = @as(u128, aHi) *% bLo;
    const b11 = @as(u128, aHi) *% bHi;

    const b00Lo = @truncate(u64, b00);
    const b00Hi = @truncate(u64, b00 >> 64);

    const mid1 = b10 +% b00Hi;
    const mid1Lo = @truncate(u64, mid1);
    const mid1Hi = @truncate(u64, mid1 >> 64);

    const mid2 = b01 +% mid1Lo;
    const mid2Lo = @truncate(u64, mid2);
    const mid2Hi = @truncate(u64, mid2 >> 64);

    const pHi = b11 +% mid1Hi +% mid2Hi;
    const pLo = (@as(u128, mid2Lo) << 64) | b00Lo;

    productHi.* = pHi;
    return pLo;
}

/// Returns the high 128-bits from a 128x128 bit multiplication.
pub inline fn umul256_hi(a: u128, bHi: u64, bLo: u64) u128 {
    var hi: u128 = undefined;
    _ = umul256(a, bHi, bLo, &hi);
    return hi;
}

/// Returns x % 1000000000.
pub inline fn uint128_mod1e9(x: u128) u32 {
    const multiplied = @truncate(u64, umul256_hi(x, 0x89705F4136B4A597, 0x31680A88F8953031));
    const shifted = @truncate(u32, multiplied >> 29);
    return @truncate(u32, x) -% 1000000000 *% shifted;
}

pub inline fn mulShift_mod1e9(m: u64, mul: [3]u64, j: u32) u32 {
    const m1 = @as(u128, m);
    const b0 = m1 *% mul[0];
    const b1 = m1 *% mul[1];
    const b2 = m1 *% mul[2];

    std.debug.assert(j >= 128);
    std.debug.assert(j <= 180);

    const mid = b1 +% @intCast(u64, b0 >> 64);
    const s1 = b2 +% @intCast(u64, mid >> 64);
    return uint128_mod1e9(s1 >> @intCast(u7, j - 128));
}

pub inline fn mulShift64(m: u64, mul: [2]u64, j: u32) u64 {
    const m1 = @as(u128, m);
    const b0 = m1 *% mul[0];
    const b2 = m1 *% mul[1];
    return @truncate(u64, ((b0 >> 64) +% b2) >> @intCast(u7, j - 64));
}

const POW10_ADDITIONAL_BITS = 120;

pub inline fn indexForExponent(e: u32) u32 {
    return (e + 15) / 16;
}

pub inline fn pow10BitsForIndex(idx: u32) u32 {
    return 16 * idx + POW10_ADDITIONAL_BITS;
}

pub inline fn lengthForIndex(idx: u32) u32 {
    // +1 for ceil, +16 for mantissa, +8 to round up when dividing by 9
    return (log10Pow2(16 * idx) + 1 + 16 + 8) / 9;
}
