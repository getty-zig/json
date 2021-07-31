const formatter = @import("../formatter.zig");
const std = @import("std");

pub fn Formatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub fn interface(self: *Self, comptime name: []const u8) blk: {
            if (std.mem.eql(u8, name, "formatter")) {
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
            } else {
                @compileError("Unknown interface name");
            }
        } {
            return .{ .context = self };
        }

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
