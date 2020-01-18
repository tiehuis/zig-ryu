const std = @import("std");

usingnamespace @import("tables_digits.zig");

pub const DOUBLE_MANTISSA_BITS = 52;
pub const DOUBLE_EXPONENT_BITS = 11;
pub const DOUBLE_BIAS = 1023;

pub fn copy_special_string(result: []u8, sign: bool, mantissa: u64) []u8 {
    if (mantissa != 0) {
        std.mem.copy(u8, result, "nan");
        return result[0..3];
    }

    if (sign) {
        result[0] = '-';
    }

    const offset: usize = @boolToInt(sign);

    std.mem.copy(u8, result[offset..], "Infinity");
    return result[0 .. offset + 8];
}

pub inline fn append_d_digits(result: []u8, olength: u32, digits_: u32) void {
    var digits = digits_;

    var i: usize = 0;
    while (digits >= 10000) {
        const c = digits % 10000;
        digits /= 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;
        std.mem.copy(u8, result[olength + 1 - i - 2 ..], DIGIT_TABLE[c0 .. c0 + 2]);
        std.mem.copy(u8, result[olength + 1 - i - 4 ..], DIGIT_TABLE[c1 .. c1 + 2]);
        i += 4;
    }
    if (digits >= 100) {
        const c = (digits % 100) << 1;
        digits /= 100;
        std.mem.copy(u8, result[olength + 1 - i - 2 ..], DIGIT_TABLE[c .. c + 2]);
        i += 2;
    }
    if (digits >= 10) {
        const c = digits << 1;
        result[2] = DIGIT_TABLE[c + 1];
        result[1] = '.';
        result[0] = DIGIT_TABLE[c];
    } else {
        result[1] = '.';
        result[0] = '0' + @intCast(u8, digits);
    }
}

pub inline fn append_c_digits(result: []u8, count: u32, digits_: u32) void {
    var digits = digits_;

    var i: usize = 0;
    while (i < count - 1) : (i += 2) {
        const c = (digits % 100) << 1;
        digits /= 100;
        std.mem.copy(u8, result[count - i - 2 ..], DIGIT_TABLE[c .. c + 2]);
    }
    if (i < count) {
        const c = '0' + @intCast(u8, digits % 10);
        result[count - i - 1] = c;
    }
}

pub inline fn append_n_digits(result: []u8, olength: u32, digits_: u32) void {
    var digits = digits_;

    var i: usize = 0;
    while (digits >= 10000) {
        const c = digits % 10000;
        digits /= 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;
        std.mem.copy(u8, result[olength - i - 2 ..], DIGIT_TABLE[c0 .. c0 + 2]);
        std.mem.copy(u8, result[olength - i - 4 ..], DIGIT_TABLE[c1 .. c1 + 2]);
        i += 4;
    }
    if (digits >= 100) {
        const c = (digits % 100) << 1;
        digits /= 100;
        std.mem.copy(u8, result[olength - i - 2 ..], DIGIT_TABLE[c .. c + 2]);
        i += 2;
    }
    if (digits >= 10) {
        const c = digits << 1;
        std.mem.copy(u8, result[olength - i - 2 ..], DIGIT_TABLE[c .. c + 2]);
    } else {
        result[0] = '0' + @intCast(u8, digits);
    }
}

pub inline fn append_nine_digits(result: []u8, digits_: u32) void {
    var digits = digits_;

    if (digits == 0) {
        std.mem.set(u8, result[0..9], '0');
        return;
    }

    var i: usize = 0;
    while (i < 5) : (i += 4) {
        const c = digits % 10000;
        digits /= 10000;
        const c0 = (c % 100) << 1;
        const c1 = (c / 100) << 1;
        std.mem.copy(u8, result[7 - i ..], DIGIT_TABLE[c0 .. c0 + 2]);
        std.mem.copy(u8, result[5 - i ..], DIGIT_TABLE[c1 .. c1 + 2]);
    }

    result[0] = '0' + @intCast(u8, digits);
}
