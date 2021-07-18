const getty = @import("getty");
const std = @import("std");

pub fn Serializer(comptime W: type, comptime F: type) type {
    return struct {
        writer: W,
        formatter: F,

        _written: usize = 0,

        const Self = @This();

        pub fn init(writer: anytype, formatter: anytype) Self {
            return .{
                .writer = writer,
                .formatter = formatter,
            };
        }

        /// Implements `getty.ser.Serializer`.
        pub const S = getty.ser.Serializer(
            *Self,
            Ok,
            Error,
            //Map,
            Sequence,
            Struct,
            //Tuple,
            serializeBool,
            serializeFloat,
            serializeInt,
            serializeNull,
            serializeSequence,
            serializeString,
            serializeStruct,
            serializeVariant,
        );

        pub const Ok = void;
        pub const Error = error{
            /// Failure to read or write bytes on an IO stream.
            Io,

            /// Input was not syntactically valid JSON.
            Syntax,

            /// Input data was semantically incorrect.
            ///
            /// For example, JSON containing a number is semantically incorrect
            /// when the type being deserialized into holds a String.
            Data,

            /// Prematurely reached the end of the input data.
            ///
            /// Callers that process streaming input may be interested in
            /// retrying the deserialization once more data is available.
            Eof,
        };

        //pub const Map = SM;
        pub const Sequence = SI;
        pub const Struct = SS;
        //pub const Tuple = ST;

        pub fn getSerializer(self: *Self) S {
            return .{ .context = self };
        }

        /// Implements `boolFn` for `getty.ser.Serializer`.
        pub fn serializeBool(self: *Self, value: bool) Error!Ok {
            self.writer.writeAll(if (value) "true" else "false") catch return Error.Io;
        }

        /// Implements `floatFn` for `getty.ser.Serializer`.
        pub fn serializeFloat(self: *Self, value: anytype) Error!Ok {
            std.json.stringify(value, .{}, self.writer) catch return Error.Io;
        }

        /// Implements `intFn` for `getty.ser.Serializer`.
        pub fn serializeInt(self: *Self, value: anytype) Error!Ok {
            var buffer: [20]u8 = undefined;
            const number = std.fmt.bufPrint(&buffer, "{}", .{value}) catch unreachable;
            self.writer.writeAll(number) catch return Error.Io;
        }

        /// Implements `nullFn` for `getty.ser.Serializer`.
        pub fn serializeNull(self: *Self) Error!Ok {
            self.writer.writeAll("null") catch return Error.Io;
        }

        /// Implements `sequenceFn` for `getty.ser.Serializer`.
        pub fn serializeSequence(self: *Self) Error!Sequence {
            self.writer.writeByte('[') catch return Error.Io;

            return self.getSequence();
        }

        /// Implements `stringFn` for `getty.ser.Serializer`.
        pub fn serializeString(self: *Self, value: anytype) Error!Ok {
            self.writer.writeByte('"') catch return Error.Io;
            self.writer.writeAll(value) catch return Error.Io;
            self.writer.writeByte('"') catch return Error.Io;
        }

        /// Implements `structFn` for `getty.ser.Serializer`.
        pub fn serializeStruct(self: *Self) Error!Struct {
            self.writer.writeByte('{') catch return Error.Io;

            return self.getStruct();
        }

        /// Implements `variantFn` for `getty.ser.Serializer`.
        pub fn serializeVariant(self: *Self, value: anytype) Error!Ok {
            self.serializeString(@tagName(value)) catch return Error.Io;
        }

        /// Implements `getty.ser.SerializeSequence`.
        pub const SI = getty.ser.SerializeSequence(
            *Self,
            Ok,
            Error,
            serializeElement,
            seqEnd,
        );

        pub fn getSequence(self: *Self) SI {
            return .{ .context = self };
        }

        /// Implements `elementFn` for `getty.ser.SerializeSequence`.
        ///
        /// FIXME: Pretty sure the _written usage is wrong for elements and
        /// fields.
        pub fn serializeElement(self: *Self, value: anytype) Error!void {
            if (self._written > 0) {
                self.writer.writeByte(',') catch return Error.Io;
            }

            self._written += 1;

            getty.ser.serialize(self, value) catch return Error.Io;
        }

        /// Implements `endFn` for `getty.ser.SerializeSequence`.
        pub fn seqEnd(self: *Self) Error!Ok {
            self.writer.writeByte(']') catch return Error.Io;
        }

        /// Implements `getty.ser.SerializeStruct`.
        pub const SS = getty.ser.SerializeStruct(
            *Self,
            Ok,
            Error,
            serializeField,
            structEnd,
        );

        pub fn getStruct(self: *Self) SS {
            return .{ .context = self };
        }

        /// Implements `fieldFn` for `getty.ser.SerializeStruct`.
        pub fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Error!void {
            if (self._written > 0) {
                self.writer.writeByte(',') catch return Error.Io;
            }

            self._written += 1;

            getty.ser.serialize(self, key) catch return Error.Io;
            self.writer.writeByte(':') catch return Error.Io;
            getty.ser.serialize(self, value) catch return Error.Io;
        }

        /// Implements `endFn` for `getty.ser.SerializeStruct`.
        pub fn structEnd(self: *Self) Error!Ok {
            self.writer.writeByte('}') catch return Error.Io;
        }
    };
}

