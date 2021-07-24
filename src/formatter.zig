const std = @import("std");

const format = @import("ser/format.zig");

const fmt = std.fmt;
const CharEscape = format.CharEscape;
const formatEscapedString = format.formatEscapedString;

pub fn Formatter(
    comptime Context: type,
    comptime Writer: type,
    comptime nullFn: fn (Context, Writer) Writer.Error!void,
    comptime boolFn: fn (Context, Writer, bool) Writer.Error!void,
    comptime intFn: fn (Context, Writer, anytype) Writer.Error!void,
    comptime floatFn: fn (Context, Writer, anytype) Writer.Error!void,
    comptime numberStringFn: fn (Context, Writer, []const u8) Writer.Error!void,
    comptime beginStringFn: fn (Context, Writer) Writer.Error!void,
    comptime endStringFn: fn (Context, Writer) Writer.Error!void,
    comptime stringFragmentFn: fn (Context, Writer, []const u8) Writer.Error!void,
    comptime charEscapeFn: fn (Context, Writer, CharEscape) Writer.Error!void,
    comptime beginArrayFn: fn (Context, Writer) Writer.Error!void,
    comptime endArrayFn: fn (Context, Writer) Writer.Error!void,
    comptime beginArrayValueFn: fn (Context, Writer, bool) Writer.Error!void,
    comptime endArrayValueFn: fn (Context, Writer) Writer.Error!void,
    comptime beginObjectFn: fn (Context, Writer) Writer.Error!void,
    comptime endObjectFn: fn (Context, Writer) Writer.Error!void,
    comptime beginObjectKeyFn: fn (Context, Writer, bool) Writer.Error!void,
    comptime endObjectKeyFn: fn (Context, Writer) Writer.Error!void,
    comptime beginObjectValueFn: fn (Context, Writer) Writer.Error!void,
    comptime endObjectValueFn: fn (Context, Writer) Writer.Error!void,
    comptime rawFragmentFn: fn (Context, Writer, []const u8) Writer.Error!void,
) type {
    return struct {
        context: Context,

        const Self = @This();

        /// Writes a `null` value to the specified writer.
        pub inline fn writeNull(self: Self, writer: Writer) Writer.Error!void {
            try nullFn(self.context, writer);
        }

        /// Writes `true` or `false` to the specified writer.
        pub inline fn writeBool(self: Self, writer: Writer, value: bool) Writer.Error!void {
            try boolFn(self.context, writer, value);
        }

        /// Writes an integer value to the specified writer.
        pub inline fn writeInt(self: Self, writer: Writer, value: anytype) Writer.Error!void {
            switch (@typeInfo(@TypeOf(value))) {
                .ComptimeInt, .Int => try intFn(self.context, writer, value),
                else => @compileError("expected integer, found " ++ @typeName(@TypeOf(value))),
            }
        }

        // Writes an floating point value to the specified writer.
        pub inline fn writeFloat(self: Self, writer: Writer, value: anytype) Writer.Error!void {
            switch (@typeInfo(@TypeOf(value))) {
                .ComptimeFloat, .Float => try floatFn(self.context, writer, value),
                else => @compileError("expected floating point, found " ++ @typeName(@TypeOf(value))),
            }
        }

        /// Writes a number that has already been rendered into a string.
        ///
        /// TODO: Check that the string is actually an integer when parsed.
        pub inline fn writeNumberString(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try numberStringFn(self.context, writer, value);
        }

        /// Called before each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub inline fn beginString(self: Self, writer: Writer) Writer.Error!void {
            try beginStringFn(self.context, writer);
        }

        /// Called after each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub inline fn endString(self: Self, writer: Writer) Writer.Error!void {
            try endStringFn(self.context, writer);
        }

        /// Writes a string fragment that doesn't need any escaping to the
        /// specified writer.
        pub inline fn writeStringFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try stringFragmentFn(self.context, writer, value);
        }

        pub inline fn writeCharEscape(self: Self, writer: Writer, value: CharEscape) Writer.Error!void {
            try charEscapeFn(self.context, writer, value);
        }

        pub inline fn beginArray(self: Self, writer: Writer) Writer.Error!void {
            try beginArrayFn(self.context, writer);
        }

        pub inline fn endArray(self: Self, writer: Writer) Writer.Error!void {
            try endArrayFn(self.context, writer);
        }

        pub inline fn beginArrayValue(self: Self, writer: Writer, first: bool) Writer.Error!void {
            try beginArrayValueFn(self.context, writer, first);
        }

        pub inline fn endArrayValue(self: Self, writer: Writer) Writer.Error!void {
            try endArrayValueFn(self.context, writer);
        }

        pub inline fn beginObject(self: Self, writer: Writer) Writer.Error!void {
            try beginObjectFn(self.context, writer);
        }

        pub inline fn endObject(self: Self, writer: Writer) Writer.Error!void {
            try endObjectFn(self.context, writer);
        }

        pub inline fn beginObjectKey(self: Self, writer: Writer, first: bool) Writer.Error!void {
            try beginObjectKeyFn(self.context, writer, first);
        }

        pub inline fn endObjectKey(self: Self, writer: Writer) Writer.Error!void {
            try endObjectKeyFn(self.context, writer);
        }

        pub inline fn beginObjectValue(self: Self, writer: Writer) Writer.Error!void {
            try beginObjectValueFn(self.context, writer, first);
        }

        pub inline fn endObjectValue(self: Self, writer: Writer) Writer.Error!void {
            try endObjectValueFn(self.context, writer);
        }

        pub inline fn writeRawFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try rawFragmentFn(self.context, writer, value);
        }
    };
}

