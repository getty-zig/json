const escape = @import("details/escape.zig");
const std = @import("std");

const FormatterInterface = @import("../../../json.zig").ser.Formatter;

pub fn Formatter(comptime Writer: type) type {
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
            for (0..self.current) |_| {
                try writer.writeAll(self.indent);
            }
        }

        pub usingnamespace FormatterInterface(
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
            try std.fmt.formatInt(value, 10, .lower, .{}, writer);
        }

        fn writeFloat(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
            try std.fmt.formatFloatScientific(value, std.fmt.FormatOptions{}, writer);
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
