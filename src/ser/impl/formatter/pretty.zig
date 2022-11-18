const escape = @import("details/escape.zig");
const fmt = @import("details/fmt.zig");
const std = @import("std");

const Formatter = @import("../../../lib.zig").ser.Formatter;

pub fn PrettyFormatter(comptime Writer: type) type {
    return struct {
        current: usize,
        has_value: bool,
        indent: []const u8,

        const Self = @This();

        /// Construct a pretty printer formatter that defaults to using two
        /// spaces for indentation.
        pub fn init() Self {
            return initWithIndent("  ");
        }

        /// Construct a pretty printer formatter that uses the `indent` string
        /// for indentation.
        pub fn initWithIndent(indent: []const u8) Self {
            return .{
                .current = 0,
                .has_value = false,
                .indent = indent,
            };
        }

        fn doIndent(self: *Self, writer: anytype) Writer.Error!void {
            var i: usize = 0;

            while (i < self.current) : (i += 1) {
                try writer.writeAll(self.indent);
            }
        }

        pub usingnamespace Formatter(
            *Self,
            Writer,
            .{
                .writeBool = writeBool,
                .writeCharEscape = writeCharEscape,
                .writeInt = writeInt,
                .writeFloat = writeFloat,
                .writeNull = writeNull,
                .writeNumberString = writeNumberString,
                .writeRawFragment = writeRawFragment,
                .writeStringFragment = writeStringFragment,

                .beginArray = beginArray,
                .beginArrayValue = beginArrayValue,
                .beginString = beginString,
                .beginObject = beginObject,
                .beginObjectKey = beginObjectKey,
                .beginObjectValue = beginObjectValue,

                .endArray = endArray,
                .endArrayValue = endArrayValue,
                .endObject = endObject,
                .endObjectKey = endObjectKey,
                .endObjectValue = endObjectValue,
                .endString = endString,
            },
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

        fn writeCharEscape(_: *Self, writer: Writer, value: u21) Writer.Error!void {
            try escape.escapeChar(value, writer);
        }

        fn beginArray(self: *Self, writer: Writer) Writer.Error!void {
            self.current += 1;
            self.has_value = false;
            try writer.writeAll("[");
        }

        fn endArray(self: *Self, writer: Writer) Writer.Error!void {
            self.current -= 1;

            if (self.has_value) {
                try writer.writeAll("\n");
                try self.doIndent(writer);
            }

            try writer.writeAll("]");
        }

        fn beginArrayValue(self: *Self, writer: Writer, first: bool) Writer.Error!void {
            if (first) {
                try writer.writeAll("\n");
            } else {
                try writer.writeAll(",\n");
            }

            try self.doIndent(writer);
        }

        fn endArrayValue(self: *Self, _: Writer) Writer.Error!void {
            self.has_value = true;
        }

        fn beginObject(self: *Self, writer: Writer) Writer.Error!void {
            self.current += 1;
            self.has_value = false;
            try writer.writeAll("{");
        }

        fn endObject(self: *Self, writer: Writer) Writer.Error!void {
            self.current -= 1;

            if (self.has_value) {
                try writer.writeAll("\n");
                try self.doIndent(writer);
            }

            try writer.writeAll("}");
        }

        fn beginObjectKey(self: *Self, writer: Writer, first: bool) Writer.Error!void {
            if (first) {
                try writer.writeAll("\n");
            } else {
                try writer.writeAll(",\n");
            }

            try self.doIndent(writer);
        }

        fn endObjectKey(_: *Self, _: Writer) Writer.Error!void {}

        fn beginObjectValue(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll(": ");
        }

        fn endObjectValue(self: *Self, _: Writer) Writer.Error!void {
            self.has_value = true;
        }

        fn writeRawFragment(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
            try writer.writeAll(value);
        }
    };
}
