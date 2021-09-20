const std = @import("std");

const ser = @import("../../../lib.zig").ser;

const Formatter = ser.Formatter;

pub fn CompactFormatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        /// Implements `json.ser.Formatter`.
        pub usingnamespace Formatter(
            *Self,
            Writer,
            _F.writeNull,
            _F.writeBool,
            _F.writeInt,
            _F.writeFloat,
            _F.writeNumberString,
            _F.beginString,
            _F.endString,
            _F.writeStringFragment,
            _F.writeCharEscape,
            _F.beginArray,
            _F.endArray,
            _F.beginArrayValue,
            _F.endArrayValue,
            _F.beginObject,
            _F.endObject,
            _F.beginObjectKey,
            _F.endObjectKey,
            _F.beginObjectValue,
            _F.endObjectValue,
            _F.writeRawFragment,
        );

        const _F = struct {
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

                std.fmt.formatFloatScientific(value, std.fmt.FormatOptions{}, stream.writer()) catch |err| switch (err) {
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

            fn writeCharEscape(_: *Self, writer: Writer, value: u21) Writer.Error!void {
                switch (value) {
                    ser.DOUBLE_QUOTE => try writer.writeAll("\\\""),
                    ser.BACKSLASH => try writer.writeAll("\\\\"),
                    ser.BACKSPACE => try writer.writeAll("\\b"),
                    ser.TAB => try writer.writeAll("\\t"),
                    ser.NEWLINE => try writer.writeAll("\\n"),
                    ser.FORM_FEED => try writer.writeAll("\\f"),
                    ser.CARRIAGE_RETURN => try writer.writeAll("\\r"),
                    else => switch (value) {
                        0x00...0x1F, 0x7F, 0x2028, 0x2029 => {
                            // If the character is in the Basic Multilingual Plane
                            // (U+0000 through U+FFFF), then it may be represented as a
                            // six-character sequence: a reverse solidus, followed by
                            // the lowercase letter u, followed by four hexadecimal
                            // digits that encode the character's code point.
                            try writer.writeAll("\\u");
                            try std.fmt.formatIntValue(value, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, writer);
                        },
                        else => if (value > 0xFFFF) {
                            // To escape an extended character that is not in
                            // the Basic Multilingual Plane, the character is
                            // represented as a 12-character sequence, encoding
                            // the UTF-16 surrogate pair.
                            std.debug.assert(value <= 0x10FFFF);

                            const high = @intCast(u16, (value - 0x10000) >> 10) + 0xD800;
                            const low = @intCast(u16, value & 0x3FF) + 0xDC00;

                            try writer.writeAll("\\u");
                            try std.fmt.formatIntValue(high, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, writer);
                            try writer.writeAll("\\u");
                            try std.fmt.formatIntValue(low, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, writer);
                        } else {
                            // UNREACHABLE: these codepoints should not be escaped.
                            unreachable;
                        },
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

            fn endArrayValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
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

            fn endObjectKey(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
                _ = writer;
            }

            fn beginObjectValue(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll(":");
            }

            fn endObjectValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
                _ = writer;
            }

            fn writeRawFragment(self: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                _ = self;

                try writer.writeAll(value);
            }
        };
    };
}
