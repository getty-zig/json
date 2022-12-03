const std = @import("std");

const math = std.math;
const meta = std.meta;

pub fn formatInt(value: anytype, writer: anytype) @TypeOf(writer).Error!void {
    comptime std.debug.assert(meta.trait.isIntegral(@TypeOf(value)));

    // Coerce integers into an i8 or larger integer type.
    //
    // The reason we need to do this because formatDecimal may need to perform
    // @rem(value, 100), but 100 can't fit in unsigned integers with less than
    // 7 bits or signed integers with less than 8 bits.
    const Int = switch (@typeInfo(@TypeOf(value))) {
        .ComptimeInt => blk: {
            const Fitted = math.IntFittingRange(value, value);
            break :blk if (meta.bitCount(Fitted) < 8) i8 else Fitted;
        },
        .Int => blk: {
            const Fitted = math.IntFittingRange(math.minInt(@TypeOf(value)), math.maxInt(@TypeOf(value)));
            break :blk if (meta.bitCount(Fitted) < 8) i8 else Fitted;
        },
        else => unreachable,
    };

    const int = @as(Int, value);

    // TODO: Change to digits10 + 1 for better space efficiency.
    var buf: [math.max(meta.bitCount(Int), 1) + 1]u8 = undefined;
    var start = switch (@typeInfo(Int).Int.signedness) {
        .signed => blk: {
            var start = formatDecimal(std.math.absCast(int), &buf);

            if (value < 0) {
                start -= 1;
                buf[start] = '-';
            }

            break :blk start;
        },
        .unsigned => formatDecimal(int, &buf),
    };

    try writer.writeAll(buf[start..]);
}

fn formatDecimal(value: anytype, buf: []u8) usize {
    comptime std.debug.assert(@typeInfo(@TypeOf(value)) == .Int);

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

/// Converts values in the range [0, 100) to a string.
fn digits2(value: usize) []const u8 {
    return ("0001020304050607080910111213141516171819" ++
        "2021222324252627282930313233343536373839" ++
        "4041424344454647484950515253545556575859" ++
        "6061626364656667686970717273747576777879" ++
        "8081828384858687888990919293949596979899")[value * 2 ..];
}

/// Returns the number of digits in `value`.
fn countDigits(value: anytype) usize {
    comptime std.debug.assert(@typeInfo(@TypeOf(value)) == .Int);

    const bits = comptime math.log2(10);
    var n: usize = 1;

    {
        var v = value >> bits;
        while (v != 0) : (n += 1) v >>= bits;
    }

    return n;
}