pub fn CompactFormatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub const F = Formatter(
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

        pub fn formatter(self: *Self) F {
            return .{ .context = self };
        }

        const _F = struct {
            fn writeNull(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("null");
            }

            fn writeBool(_: *Self, writer: Writer, value: bool) Writer.Error!void {
                try writer.writeAll(if (value) "true" else "false");
            }

            fn writeInt(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                var buf: [100]u8 = undefined;
                try writer.writeAll(fmt.bufPrintIntToSlice(&buf, value, 10, .lower, .{}));
            }

            fn writeFloat(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                // this should be enough to display all decimal places of a decimal f64 number.
                var buf: [512]u8 = undefined;
                var stream = std.io.fixedBufferStream(&buf);

                fmt.formatFloatDecimal(value, fmt.FormatOptions{}, stream.writer()) catch |err| switch (err) {
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
            fn writeCharEscape(_: *Self, writer: Writer, value: CharEscape) Writer.Error!void {
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

        pub const F = Formatter(
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

        pub fn formatter(self: *Self) F {
            return .{ .context = self };
        }

        const _F = struct {
            fn writeNull(_: *Self, writer: Writer) Writer.Error!void {
                try writer.writeAll("null");
            }

            fn writeBool(_: *Self, writer: Writer, value: bool) Writer.Error!void {
                try writer.writeAll(if (value) "true" else "false");
            }

            fn writeInt(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                var buf: [100]u8 = undefined;
                try writer.writeAll(fmt.bufPrintIntToSlice(&buf, value, 10, .lower, .{}));
            }

            fn writeFloat(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
                var buf: [512]u8 = undefined;
                var stream = std.io.fixedBufferStream(&buf);

                fmt.formatFloatDecimal(value, fmt.FormatOptions{}, stream.writer()) catch |err| switch (err) {
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
            fn writeCharEscape(_: *Self, writer: Writer, value: CharEscape) Writer.Error!void {
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

            fn endArrayValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = writer;

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

            fn endObjectKey(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;
                _ = writer;
            }

            fn beginObjectValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = self;

                try writer.writeAll(": ");
            }

            fn endObjectValue(self: *Self, writer: Writer) Writer.Error!void {
                _ = writer;

                self.has_value = true;
            }

            fn writeRawFragment(self: *Self, writer: Writer, value: []const u8) Writer.Error!void {
                _ = self;

                try writer.writeAll(value);
            }
        };
    };
}

test "formatter" {
    var stdout = std.io.getStdOut();
    const writer = stdout.writer();

    var compact_formatter = PrettyFormatter(@TypeOf(writer)).init();
    const formatter = compact_formatter.formatter();

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");

    try formatter.writeBool(writer, false);

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");

    try formatter.writeInt(writer, 12345);

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");

    try formatter.writeFloat(writer, 3.1415);

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");

    try formatter.writeNull(writer);

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");

    try formatter.beginArray(writer);
    try formatter.beginArrayValue(writer, true);
    try formatter.writeBool(writer, true);
    try formatter.endArrayValue(writer);
    try formatter.beginArrayValue(writer, false);
    try formatter.writeBool(writer, false);
    try formatter.endArrayValue(writer);
    try formatter.endArray(writer);

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
}
