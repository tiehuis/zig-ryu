const std = @import("std");

const ryu32_backend = @import("ryu32.zig");
const ryu64_backend = @import("ryu64.zig");
const ryu128_backend = @import("ryu128.zig");

pub const ryu16 = ryu128_backend.ryu16;
pub const ryuAlloc16 = ryu128_backend.ryuAlloc16;

pub const ryu32 = ryu32_backend.ryu32;
pub const ryuAlloc32 = ryu32_backend.ryuAlloc32;

pub const ryu64 = ryu64_backend.ryu64;
pub const ryuAlloc64 = ryu64_backend.ryuAlloc64;

pub const ryu80 = ryu128_backend.ryu80;
pub const ryuAlloc80 = ryu128_backend.ryuAlloc80;

pub const ryu128 = ryu128_backend.ryu128;
pub const ryuAlloc128 = ryu128_backend.ryuAlloc128;

// The following buffer sizes are required for each type:
//
// f16  - 11
// f32  - 16
// f64  - 25
// f80  - 53
// f128 - 53
fn floatToBuffer(x: var, buffer: []u8) []u8 {
    const T = @typeOf(x);
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

fn floatToString(a: *std.mem.Allocator, x: var) ![]u8 {
    const T = @typeOf(x);
    return switch (T) {
        f16 => ryuAlloc16(a, x),
        f32 => ryuAlloc32(a, x),
        f64 => ryuAlloc64(a, x),
        c_longdouble => switch (T.bit_count) {
            80 => ryuAlloc80(a, x),
            128 => ryuAlloc128(a, x),
        },
        f128 => ryuAlloc128(a, x),
        else => @compileError("floatToBuffer not implemented for " ++ @typeName(T)),
    };
}

test "ryu buffer interface" {
    var buffer: [53]u8 = undefined;
    var slice: []u8 = undefined;

    slice = floatToBuffer(f16(0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));

    slice = floatToBuffer(f32(0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));

    slice = floatToBuffer(f64(0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));

    //slice = floatToBuffer(c_longdouble(0.0), buffer[0..]);
    //std.debug.assert(std.mem.eql(u8, "0E0", slice));

    slice = floatToBuffer(f128(0.0), buffer[0..]);
    std.debug.assert(std.mem.eql(u8, "0E0", slice));
}

test "ryu string interface" {
    var al = std.debug.global_allocator;

    std.debug.assert(std.mem.eql(u8, "0E0", try floatToString(al, f16(0.0))));
    std.debug.assert(std.mem.eql(u8, "0E0", try floatToString(al, f32(0.0))));
    std.debug.assert(std.mem.eql(u8, "0E0", try floatToString(al, f64(0.0))));
    //std.debug.assert(std.mem.eql(u8, "0E0", try floatToString(al, c_longdouble(0.0))));
    std.debug.assert(std.mem.eql(u8, "0E0", try floatToString(al, f128(0.0))));
}