pub fn formattedSerializer(writer: anytype, formatter: anytype) Serializer(@TypeOf(writer), @TypeOf(formatter)) {
    return Serializer(@TypeOf(writer), @TypeOf(formatter)).init(writer, formatter);
}

pub fn serializer(writer: anytype) Serializer(@TypeOf(writer), CompactFormatter(@TypeOf(writer))) {
    return formattedSerializer(writer, CompactFormatter(@TypeOf(writer)){});
}

/// Serializes a value using the JSON serializer into a provided writer.
pub fn toWriter(writer: anytype, value: anytype) !void {
    var s = serializer(writer);
    try getty.ser.serialize(&s, value);
}

/// Returns an owned slice of a serialized JSON string.
///
/// The caller is responsible for freeing the returned memory.
pub fn toString(allocator: *std.mem.Allocator, value: anytype) ![]const u8 {
    var array_list = std.ArrayList(u8).init(allocator);
    errdefer array_list.deinit();

    try toWriter(array_list.writer(), value);
    return array_list.toOwnedSlice();
}

pub fn CompactFormatter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        pub const F = Formatter(
            *Self,
            Writer,
            writeBool,
            writeInt,
            writeFloat,
            writeNull,
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

        pub fn formatter(self: *Self) F {
            return .{ .context = self };
        }

        pub fn writeBool(_: *Self, writer: Writer, value: bool) Writer.Error!void {
            try writer.writeAll(if (value) "true" else "false");
        }

        pub fn writeInt(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
            var buf: [100]u8 = undefined;
            try writer.writeAll(std.fmt.bufPrintIntToSlice(&buf, value, 10, .lower, .{}));
        }

        pub fn writeFloat(_: *Self, writer: Writer, value: anytype) Writer.Error!void {
            // this should be enough to display all decimal places of a decimal f64 number.
            var buf: [512]u8 = undefined;
            var buf_stream = std.io.fixedBufferStream(&buf);

            std.fmt.formatFloatDecimal(value, std.fmt.FormatOptions{}, buf_stream.writer()) catch |err| switch (err) {
                error.NoSpaceLeft => unreachable,
                else => unreachable, // TODO: handle error
            };

            try writer.writeAll(&buf);
        }

        pub fn writeNull(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("null");
        }

        pub fn writeNumberString(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
            try writer.writeAll(value);
        }

        pub fn beginString(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("\"");
        }

        pub fn endString(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("\"");
        }

        pub fn writeStringFragment(_: *Self, writer: Writer, value: []const u8) Writer.Error!void {
            try writer.writeAll(value);
        }

        pub fn writeCharEscape(_: *Self, writer: Writer, value: CharEscape) Writer.Error!void {
            const s = switch (value) {
                .Quote => "\\\"",
                .ReverseSolidus => "\\\\",
                .Solidus => "\\/",
                .Backspace => "\\",
                .FormFeed => "\\f",
                .LineFeed => "\\n",
                .CarriageReturn => "\\r",
                .Tab => "\\t",
                //.AsciiControl
            };

            try writer.writeAll(s);
        }

        pub fn beginArray(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("[");
        }

        pub fn endArray(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("]");
        }

        pub fn beginArrayValue(_: *Self, writer: Writer, first: bool) Writer.Error!void {
            if (!first)
                try writer.writeAll(",");
        }

        pub fn endArrayValue(self: *Self, writer: Writer) Writer.Error!void {
            _ = self;
            _ = writer;
        }

        pub fn beginObject(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("{");
        }

        pub fn endObject(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll("}");
        }

        pub fn beginObjectKey(_: *Self, writer: Writer, first: bool) Writer.Error!void {
            if (!first)
                try writer.writeAll(",");
        }

        pub fn endObjectKey(self: *Self, writer: Writer) Writer.Error!void {
            _ = self;
            _ = writer;
        }

        pub fn beginObjectValue(_: *Self, writer: Writer) Writer.Error!void {
            try writer.writeAll(":");
        }

        pub fn endObjectValue(self: *Self, writer: Writer) Writer.Error!void {
            _ = self;
            _ = writer;
        }

        pub fn writeRawFragment(self: *Self, writer: Writer, value: []const u8) Writer.Error!void {
            _ = self;

            try writer.writeAll(value);
        }
    };
}

