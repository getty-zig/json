const escape = @import("details/escape.zig");
const fmt = @import("details/fmt.zig");
const std = @import("std");

const Formatter = @import("../../../lib.zig").ser.Formatter;

pub fn CompactFormatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub usingnamespace Formatter(
            *Self,
            Writer,
            writeNull,
            writeBool,
            writeInt,
            writeFloat,
            writeNumberString,
            beginString,
            endString,
            writeStringFragment,
            writeCharEscape,
            beginArray,
            endArray,
            beginArrayValue,
            endArrayValue,
            beginObject,
            endObject,
            beginObjectKey,
            endObjectKey,
            beginObjectValue,
            endObjectValue,
            writeRawFragment,
        );
        fn writeNull(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("null");
        }

        fn writeBool(_: *Self, writer: Writer, value: bool) Writer.Error!void {
            try writer.writeAll(if (value) "true" else "false");
        }

        fn writeInt(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
            try fmt.formatInt(value, writer);
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
            try escape.escapeChar(value, writer);
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

        fn endArrayValue(_: *Self, _: Writer) Writer.Error!void {}

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

        fn endObjectKey(_: *Self, _: Writer) Writer.Error!void {}

        fn beginObjectValue(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll(":");
        }

        fn endObjectValue(_: *Self, _: Writer) Writer.Error!void {}

        fn writeRawFragment(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
            try writer.writeAll(value);
        }
    };
}
