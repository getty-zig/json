const std = @import("std");

// Converts values in the range [0, 100) to a string.
pub fn digits2(value: usize) []const u8 {
    const digits =
        "0001020304050607080910111213141516171819" ++
        "2021222324252627282930313233343536373839" ++
        "4041424344454647484950515253545556575859" ++
        "6061626364656667686970717273747576777879" ++
        "8081828384858687888990919293949596979899";

    return digits[value * 2 ..];
}

/// Returns the number of digits in `value`.
pub fn countDigits(value: anytype) usize {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    comptime std.debug.assert(info == .Int);

    const bits = comptime std.math.log2(10);
    var n: usize = 1;

    {
        var v = value >> bits;
        while (v != 0) : (n += 1) v >>= bits;
    }

    return n;
}

pub fn formatDecimal(value: anytype, buf: []u8) !usize {
    const info = @typeInfo(@TypeOf(value));

    comptime std.debug.assert(info == .Int);

    var v = value;
    var index: usize = buf.len;

    while (v >= 100) : (v = @divTrunc(v, 100)) {
        index -= 2;
        std.mem.copy(u8, buf[index..], digits2(@intCast(usize, @rem(v, 100)))[0..2]);
    }

    if (v < 10) {
        index -= 1;
        buf[index] = '0' + @intCast(u8, v);
    } else {
        index -= 2;
        std.mem.copy(u8, buf[index..], digits2(@intCast(usize, v))[0..2]);
    }

    return index;
}

pub fn formatInt(value: anytype, writer: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    comptime std.debug.assert(info == .Int or info == .ComptimeInt);

    // This buffer should be large enough to hold all digits and a sign.
    //
    // TODO: Change to digits10 + 1.
    var buf: [std.math.max(std.meta.bitCount(T), 1) + 1]u8 = undefined;

    var start = switch (info.Int.signedness) {
        .signed => blk: {
            const abs = std.math.absInt(@as(i128, value)) catch unreachable; // TODO: change unreachable

            var start = try formatDecimal(abs, &buf);

            if (value < 0) {
                start -= 1;
                buf[start] = '-';
            }

            break :blk start;
        },
        .unsigned => try formatDecimal(value, &buf),
    };

    try writer.writeAll(buf[start..]);
}
