const std = @import("std");

const math = std.math;
const meta = std.meta;

pub fn formatInt(value: anytype, writer: anytype) @TypeOf(writer).Error!void {
    comptime std.debug.assert(meta.trait.isIntegral(@TypeOf(value)));

    const Int = switch (@typeInfo(@TypeOf(value))) {
        .Int => @TypeOf(value),
        .ComptimeInt => blk: {
            // Coerce comptime_int into an appropriate integer type.
            //
            // The `Fitted` type is converted into a i8 so that @rem(value,
            // 100) can be computed in `formatDecimal`.
            //
            // Unsigned comptime_ints with less than 7 bits and signed
            // comptime_ints with less than 8 bits cause a compile error since
            // 100 cannot be coerced into such types.
            const Fitted = math.IntFittingRange(value, value);
            break :blk if (meta.bitCount(Fitted) < 8) i8 else Fitted;
        },
        else => unreachable,
    };
    const int = @as(Int, value);

    // TODO: Change to digits10 + 1 for better space efficiency.
    var buf: [math.max(meta.bitCount(Int), 1) + 1]u8 = undefined;
    var start = switch (@typeInfo(Int).Int.signedness) {
        .signed => blk: {
            var start = formatDecimal(abs(int), &buf);

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

/// Returns the absolute value of `x`.
///
/// The return type of `abs` is the smallest type between u32, u64, and u128
/// that can store all possible absolute values of the type of `x`. For
/// example, if the type of `x` is i8, then the greatest absolute value
/// possible is 128. 128 can be stored as a u32, and u32 is smaller than u64
/// and u128, so u32 is the return type.
///
/// For positive integers, `x` is simply casted to the return type and
/// returned.
///
/// For negative integers, if `x` is greater than the smallest possible value
/// of @TypeOf(x), then the negation of `x` is casted to the return type and is
/// returned. Otherwise, the wrapped difference between `x` and 1 is casted to
/// the return type and the sum between the difference and 1 is returned.
fn abs(x: anytype) U32Or64Or128(@TypeOf(x)) {
    const T = @TypeOf(x);
    comptime std.debug.assert(@typeInfo(T) == .Int);
    const Unsigned = U32Or64Or128(T);

    if (x > 0) return @intCast(Unsigned, x);

    if (x > math.minInt(T)) {
        return @intCast(Unsigned, -x);
    } else {
        return @intCast(Unsigned, x -% 1) + 1;
    }
}

/// Returns the smallest type between u32, u64, and u128 that can hold all
/// positive values of T.
fn U32Or64Or128(comptime T: type) type {
    comptime std.debug.assert(@typeInfo(T) == .Int);
    comptime std.debug.assert(@typeInfo(T).Int.bits <= 128);

    const max = math.maxInt(T);
    const max_u32 = math.maxInt(u32);
    const max_u64 = math.maxInt(u64);
    const max_u128 = math.maxInt(u128);

    if (max <= max_u32) return u32;
    if (max <= max_u64) return u64;
    if (max <= max_u128) return u128;

    // UNREACHABLE: It is asserted above that the number of bits in T is less
    // than or equal to 128.
    unreachable;
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
