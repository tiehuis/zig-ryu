// C interface for testing.
//
// This matches ryu.h from the reference implementation.

const std = @import("std");

const ryu32 = @import("ryu32.zig");
const ryu64 = @import("ryu64.zig");

var allocator = std.heap.c_allocator;

export fn d2s_buffered_n(f: f64, result: [*]u8) c_int {
    const s = ryu64.ryu64(f, result[0..25]);
    return @intCast(c_int, s.len);
}

export fn d2s_buffered(f: f64, result: [*]u8) void {
    const index = d2s_buffered_n(f, result);
    result[@intCast(usize, index)] = 0;
}

export fn d2s(f: f64) ?[*]u8 {
    var m = allocator.alloc(u8, 25) catch return null;
    const s = ryu64.ryu64(f, m);
    m[s.len] = 0;
    return m.ptr;
}

export fn f2s_buffered_n(f: f32, result: [*]u8) c_int {
    const s = ryu32.ryu32(f, result[0..25]);
    return @intCast(c_int, s.len);
}

export fn f2s_buffered(f: f32, result: [*]u8) void {
    const index = f2s_buffered_n(f, result);
    result[@intCast(usize, index)] = 0;
}

export fn f2s(f: f32) ?[*]u8 {
    var m = allocator.alloc(u8, 25) catch return null;
    const s = ryu32.ryu32(f, m);
    m[s.len] = 0;
    return m.ptr;
}