//pub const PrettyFormatter = struct {};

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

pub const CharEscape = enum(u8) {
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

    // An escaped ASCII plane control character (usually escaped as `\u00XX`
    // where `XX` are two hex characters)
    //
    // TODO
    //AsciiControl,

    pub inline fn fromEscapeTable(escape: u8, byte: u8) @This() {
        _ = byte;

        return switch (escape) {
            BB => .Backspace,
            TT => .Tab,
            NN => .LineFeed,
            FF => .FormFeed,
            RR => .CarriageReturn,
            QU => .Quote,
            BS => .ReverseSolidus,
            //UU => .AsciiControl(byte),
            else => unreachable,
        };
    }
};

pub fn Formatter(
    comptime Context: type,
    comptime Writer: type,
    comptime boolFn: fn (Context, Writer, bool) Writer.Error!void,
    comptime intFn: fn (Context, Writer, anytype) Writer.Error!void,
    comptime floatFn: fn (Context, Writer, anytype) Writer.Error!void,
    comptime nullFn: fn (Context, Writer) Writer.Error!void,
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

        /// Writes a `null` value to the specified writer.
        pub inline fn writeNull(self: Self, writer: Writer) Writer.Error!void {
            try nullFn(self.context, writer);
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

test "formatter" {
    var stdout = std.io.getStdOut();
    const writer = stdout.writer();

    var compact_formatter = CompactFormatter(@TypeOf(writer)){};
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

    try formatter.beginString(writer);
    try formatter.writeBool(writer, true);
    try formatter.endString(writer);

    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
    try formatter.writeNumberString(writer, "\n");
}

test "toWriter - Array" {
    try t([_]i8{ 1, 2, 3 }, "[1,2,3]");
}

test "toWriter - Bool" {
    try t(true, "true");
    try t(false, "false");
}

test "toWriter - Enum" {
    try t(enum { Foo }.Foo, "\"Foo\"");
    try t(.Foo, "\"Foo\"");
}

test "toWriter - Integer" {
    try t('A', "65");
    try t(std.math.maxInt(u32), "4294967295");
    try t(std.math.maxInt(u64), "18446744073709551615");
    try t(std.math.minInt(i32), "-2147483648");
    try t(std.math.maxInt(i64), "9223372036854775807");
}

test "toWriter - Null" {
    try t(null, "null");
}

test "toWriter - String" {
    try t("Foobar", "\"Foobar\"");
}

test "toWriter - Struct" {
    const Point = struct { x: i32, y: i32 };
    const point = Point{ .x = 1, .y = 2 };

    try t(point, "{\"x\":1,\"y\":2}");
}

fn t(input: anytype, output: []const u8) !void {
    var array_list = std.ArrayList(u8).init(std.testing.allocator);
    defer array_list.deinit();

    try toWriter(array_list.writer(), input);
    try std.testing.expectEqualSlices(u8, array_list.items, output);
}

comptime {
    std.testing.refAllDecls(@This());
}
