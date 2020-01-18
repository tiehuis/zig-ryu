//! Print an f64 as a fixed-precision.

const std = @import("std");

usingnamespace struct {
    pub usingnamespace @import("../internal.zig");
    pub usingnamespace @import("tables_fixed_and_scientific.zig");
};

/// Print an f64 in fixed-precision format. Result must be at least XXX bytes but need not be
/// more, as this is the upper limit.
pub fn printFixed(result: []u8, d: f64, precision: u32) []u8 {
    const bits = @bitCast(u64, d);

    const ieee_sign = ((bits >> (DOUBLE_MANTISSA_BITS + DOUBLE_EXPONENT_BITS)) & 1) != 0;
    const ieee_mantissa = bits & ((1 << DOUBLE_MANTISSA_BITS) - 1);
    const ieee_exponent = (bits >> DOUBLE_MANTISSA_BITS) & ((1 << DOUBLE_EXPONENT_BITS) - 1);

    if (ieee_exponent == ((1 << DOUBLE_EXPONENT_BITS) - 1)) {
        return copy_special_string(result, ieee_sign, ieee_mantissa);
    }

    if (ieee_exponent == 0 and ieee_mantissa == 0) {
        var index: usize = 0;
        if (ieee_sign) {
            result[index] = '-';
            index += 1;
        }

        result[index] = '0';
        index += 1;

        if (precision > 0) {
            result[index] = '.';
            index += 1;
            std.mem.set(u8, result[index .. index + precision], '0');
            index += precision;
        }

        return result[0..index];
    }

    var e2: i32 = undefined;
    var m2: u64 = undefined;
    if (ieee_exponent == 0) {
        e2 = 1 - DOUBLE_BIAS - DOUBLE_MANTISSA_BITS;
        m2 = ieee_mantissa;
    } else {
        e2 = @intCast(i32, ieee_exponent) - DOUBLE_BIAS - DOUBLE_MANTISSA_BITS;
        m2 = (1 << DOUBLE_MANTISSA_BITS) | ieee_mantissa;
    }

    var index: usize = 0;
    var nonzero = false;
    if (ieee_sign) {
        result[index] = '-';
        index += 1;
    }

    if (e2 >= -52) {
        const idx = if (e2 < 0) 0 else indexForExponent(@intCast(u32, e2));
        const p10bits = pow10BitsForIndex(idx);
        const len = lengthForIndex(idx);

        var i_: usize = 0;
        while (i_ < len) : (i_ += 1) {
            const i = len - i_ - 1;
            const j = @intCast(u32, @intCast(i32, p10bits) - e2);
            const digits = mulShift_mod1e9(m2 << 8, POW10_SPLIT[POW10_OFFSET[idx] + i], j + 8);

            if (nonzero) {
                append_nine_digits(result[index..], digits);
                index += 9;
            } else if (digits != 0) {
                const olength = decimalLength9(digits);
                append_n_digits(result[index..], olength, digits);
                index += olength;
                nonzero = true;
            }
        }
    }
    if (!nonzero) {
        result[index] = '0';
        index += 1;
    }
    if (precision > 0) {
        result[index] = '.';
        index += 1;
    }

    const RoundUp = enum {
        Never = 0,
        Always,
        Odd,
    };

    if (e2 < 0) {
        const idx = @intCast(u32, -e2) / 16;
        const blocks = precision / 9 + 1;
        var round_up = RoundUp.Never;

        var i: u32 = 0;
        if (blocks <= MIN_BLOCK_2[idx]) {
            i = blocks;
            std.mem.set(u8, result[index .. index + precision], '0');
            index += precision;
        } else if (i < MIN_BLOCK_2[idx]) {
            i = MIN_BLOCK_2[idx];
            std.mem.set(u8, result[index .. index + 9 * i], '0');
            index += 9 * i;
        }

        while (i < blocks) : (i += 1) {
            const j = ADDITIONAL_BITS_2 + @intCast(u32, -e2) - 16 * idx;
            const p = POW10_OFFSET_2[idx] + i - MIN_BLOCK_2[idx];
            if (p >= POW10_OFFSET_2[idx + 1]) {
                // If the remaining digits are all 0, then we might as well use memset.
                // No rounding required in this case.
                const fill = precision - 9 * i;
                std.mem.set(u8, result[index .. index + fill], '0');
                index += fill;
                break;
            }

            var digits = mulShift_mod1e9(m2 << 8, POW10_SPLIT_2[p], j + 8);

            if (i < blocks - 1) {
                append_nine_digits(result[index..], digits);
                index += 9;
            } else {
                const maximum = @intCast(i32, precision) - @intCast(i32, 9 * i);
                var last_digit: u32 = 0;

                var k: usize = 0;
                while (@intCast(i32, k) < 9 - maximum) : (k += 1) {
                    last_digit = digits % 10;
                    digits /= 10;
                }

                if (last_digit != 5) {
                    round_up = @intToEnum(RoundUp, @boolToInt(last_digit > 5));
                } else {
                    // Is m * 10^(additionalDigits + 1) / 2^(-e2) an integer?
                    const required_twos = -e2 - @intCast(i32, precision) - 1;
                    const trailing_zeros = required_twos <= 0 or (required_twos < 60 and
                        multipleOfPowerOf2(m2, @intCast(u32, required_twos)));
                    round_up = if (trailing_zeros) .Odd else .Always;
                }
                if (maximum > 0) {
                    append_c_digits(result[index..], @intCast(u32, maximum), digits);
                    index += @intCast(u32, maximum);
                }
                break;
            }
        }

        if (round_up != .Never) {
            var round_index = @intCast(isize, index);
            var dot_index: usize = 0; // '.' can't be located at index 0
            while (true) {
                // When we hit the first round (-1), then do something different
                round_index -= 1;

                var c: u8 = undefined;
                if (round_index != -1) {
                    c = result[@intCast(usize, round_index)];
                }

                if (round_index == -1 or c == '-') {
                    result[@intCast(usize, round_index + 1)] = '1';
                    if (dot_index > 0) {
                        result[dot_index] = '0';
                        result[dot_index + 1] = '.';
                    }
                    result[index] = '0';
                    index += 1;
                    break;
                }
                if (c == '.') {
                    dot_index = @intCast(usize, round_index);
                    continue;
                } else if (c == '9') {
                    result[@intCast(usize, round_index)] = '0';
                    round_up = .Always;
                    continue;
                } else {
                    if (round_up == .Odd and c % 2 == 0) {
                        break;
                    }
                    result[@intCast(usize, round_index)] = c + 1;
                    break;
                }
            }
        }
    } else {
        std.mem.set(u8, result[index .. index + precision], '0');
        index += precision;
    }

    return result[0..index];
}
