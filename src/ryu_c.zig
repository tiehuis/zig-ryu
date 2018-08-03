// C interface for testing.
//
// This matches ryu.h from the reference implementation.

const std = @import("std");

const ryu32 = @import("ryu32.zig");
const ryu64 = @import("ryu64.zig");

export fn d2s_buffered_n(f: f64, result: [*]u8) c_int {
    const s = ryu64.ryu64(f, result[0..25]);
    return @intCast(c_int, s.len);
}

export fn d2s_buffered(f: f64, result: [*]u8) void {
    const index = d2s_buffered_n(f, result);
    result[@intCast(usize, index)] = 0;
}

export fn d2s(f: f64) ?[*]u8 {
    if (ryu64.ryuAlloc64(std.heap.c_allocator, f)) |p| {
        return p.ptr;
    } else |_| {
        return null;
    }
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
    if (ryu32.ryuAlloc32(std.heap.c_allocator, f)) |p| {
        return p.ptr;
    } else |_| {
        return null;
    }
}
