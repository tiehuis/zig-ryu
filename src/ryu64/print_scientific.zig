const std = @import("std");

usingnamespace struct {
    pub usingnamespace @import("../internal.zig");
    pub usingnamespace @import("tables_fixed_and_scientific.zig");
};

pub fn printScientific(result: []u8, d: f64, precision_: u32) []u8 {
    var precision = precision_;
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

        std.mem.copy(u8, result[index .. index + 4], "e+00");
        index += 4;

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

    const print_decimal_point = precision > 0;
    precision += 1;

    var index: usize = 0;
    if (ieee_sign) {
        result[index] = '-';
        index += 1;
    }

    var digits: u32 = 0;
    var printed_digits: u32 = 0;
    var available_digits: u32 = 0;
    var exp: i32 = 0;
    if (e2 >= -52) {
        const idx = if (e2 < 0) 0 else indexForExponent(@intCast(u32, e2));
        const p10bits = pow10BitsForIndex(idx);
        const len = lengthForIndex(idx);

        var i_: usize = 0;
        while (i_ < len) : (i_ += 1) {
            const i = len - i_ - 1;
            const j = @intCast(u32, @intCast(i32, p10bits) - e2);

            digits = mulShift_mod1e9(m2 << 8, POW10_SPLIT[POW10_OFFSET[idx] + i], j + 8);
            if (printed_digits != 0) {
                if (printed_digits + 9 > precision) {
                    available_digits = 9;
                    break;
                }
                append_nine_digits(result[index..], digits);
                index += 9;
                printed_digits += 9;
            } else if (digits != 0) {
                available_digits = decimalLength9(digits);
                exp = @intCast(i32, i * 9 + available_digits) - 1;
                if (available_digits > precision) {
                    break;
                }
                if (print_decimal_point) {
                    append_d_digits(result[index..], available_digits, digits);
                    index += available_digits + 1; // +1 for decimal point
                } else {
                    result[index] = '0' + @intCast(u8, digits);
                    index += 1;
                }
                printed_digits = available_digits;
                available_digits = 0;
            }
        }
    }

    if (e2 < 0 and available_digits == 0) {
        const idx = @intCast(u32, -e2) / 16;

        var i = MIN_BLOCK_2[idx];
        while (i < 200) : (i += 1) {
            const j = ADDITIONAL_BITS_2 + (@intCast(u32, -e2) - 16 * idx);
            const p = POW10_OFFSET_2[idx] + i - MIN_BLOCK_2[idx];
            digits = if (p >= POW10_OFFSET_2[idx + 1]) 0 else mulShift_mod1e9(m2 << 8, POW10_SPLIT_2[p], j + 8);

            if (printed_digits != 0) {
                if (printed_digits + 9 > precision) {
                    available_digits = 9;
                    break;
                }
                append_nine_digits(result[index..], digits);
                index += 9;
                printed_digits += 9;
            } else if (digits != 0) {
                available_digits = decimalLength9(digits);
                exp = -(@intCast(i32, i) + 1) * 9 + @intCast(i32, available_digits) - 1;
                if (available_digits > precision) {
                    break;
                }
                if (print_decimal_point) {
                    append_d_digits(result[index..], available_digits, digits);
                    index += available_digits + 1; // +1 for decimal point
                } else {
                    result[index] = '0' + @intCast(u8, digits);
                    index += 1;
                }
                printed_digits = available_digits;
                available_digits = 0;
            }
        }
    }

    const maximum = precision - printed_digits;

    if (available_digits == 0) {
        digits = 0;
    }
    var last_digit: u32 = 0;
    if (available_digits > maximum) {
        var k: usize = 0;
        while (k < available_digits - maximum) : (k += 1) {
            last_digit = digits % 10;
            digits /= 10;
        }
    }

    const RoundUp = enum {
        Never = 0,
        Always,
        Odd,
    };

    // 0 = don't round up; 1 = round up unconditionally, 2 = round up if odd
    var round_up = RoundUp.Never;
    if (last_digit != 5) {
        round_up = @intToEnum(RoundUp, @boolToInt(last_digit > 5));
    } else {
        // Is m * 2^e2 * 10^(precision + 1 - exp) an integer?
        // precision was already increased by 1, so we don't need to write +1 here.
        const rexp = @intCast(i32, precision) - exp;
        const required_twos = -e2 - rexp;
        var trailing_zeros = required_twos <= 0 or
            (required_twos < 60 and multipleOfPowerOf2(m2, @intCast(u32, required_twos)));
        if (rexp < 0) {
            const required_fives = -rexp;
            trailing_zeros = trailing_zeros and multipleOfPowerOf5(m2, @intCast(u32, required_fives));
        }
        round_up = if (trailing_zeros) .Odd else .Always;
    }
    if (printed_digits != 0) {
        if (digits == 0) {
            std.mem.set(u8, result[index .. index + maximum], '0');
        } else {
            append_c_digits(result[index..], maximum, digits);
        }
        index += maximum;
    } else {
        if (print_decimal_point) {
            append_d_digits(result[index..], maximum, digits);
            index += maximum + 1; // +1 for decimal point
        } else {
            result[index] = '0' + @intCast(u8, digits);
            index += 1;
        }
    }

    if (round_up != .Never) {
        var round_index = @intCast(i32, index);
        while (true) {
            round_index -= 1;

            var c: u8 = undefined;
            if (round_index != -1) {
                c = result[@intCast(usize, round_index)];
            }

            if (round_index == -1 or c == '-') {
                result[@intCast(usize, round_index + 1)] = '1';
                exp += 1;
                break;
            }
            if (c == '.') {
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

    result[index] = 'e';
    index += 1;
    if (exp < 0) {
        result[index] = '-';
        index += 1;
        exp = -exp;
    } else {
        result[index] = '+';
        index += 1;
    }

    const pexp = @intCast(u32, exp);

    if (pexp >= 100) {
        const c = pexp % 10;
        std.mem.copy(u8, result[index..], DIGIT_TABLE[2 * (pexp / 10) .. 2 * (pexp / 10) + 2]);
        result[index + 2] = '0' + @intCast(u8, c);
        index += 3;
    } else {
        std.mem.copy(u8, result[index..], DIGIT_TABLE[2 * pexp .. 2 * pexp + 2]);
        index += 2;
    }

    return result[0..index];
}
