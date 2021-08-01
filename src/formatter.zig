const std = @import("std");

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
            try beginObjectValueFn(self.context, writer);
        }

        pub inline fn endObjectValue(self: Self, writer: Writer) Writer.Error!void {
            try endObjectValueFn(self.context, writer);
        }

        pub inline fn writeRawFragment(self: Self, writer: Writer, value: []const u8) Writer.Error!void {
            try rawFragmentFn(self.context, writer, value);
        }
    };
}

const BB: u8 = 'b'; // \x08
const TT: u8 = 't'; // \x09
const NN: u8 = 'n'; // \x0A
const FF: u8 = 'f'; // \x0C
const RR: u8 = 'r'; // \x0D
const QU: u8 = '"'; // \x22
const BS: u8 = '\\'; // \x5C
const UU: u8 = 'u'; // \x00...\x1F except the ones above
const __: u8 = 0;

// Lookup table of escape sequences. A value of b'x' at index i means that byte
// i is escaped as "\x" in JSON. A value of 0 means that byte i is not escaped.
const ESCAPE = [256]u8{
    //   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
    UU, UU, UU, UU, UU, UU, UU, UU, BB, TT, NN, UU, FF, RR, UU, UU, // 0
    UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, // 1
    __, __, QU, __, __, __, __, __, __, __, __, __, __, __, __, __, // 2
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 3
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 4
    __, __, __, __, __, __, __, __, __, __, __, __, BS, __, __, __, // 5
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 6
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 7
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 8
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 9
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // A
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // B
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // C
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // D
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // E
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // F
};

pub const CharEscape = union(enum) {
    // An escaped ASCII plane control character (usually escaped as `\u00XX`
    // where `XX` are two hex characters)
    ascii: u8,

    non_ascii: enum(u8) {
        /// An escaped quote `"`
        Quote,

        /// An escaped reverse solidus `\`
        ReverseSolidus,

        /// An escaped solidus `/`
        Solidus,

        /// An escaped backspace character (usually escaped as `\b`)
        Backspace,

        /// An escaped form feed character (usually escaped as `\f`)
        FormFeed,

        /// An escaped line feed character (usually escaped as `\n`)
        LineFeed,

        /// An escaped carriage return character (usually escaped as `\r`)
        CarriageReturn,

        /// An escaped tab character (usually escaped as `\t`)
        Tab,
    },

    fn fromEscapeTable(escape: u8, byte: u8) @This() {
        switch (escape) {
            BB => return .{ .non_ascii = .Backspace },
            TT => return .{ .non_ascii = .Tab },
            NN => return .{ .non_ascii = .LineFeed },
            FF => return .{ .non_ascii = .FormFeed },
            RR => return .{ .non_ascii = .CarriageReturn },
            QU => return .{ .non_ascii = .Quote },
            BS => return .{ .non_ascii = .ReverseSolidus },
            UU => return .{ .ascii = byte },
            else => unreachable,
        }
    }
};

pub fn formatEscapedString(writer: anytype, formatter: anytype, bytes: []const u8) !void {
    var start: usize = 0;

    for (bytes) |byte, i| {
        // TODO: Does byte need to be casted?
        const escape = ESCAPE[@as(usize, byte)];

        if (escape == 0) {
            continue;
        }

        if (start < i) {
            try formatter.writeStringFragment(writer, bytes[start..i]);
        }

        const char_escape = CharEscape.fromEscapeTable(escape, byte);
        try formatter.writeCharEscape(writer, char_escape);

        start = i + 1;
    }

    if (start != bytes.len) {
        try formatter.writeStringFragment(writer, bytes[start..]);
    }
}

const PrettyFormatter = @import("formatters/pretty.zig").Formatter;

test "formatter" {
    var stdout = std.io.getStdOut();
    const writer = stdout.writer();

    var pretty_formatter = PrettyFormatter(@TypeOf(writer)).init();
    const formatter = pretty_formatter.interface(.Formatter);

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
