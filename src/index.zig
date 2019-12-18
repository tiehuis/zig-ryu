const std = @import("std");

const ryu32_backend = @import("ryu32.zig");
const ryu64_backend = @import("ryu64.zig");
const ryu128_backend = @import("ryu128.zig");

pub const ryu16 = ryu32_backend.ryu16;
pub const ryu32 = ryu32_backend.ryu32;
pub const ryu64 = ryu64_backend.ryu64;
pub const ryu80 = ryu128_backend.ryu80;
pub const ryu128 = ryu128_backend.ryu128;

// The following buffer sizes are required for each type:
//
// f16  - 11
// f32  - 16
// f64  - 25
// f80  - 53 (TODO: Can reduce)
// f128 - 53
fn floatToBuffer(x: var, buffer: []u8) []u8 {
    const T = @TypeOf(x);
    return switch (T) {
        f16 => ryu16(x, buffer),
        f32 => ryu32(x, buffer),
        f64 => ryu64(x, buffer),
        c_longdouble => switch (T.bit_count) {
            80 => ryu80(x, buffer),
            128 => ryu128(x, buffer),
        },
        f128 => ryu128(x, buffer),
        else => @compileError("floatToBuffer not implemented for " ++ @typeName(T)),
    };
}

test "ryu buffer interface" {
    var buffer: [53]u8 = undefined;
    var slice: []u8 = undefined;

    slice = floatToBuffer(@as(f16, 0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));

    slice = floatToBuffer(@as(f32, 0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));

    slice = floatToBuffer(@as(f64, 0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));

    //slice = floatToBuffer(@as(c_longdouble, 0.0), buffer[0..]);
    //std.debug.assert(std.mem.eql(u8, "0E0", slice));

    slice = floatToBuffer(@as(f128, 0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));
}
