const escape = @import("details/escape.zig");
const std = @import("std");

const FormatterInterface = @import("../../../json.zig").ser.Formatter;

pub fn Formatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub usingnamespace FormatterInterface(
            Self,
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
        fn writeNull(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("null");
        }

        fn writeBool(_: Self, w: Writer, v: bool) Writer.Error!void {
            try w.writeAll(if (v) "true" else "false");
        }

        fn writeInt(_: Self, w: Writer, v: anytype) Writer.Error!void {
            try std.fmt.formatInt(v, 10, .lower, .{}, w);
        }

        fn writeFloat(_: Self, w: Writer, v: anytype) Writer.Error!void {
            try std.fmt.formatFloatScientific(v, std.fmt.FormatOptions{}, w);
        }

        fn writeNumberString(_: Self, w: Writer, v: []const u8) Writer.Error!void {
            try w.writeAll(v);
        }

        fn beginString(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("\"");
        }

        fn endString(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("\"");
        }

        fn writeStringFragment(_: Self, w: Writer, v: []const u8) Writer.Error!void {
            try w.writeAll(v);
        }

        fn writeCharEscape(_: Self, w: Writer, v: u21) Writer.Error!void {
            try escape.escapeChar(v, w);
        }

        fn beginArray(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("[");
        }

        fn endArray(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("]");
        }

        fn beginArrayValue(_: Self, w: Writer, first: bool) Writer.Error!void {
            if (!first)
                try w.writeAll(",");
        }

        fn endArrayValue(_: Self, _: Writer) Writer.Error!void {}

        fn beginObject(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("{");
        }

        fn endObject(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll("}");
        }

        fn beginObjectKey(_: Self, w: Writer, first: bool) Writer.Error!void {
            if (!first)
                try w.writeAll(",");
        }

        fn endObjectKey(_: Self, _: Writer) Writer.Error!void {}

        fn beginObjectValue(_: Self, w: Writer) Writer.Error!void {
            try w.writeAll(":");
        }

        fn endObjectValue(_: Self, _: Writer) Writer.Error!void {}

        fn writeRawFragment(_: Self, w: Writer, v: []const u8) Writer.Error!void {
            try w.writeAll(v);
        }
    };
}
