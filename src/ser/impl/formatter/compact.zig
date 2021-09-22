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
                try ser.escapeChar(value, writer);
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
