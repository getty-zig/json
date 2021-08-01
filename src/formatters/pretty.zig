const formatter = @import("../formatter.zig");
const std = @import("std");

pub fn Formatter(comptime Writer: type) type {
    return struct {
        current: usize,
        has_value: bool,
        indent: []const u8,

        const Self = @This();

        const Interface = enum {
            Formatter,
        };

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

        pub fn interface(self: *Self, comptime iface: Interface) switch (iface) {
            .Formatter => blk: {
                const _Formatter = struct {
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

                    fn beginArray(f: *Self, writer: Writer) Writer.Error!void {
                        f.current += 1;
                        f.has_value = false;
                        try writer.writeAll("[");
                    }

                    fn endArray(f: *Self, writer: Writer) Writer.Error!void {
                        f.current -= 1;

                        if (f.has_value) {
                            try writer.writeAll("\n");
                            try f.doIndent(writer);
                        }

                        try writer.writeAll("]");
                    }

                    fn beginArrayValue(f: *Self, writer: Writer, first: bool) Writer.Error!void {
                        if (first) {
                            try writer.writeAll("\n");
                        } else {
                            try writer.writeAll(",\n");
                        }

                        try f.doIndent(writer);
                    }

                    fn endArrayValue(f: *Self, writer: Writer) Writer.Error!void {
                        _ = writer;

                        f.has_value = true;
                    }

                    fn beginObject(f: *Self, writer: Writer) Writer.Error!void {
                        f.current += 1;
                        f.has_value = false;
                        try writer.writeAll("{");
                    }

                    fn endObject(f: *Self, writer: Writer) Writer.Error!void {
                        f.current -= 1;

                        if (f.has_value) {
                            try writer.writeAll("\n");
                            try f.doIndent(writer);
                        }

                        try writer.writeAll("}");
                    }

                    fn beginObjectKey(f: *Self, writer: Writer, first: bool) Writer.Error!void {
                        if (first) {
                            try writer.writeAll("\n");
                        } else {
                            try writer.writeAll(",\n");
                        }

                        try f.doIndent(writer);
                    }

                    fn endObjectKey(f: *Self, writer: Writer) Writer.Error!void {
                        _ = f;
                        _ = writer;
                    }

                    fn beginObjectValue(f: *Self, writer: Writer) Writer.Error!void {
                        _ = f;

                        try writer.writeAll(": ");
                    }

                    fn endObjectValue(f: *Self, writer: Writer) Writer.Error!void {
                        _ = writer;

                        f.has_value = true;
                    }

                    fn writeRawFragment(f: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                        _ = f;

                        try writer.writeAll(value);
                    }
                };
                break :blk formatter.Formatter(
                    *Self,
                    Writer,
                    _Formatter.writeNull,
                    _Formatter.writeBool,
                    _Formatter.writeInt,
                    _Formatter.writeFloat,
                    _Formatter.writeNumberString,
                    _Formatter.beginString,
                    _Formatter.endString,
                    _Formatter.writeStringFragment,
                    _Formatter.writeCharEscape,
                    _Formatter.beginArray,
                    _Formatter.endArray,
                    _Formatter.beginArrayValue,
                    _Formatter.endArrayValue,
                    _Formatter.beginObject,
                    _Formatter.endObject,
                    _Formatter.beginObjectKey,
                    _Formatter.endObjectKey,
                    _Formatter.beginObjectValue,
                    _Formatter.endObjectValue,
                    _Formatter.writeRawFragment,
                );
            },
        } {
            return .{ .context = self };
        }
    };
}
