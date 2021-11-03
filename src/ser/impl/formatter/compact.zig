const std = @import("std");

const ser = @import("../../../lib.zig").ser;

const Formatter = ser.Formatter;

pub fn CompactFormatter(comptime Writer: type) type {
    return struct {
        const Self = @This();
        const impl = @"impl CompactFormatter"(Writer);

        pub usingnamespace Formatter(
            *Self,
            Writer,
            impl.formatter.writeNull,
            impl.formatter.writeBool,
            impl.formatter.writeInt,
            impl.formatter.writeFloat,
            impl.formatter.writeNumberString,
            impl.formatter.beginString,
            impl.formatter.endString,
            impl.formatter.writeStringFragment,
            impl.formatter.writeCharEscape,
            impl.formatter.beginArray,
            impl.formatter.endArray,
            impl.formatter.beginArrayValue,
            impl.formatter.endArrayValue,
            impl.formatter.beginObject,
            impl.formatter.endObject,
            impl.formatter.beginObjectKey,
            impl.formatter.endObjectKey,
            impl.formatter.beginObjectValue,
            impl.formatter.endObjectValue,
            impl.formatter.writeRawFragment,
        );
    };
}

fn @"impl CompactFormatter"(comptime Writer: type) type {
    const Self = CompactFormatter(Writer);

    return struct {
        pub const formatter = struct {
            pub fn writeNull(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("null");
            }

            pub fn writeBool(_: *Self, writer: Writer, value: bool) Writer.Error!void {
                try writer.writeAll(if (value) "true" else "false");
            }

            pub fn writeInt(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                const T = @TypeOf(value);

                const Int = switch (@typeInfo(T)) {
                    .Int => T,
                    .ComptimeInt => blk: {
                        // The `Fitted` type is converted into a u7 so that
                        // @rem(value, 100) can be computed in `formatDecimal`.
                        //
                        // Integer types with less than 7 bits cause a compile
                        // error since 100 cannot be coerced into such types.
                        const Fitted = std.math.IntFittingRange(value, value);
                        break :blk if (std.meta.bitCount(Fitted) < 7) u7 else Fitted;
                    },
                    else => unreachable,
                };

                try formatInt(@as(Int, value), writer);
            }

            pub fn writeFloat(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                // this should be enough to display all decimal places of a decimal f64 number.
                var buf: [512]u8 = undefined;
                var stream = std.io.fixedBufferStream(&buf);

                std.fmt.formatFloatScientific(value, std.fmt.FormatOptions{}, stream.writer()) catch |err| switch (err) {
                    error.NoSpaceLeft => unreachable,
                    else => unreachable, // TODO: handle error
                };

                // TODO: fix getPos error
                try writer.writeAll(buf[0 .. stream.getPos() catch unreachable]);
            }

            pub fn writeNumberString(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                try writer.writeAll(value);
            }

            pub fn beginString(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("\"");
            }

            pub fn endString(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("\"");
            }

            pub fn writeStringFragment(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                try writer.writeAll(value);
            }

            pub fn writeCharEscape(_: *Self, writer: Writer, value: u21) Writer.Error!void {
                try ser.escapeChar(value, writer);
            }

            pub fn beginArray(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("[");
            }

            pub fn endArray(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("]");
            }

            pub fn beginArrayValue(_: *Self, writer: Writer, first: bool) Writer.Error!void {
                if (!first)
                    try writer.writeAll(",");
            }

            pub fn endArrayValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
                _ = writer;
            }

            pub fn beginObject(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("{");
            }

            pub fn endObject(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("}");
            }

            pub fn beginObjectKey(_: *Self, writer: Writer, first: bool) Writer.Error!void {
                if (!first)
                    try writer.writeAll(",");
            }

            pub fn endObjectKey(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
                _ = writer;
            }

            pub fn beginObjectValue(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll(":");
            }

            pub fn endObjectValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
                _ = writer;
            }

            pub fn writeRawFragment(self: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                _ = self;

                try writer.writeAll(value);
            }
        };
    };
}

// Converts values in the range [0, 100) to a string.
fn digits2(value: usize) []const u8 {
    const digits =
        "0001020304050607080910111213141516171819" ++
        "2021222324252627282930313233343536373839" ++
        "4041424344454647484950515253545556575859" ++
        "6061626364656667686970717273747576777879" ++
        "8081828384858687888990919293949596979899";

    return digits[value * 2 ..];
}

/// Returns the number of digits in `value`.
fn countDigits(value: anytype) usize {
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

fn formatDecimal(value: anytype, buf: []u8) !usize {
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

fn formatInt(value: anytype, writer: anytype) !void {
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
