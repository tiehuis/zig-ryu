pub const ryu64 = struct {
    pub const max_buf_size = struct {
        // TODO: Some of these bounds can be tightened
        pub const scientific = 2000;
        pub const fixed = 2000;
        pub const hex = 32;
        pub const shortest = 25;
    };

    pub const printScientific = @import("ryu64/print_scientific.zig").printScientific;
    pub const printFixed = @import("ryu64/print_fixed.zig").printFixed;
    pub const printHex = @import("ryu64/print_hex.zig").printHex;
    pub const printShortest = @import("ryu64/print_shortest.zig").printShortest;
};

pub const ryu32 = struct {
    pub const max_buf_size = struct {
        // TODO: Some of these bounds can be tightened
        pub const scientific = 2000;
        pub const fixed = 2000;
        pub const hex = 32;
        pub const shortest = 16;
    };

    pub inline fn printScientific(result: []u8, d: f32, precision: u32) []u8 {
        return ryu64.printScientific(result, @floatCast(f64, d), precision);
    }

    pub inline fn printFixed(result: []u8, d: f32, precision: u32) []u8 {
        return ryu64.printFixed(result, @floatCast(f64, d), precision);
    }

    pub inline fn printHex(result: []u8, d: f32, precision: u32) []u8 {
        return ryu64.printHex(result, @floatCast(f32, d), precision);
    }

    pub const printShortest = @import("ryu32/print_shortest.zig").printShortest32;
};

pub const ryu16 = struct {
    pub const max_buf_size = struct {
        // TODO: Some of these bounds can be tightened
        pub const scientific = 2000;
        pub const fixed = 2000;
        pub const hex = 32;
        pub const shortest = 16;
    };

    pub inline fn printScientific(result: []u8, d: f16, precision: u32) []u8 {
        return ryu64.printScientific(result, @floatCast(f64, d), precision);
    }

    pub inline fn printFixed(result: []u8, d: f16, precision: u32) []u8 {
        return ryu64.printFixed(result, @floatCast(f64, d), precision);
    }

    pub inline fn printHex(result: []u8, d: f16, precision: u32) []u8 {
        return ryu64.printHex(result, @floatCast(f32, d), precision);
    }

    pub const printShortest = @import("ryu32/print_shortest.zig").printShortest16;
};

pub inline fn ryu(comptime T: type) type {
    return switch (T) {
        f16 => ryu16,
        f32 => ryu32,
        f64 => ryu64,
        else => @compileError("ryu cannot print the type: " ++ @typeName(T)),
    };
}

test "all" {
    _ = @import("ryu64/test_shortest.zig");
    _ = @import("ryu64/test_fixed.zig");
    _ = @import("ryu64/test_scientific.zig");
    _ = @import("ryu64/parse.zig");

    _ = @import("ryu32/test_shortest.zig");
}
