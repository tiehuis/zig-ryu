const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut();
    var buf: [10000]u8 = undefined;

    inline for (.{ f128, f80, c_longdouble, f64, f32, f16 }) |T| {
        const f = 3.12345678910111213141516171819202122232425;
        const c = try std.fmt.bufPrint(&buf, "{}", .{@as(T, f)});

        _ = try stdout.write(c);
        _ = try stdout.write(" :" ++ @typeName(T) ++ "\n");
    }
}
