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

        fn doIndent(self: *Self, w: anytype) Writer.Error!void {
            for (0..self.current) |_| {
                try w.writeAll(self.indent);
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

        fn writeNull(_: *Self, w: Writer) Writer.Error!void {
            try w.writeAll("null");
        }

        fn writeBool(_: *Self, w: Writer, v: bool) Writer.Error!void {
            try w.writeAll(if (v) "true" else "false");
        }

        fn writeInt(_: *Self, w: Writer, v: anytype) Writer.Error!void {
            try std.fmt.formatInt(v, 10, .lower, .{}, w);
        }

        fn writeFloat(_: *Self, w: Writer, v: anytype) Writer.Error!void {
            try std.fmt.formatFloatScientific(v, std.fmt.FormatOptions{}, w);
        }

        fn writeNumberString(_: *Self, w: Writer, v: []const u8) Writer.Error!void {
            try w.writeAll(v);
        }

        fn beginString(_: *Self, w: Writer) Writer.Error!void {
            try w.writeAll("\"");
        }

        fn endString(_: *Self, w: Writer) Writer.Error!void {
            try w.writeAll("\"");
        }

        fn writeStringFragment(_: *Self, w: Writer, v: []const u8) Writer.Error!void {
            try w.writeAll(v);
        }

        fn writeCharEscape(_: *Self, w: Writer, v: u21) Writer.Error!void {
            try escape.escapeChar(v, w);
        }

        fn beginArray(self: *Self, w: Writer) Writer.Error!void {
            self.current += 1;
            self.has_value = false;
            try w.writeAll("[");
        }

        fn endArray(self: *Self, w: Writer) Writer.Error!void {
            self.current -= 1;

            if (self.has_value) {
                try w.writeAll("\n");
                try self.doIndent(w);
            }

            try w.writeAll("]");
        }

        fn beginArrayValue(self: *Self, w: Writer, first: bool) Writer.Error!void {
            if (first) {
                try w.writeAll("\n");
            } else {
                try w.writeAll(",\n");
            }

            try self.doIndent(w);
        }

        fn endArrayValue(self: *Self, _: Writer) Writer.Error!void {
            self.has_value = true;
        }

        fn beginObject(self: *Self, w: Writer) Writer.Error!void {
            self.current += 1;
            self.has_value = false;
            try w.writeAll("{");
        }

        fn endObject(self: *Self, w: Writer) Writer.Error!void {
            self.current -= 1;

            if (self.has_value) {
                try w.writeAll("\n");
                try self.doIndent(w);
            }

            try w.writeAll("}");
        }

        fn beginObjectKey(self: *Self, w: Writer, first: bool) Writer.Error!void {
            if (first) {
                try w.writeAll("\n");
            } else {
                try w.writeAll(",\n");
            }

            try self.doIndent(w);
        }

        fn endObjectKey(_: *Self, _: Writer) Writer.Error!void {}

        fn beginObjectValue(_: *Self, w: Writer) Writer.Error!void {
            try w.writeAll(": ");
        }

        fn endObjectValue(self: *Self, _: Writer) Writer.Error!void {
            self.has_value = true;
        }

        fn writeRawFragment(_: *Self, w: Writer, v: []const u8) Writer.Error!void {
            try w.writeAll(v);
        }
    };
}
