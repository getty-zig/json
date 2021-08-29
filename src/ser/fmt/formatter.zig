const CharEscape = @import("../../lib.zig").CharEscape;

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
        pub fn writeNull(self: Self, writer: Writer) Writer.Error!void {
            try nullFn(self.context, writer);
        }

        /// Writes `true` or `false` to the specified writer.
        pub fn writeBool(self: Self, writer: Writer, value: bool) Writer.Error!void {
            try boolFn(self.context, writer, value);
        }

        /// Writes an integer value to the specified writer.
        pub fn writeInt(self: Self, writer: Writer, value: anytype) Writer.Error!void {
            switch (@typeInfo(@TypeOf(value))) {
                .ComptimeInt, .Int => try intFn(self.context, writer, value),
                else => @compileError("expected integer, found " ++ @typeName(@TypeOf(value))),
            }
        }

        // Writes an floating point value to the specified writer.
        pub fn writeFloat(self: Self, writer: Writer, value: anytype) Writer.Error!void {
            switch (@typeInfo(@TypeOf(value))) {
                .ComptimeFloat, .Float => try floatFn(self.context, writer, value),
                else => @compileError("expected floating point, found " ++ @typeName(@TypeOf(value))),
            }
        }

        /// Writes a number that has already been rendered into a string.
        ///
        /// TODO: Check that the string is actually an integer when parsed.
        pub fn writeNumberString(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try numberStringFn(self.context, writer, value);
        }

        /// Called before each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub fn beginString(self: Self, writer: Writer) Writer.Error!void {
            try beginStringFn(self.context, writer);
        }

        /// Called after each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub fn endString(self: Self, writer: Writer) Writer.Error!void {
            try endStringFn(self.context, writer);
        }

        /// Writes a string fragment that doesn't need any escaping to the
        /// specified writer.
        pub fn writeStringFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try stringFragmentFn(self.context, writer, value);
        }

        pub fn writeCharEscape(self: Self, writer: Writer, value: CharEscape) Writer.Error!void {
            try charEscapeFn(self.context, writer, value);
        }

        pub fn beginArray(self: Self, writer: Writer) Writer.Error!void {
            try beginArrayFn(self.context, writer);
        }

        pub fn endArray(self: Self, writer: Writer) Writer.Error!void {
            try endArrayFn(self.context, writer);
        }

        pub fn beginArrayValue(self: Self, writer: Writer, first: bool) Writer.Error!void {
            try beginArrayValueFn(self.context, writer, first);
        }

        pub fn endArrayValue(self: Self, writer: Writer) Writer.Error!void {
            try endArrayValueFn(self.context, writer);
        }

        pub fn beginObject(self: Self, writer: Writer) Writer.Error!void {
            try beginObjectFn(self.context, writer);
        }

        pub fn endObject(self: Self, writer: Writer) Writer.Error!void {
            try endObjectFn(self.context, writer);
        }

        pub fn beginObjectKey(self: Self, writer: Writer, first: bool) Writer.Error!void {
            try beginObjectKeyFn(self.context, writer, first);
        }

        pub fn endObjectKey(self: Self, writer: Writer) Writer.Error!void {
            try endObjectKeyFn(self.context, writer);
        }

        pub fn beginObjectValue(self: Self, writer: Writer) Writer.Error!void {
            try beginObjectValueFn(self.context, writer);
        }

        pub fn endObjectValue(self: Self, writer: Writer) Writer.Error!void {
            try endObjectValueFn(self.context, writer);
        }

        pub fn writeRawFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try rawFragmentFn(self.context, writer, value);
        }
    };
}
