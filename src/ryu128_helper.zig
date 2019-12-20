const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

// Returns e == 0 ? 1 : ceil(log_2(5^e)).
pub fn pow5Bits(e: i32) u32 {
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 1 << 15);
    return @intCast(u32, ((@intCast(u64, e) * 163391164108059) >> 46) + 1);
}

// Returns floor(log_10(2^e)).
pub fn log10Pow2(e: i32) i32 {
    // The first value this approximation fails for is 2^1651 which is just greater than 10^297.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 1 << 15);
    return @intCast(i32, (@intCast(u64, e) * 169464822037455) >> 49);
}

// Returns floor(log_10(5^e)).
pub fn log10Pow5(e: i32) i32 {
    // The first value this approximation fails for is 5^2621 which is just greater than 10^1832.
    std.debug.assert(e >= 0);
    std.debug.assert(e <= 1 << 15);
    return @intCast(i32, (@intCast(u64, e) * 196742565691928) >> 48);
}

pub const multipleOfPowerOf5 = @import("common.zig").multipleOfPowerOf5;

pub fn mul_128_256_shift(a: []const u64, b: []const u64, shift: u32, corr: u32, result: []u64) void {
    std.debug.assert(shift > 0);
    std.debug.assert(shift < 256);

    const b00 = @as(u128, a[0]) * b[0]; // 0
    const b01 = @as(u128, a[0]) * b[1]; // 64
    const b02 = @as(u128, a[0]) * b[2]; // 128
    const b03 = @as(u128, a[0]) * b[3]; // 196
    const b10 = @as(u128, a[1]) * b[0]; // 64
    const b11 = @as(u128, a[1]) * b[1]; // 128
    const b12 = @as(u128, a[1]) * b[2]; // 196
    const b13 = @as(u128, a[1]) * b[3]; // 256

    const s0 = b00; // 0   x
    const s1 = b01 +% b10; // 64  x
    const c1 = @boolToInt(s1 < b01); // 196 x
    const s2 = b02 +% b11; // 128 x
    const c2 = @boolToInt(s2 < b02); // 256 x
    const s3 = b03 +% b12; // 196 x
    const c3 = @boolToInt(s3 < b03); // 324 x

    const p0 = s0 +% (@as(u128, s1) << 64); // 0
    const d0 = @boolToInt(p0 < b00); // 128
    const q1 = s2 +% (s1 >> 64) +% (s3 << 64); // 128
    const d1 = @boolToInt(q1 < s2); // 256
    const p1 = q1 +% (@as(u128, c1) << 64) +% d0; // 128
    const d2 = @boolToInt(p1 < q1); // 256
    const p2 = b13 +% (s3 >> 64) +% c2 +% (@as(u128, c3) << 64) +% d1 +% d2; // 256

    if (shift < 128) {
        const r0 = corr + ((p0 >> @intCast(u7, shift)) | (p1 << @intCast(u7, 128 - shift)));
        const r1 = ((p1 >> @intCast(u7, shift) | (p2 << @intCast(u7, 128 - shift)))) + @boolToInt(r0 < corr);
        result[0] = @truncate(u64, r0);
        result[1] = @intCast(u64, r0 >> 64);
        result[2] = @truncate(u64, r1);
        result[3] = @intCast(u64, r1 >> 64);
    } else if (shift == 128) {
        const r0 = corr + p1;
        const r1 = p2 + @boolToInt(r0 < corr);
        result[0] = @truncate(u64, r0);
        result[1] = @intCast(u64, r0 >> 64);
        result[2] = @truncate(u64, r1);
        result[3] = @intCast(u64, r1 >> 64);
    } else {
        const r0 = corr + ((p1 >> @intCast(u7, shift - 128)) | (p2 << @intCast(u7, 256 - shift)));
        const r1 = (p2 >> @intCast(u7, shift - 128)) + @boolToInt(r0 < corr);
        result[0] = @truncate(u64, r0);
        result[1] = @intCast(u64, r0 >> 64);
        result[2] = @truncate(u64, r1);
        result[3] = @intCast(u64, r1 >> 64);
    }
}

// Returns true if value is divisible by 2^p.
pub fn multipleOfPowerOf2(value: u128, p: u32) bool {
    return @ctz(u128, value) >= p;
}

pub fn mulShift(m: u128, mul: []const u64, j: i32) u128 {
    std.debug.assert(j > 128);

    var a: [2]u64 = undefined;

    a[0] = @truncate(u64, m);
    a[1] = @intCast(u64, m >> 64);

    var result: [4]u64 = undefined;

    mul_128_256_shift(a[0..], mul, @intCast(u32, j), 0, result[0..]);
    return (@as(u128, result[1]) << 64) | result[0];
}

test "ryu128.tables multipleOfPowerOf5" {
    assert(multipleOfPowerOf5(@as(u128, 1), 0));
    assert(!multipleOfPowerOf5(@as(u128, 1), 1));
    assert(multipleOfPowerOf5(@as(u128, 5), 1));
    assert(multipleOfPowerOf5(@as(u128, 25), 2));
    assert(multipleOfPowerOf5(@as(u128, 75), 2));
    assert(multipleOfPowerOf5(@as(u128, 50), 2));
    assert(!multipleOfPowerOf5(@as(u128, 51), 2));
    assert(!multipleOfPowerOf5(@as(u128, 75), 4));
}

test "ryu128.tables multipleOfPowerOf2" {
    assert(multipleOfPowerOf5(@as(u128, 1), 0));
    assert(!multipleOfPowerOf5(@as(u128, 1), 1));
    assert(multipleOfPowerOf2(@as(u128, 2), 1));
    assert(multipleOfPowerOf2(@as(u128, 4), 2));
    assert(multipleOfPowerOf2(@as(u128, 8), 2));
    assert(multipleOfPowerOf2(@as(u128, 12), 2));
    assert(!multipleOfPowerOf2(@as(u128, 13), 2));
    assert(!multipleOfPowerOf2(@as(u128, 8), 4));
}

test "ryu128.tables mulShift" {
    var m = &[_]u64{ 0, 0, 2, 0 };
    assert(mulShift(1, m, 129) == 1);
    assert(mulShift(12345, m, 129) == 12345);
}

test "ryu128.tables mulShiftHuge" {
    var m = &[_]u64{ 0, 0, 8, 0 };
    const f = (@as(u128, 123) << 64) | 321;
    assert(mulShift(f, m, 131) == f);
}

test "ryu128.tables log10pow2" {
    assert(log10Pow2(1) == 0);
    assert(log10Pow2(5) == 1);
    assert(log10Pow2(1 << 15) == 9864);
}

test "ryu128.tables log10pow5" {
    assert(log10Pow5(1) == 0);
    assert(log10Pow5(2) == 1);
    assert(log10Pow5(3) == 2);
    assert(log10Pow5(1 << 15) == 22903);
}
