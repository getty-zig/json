const formatter = @import("../formatter.zig");
const std = @import("std");

pub fn Formatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        const Interface = enum {
            Formatter,
        };

        pub fn interface(self: *Self, comptime iface: Interface) switch (iface) {
            .Formatter => blk: {
                const Impl = struct {
                    fn writeNull(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("null");
                    }

                    fn writeBool(_: *Self, writer: Writer, value: bool) Writer.Error!void {
                        try writer.writeAll(if (value) "true" else "false");
                    }

                    fn writeInt(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                        var buf: [100]u8 = undefined;
                        try writer.writeAll(std.fmt.bufPrintIntToSlice(&buf, value, 10, .lower, .{}));
                    }

                    fn writeFloat(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                        // this should be enough to display all decimal places of a decimal f64 number.
                        var buf: [512]u8 = undefined;
                        var stream = std.io.fixedBufferStream(&buf);

                        std.fmt.formatFloatDecimal(value, std.fmt.FormatOptions{}, stream.writer()) catch |err| switch (err) {
                            error.NoSpaceLeft => unreachable,
                            else => unreachable, // TODO: handle error
                        };

                        // TODO: fix getPos error
                        try writer.writeAll(buf[0 .. stream.getPos() catch unreachable]);
                    }

                    fn writeNumberString(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                        try writer.writeAll(value);
                    }

                    fn beginString(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("\"");
                    }

                    fn endString(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("\"");
                    }

                    fn writeStringFragment(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                        try writer.writeAll(value);
                    }

                    /// TODO: Figure out what to do on ascii control
                    fn writeCharEscape(_: *Self, writer: Writer, value: formatter.CharEscape) Writer.Error!void {
                        switch (value) {
                            .ascii => |v| {
                                const HEX_DIGITS: []const u8 = "0123456789abcdef";
                                const s = &[_]u8{
                                    '\\',
                                    'u',
                                    '0',
                                    '0',
                                    HEX_DIGITS[v >> 4],
                                    HEX_DIGITS[v & 0xF],
                                };

                                try writer.writeAll(s);
                            },
                            .non_ascii => |v| {
                                const s = switch (v) {
                                    .Quote => "\\\"",
                                    .ReverseSolidus => "\\\\",
                                    .Solidus => "\\/",
                                    .Backspace => "\\",
                                    .FormFeed => "\\f",
                                    .LineFeed => "\\n",
                                    .CarriageReturn => "\\r",
                                    .Tab => "\\t",
                                };

                                try writer.writeAll(s);
                            },
                        }
                    }

                    fn beginArray(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("[");
                    }

                    fn endArray(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("]");
                    }

                    fn beginArrayValue(_: *Self, writer: Writer, first: bool) Writer.Error!void {
                        if (!first)
                            try writer.writeAll(",");
                    }

                    fn endArrayValue(f: *Self, writer: Writer) Writer.Error!void {
                        _ = f;
                        _ = writer;
                    }

                    fn beginObject(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("{");
                    }

                    fn endObject(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll("}");
                    }

                    fn beginObjectKey(_: *Self, writer: Writer, first: bool) Writer.Error!void {
                        if (!first)
                            try writer.writeAll(",");
                    }

                    fn endObjectKey(f: *Self, writer: Writer) Writer.Error!void {
                        _ = f;
                        _ = writer;
                    }

                    fn beginObjectValue(_: *Self, writer: Writer) Writer.Error!void {
                        try writer.writeAll(":");
                    }

                    fn endObjectValue(f: *Self, writer: Writer) Writer.Error!void {
                        _ = f;
                        _ = writer;
                    }

                    fn writeRawFragment(f: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                        _ = f;

                        try writer.writeAll(value);
                    }
                };

                break :blk formatter.Formatter(
                    *Self,
                    Writer,
                    Impl.writeNull,
                    Impl.writeBool,
                    Impl.writeInt,
                    Impl.writeFloat,
                    Impl.writeNumberString,
                    Impl.beginString,
                    Impl.endString,
                    Impl.writeStringFragment,
                    Impl.writeCharEscape,
                    Impl.beginArray,
                    Impl.endArray,
                    Impl.beginArrayValue,
                    Impl.endArrayValue,
                    Impl.beginObject,
                    Impl.endObject,
                    Impl.beginObjectKey,
                    Impl.endObjectKey,
                    Impl.beginObjectValue,
                    Impl.endObjectValue,
                    Impl.writeRawFragment,
                );
            },
        } {
            return .{ .context = self };
        }
    };
}
