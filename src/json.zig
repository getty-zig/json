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

        /// Implements `json.Formatter`.
        pub const F = Formatter(
            *Self,
            Writer,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
        );

        pub fn formatter(self: *Self) F {
            return .{ .context = self };
        }

        pub const Error = error{};
    };
}

pub const PrettyFormatter = struct {};

pub fn Formatter(
    comptime Context: type,
    comptime W: type,
    comptime boolFn: ?fn (context: Context, writer: W, value: bool) W.Error!void,
    comptime intFn: ?fn (context: Context, writer: W, value: anytype) W.Error!void,
    comptime floatFn: ?fn (context: Context, writer: W, value: anytype) W.Error!void,
    comptime nullFn: ?fn (context: Context, writer: W) W.Error!void,
    comptime numberStringFn: ?fn (context: Context, writer: W, value: []const u8) W.Error!void,
    comptime beginStringFn: ?fn (context: Context, writer: W) W.Error!void,
    comptime endStringFn: ?fn (context: Context, writer: W) W.Error!void,
) type {
    return struct {
        context: Context,

        const Self = @This();

        /// Writes `true` or `false` to the specified writer.
        pub inline fn writeBool(self: Self, writer: W, value: bool) W.Error!void {
            if (boolFn) |f| {
                try f(self.context, writer, value);
            } else {
                writer.writeAll(if (value) "true" else "false") catch unreachable;
            }
        }

        // Writes an integer value to the specified writer.
        pub inline fn writeInt(self: Self, writer: W, value: anytype) W.Error!void {
            switch (@typeInfo(@TypeOf(value))) {
                .ComptimeInt, .Int => {
                    if (intFn) |f| {
                        try f(self.context, writer, value);
                    } else {
                        var buf: [100]u8 = undefined;
                        writer.writeAll(std.fmt.bufPrintIntToSlice(&buf, value, 10, .lower, .{})) catch unreachable;
                    }
                },
                else => @compileError("expected integer, found " ++ @typeName(@TypeOf(value))),
            }
        }

        // Writes an floating point value to the specified writer.
        pub inline fn writeFloat(self: Self, writer: W, value: anytype) W.Error!void {
            switch (@typeInfo(@TypeOf(value))) {
                .ComptimeFloat, .Float => {
                    if (floatFn) |f| {
                        try f(self.context, writer, value);
                    } else {
                        // this should be enough to display all decimal places of a decimal f64 number.
                        var buf: [512]u8 = undefined;
                        var buf_stream = std.io.fixedBufferStream(&buf);

                        std.fmt.formatFloatDecimal(value, std.fmt.FormatOptions{}, buf_stream.writer()) catch |err| switch (err) {
                            error.NoSpaceLeft => unreachable,
                            else => unreachable, // TODO: handle error
                        };

                        writer.writeAll(&buf) catch unreachable;
                    }
                },
                else => @compileError("expected floating point, found " ++ @typeName(@TypeOf(value))),
            }
        }

        /// Writes a `null` value to the specified writer.
        pub inline fn writeNull(self: Self, writer: W) W.Error!void {
            if (nullFn) |f| {
                try f(self.context, writer);
            } else {
                writer.writeAll("null") catch unreachable;
            }
        }

        /// Writes a number that has already been rendered into a string.
        pub inline fn writeNumberString(self: Self, writer: W, value: []const u8) W.Error!void {
            // TODO: Check that the string is actually an integer when parsed.
            if (numberStringFn) |f| {
                try f(self.context, writer, value);
            } else {
                writer.writeAll(value) catch unreachable;
            }
        }

        /// Called before each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub inline fn beginString(self: Self, writer: W) W.Error!void {
            if (beginStringFn) |f| {
                try f(self.context, writer);
            } else {
                writer.writeAll("\"") catch unreachable;
            }
        }

        /// Called after each series of `write_string_fragment` and
        /// `write_char_escape`.  Writes a `"` to the specified writer.
        pub inline fn endString(self: Self, writer: W) W.Error!void {
            if (endStringFn) |f| {
                try f(self.context, writer);
            } else {
                writer.writeAll("\"") catch unreachable;
            }
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
