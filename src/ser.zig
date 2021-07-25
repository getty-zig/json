const getty = @import("getty");
const std = @import("std");

const formatEscapedString = @import("formatter.zig").formatEscapedString;
const CompactFormatter = @import("formatters/compact.zig").Formatter;

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
        ///
        /// TODO: Reorder functions
        pub const S = getty.ser.Serializer(
            *Self,
            Ok,
            Error,
            //Map,
            Sequence,
            Struct,
            //Tuple,
            _S.serializeBool,
            _S.serializeFloat,
            _S.serializeInt,
            _S.serializeNull,
            _S.serializeSequence,
            _S.serializeString,
            _S.serializeStruct,
            _S.serializeVariant,
        );

        pub fn getSerializer(self: *Self) S {
            return .{ .context = self };
        }

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
        pub const Sequence = Map(W, F);
        pub const Struct = SST;
        //pub const Tuple = ST;

        const _S = struct {
            /// Implements `boolFn` for `getty.ser.Serializer`.
            fn serializeBool(self: *Self, value: bool) Error!Ok {
                self.formatter.writeBool(self.writer, value) catch return Error.Io;
            }

            /// Implements `intFn` for `getty.ser.Serializer`.
            fn serializeInt(self: *Self, value: anytype) Error!Ok {
                self.formatter.writeInt(self.writer, value) catch return Error.Io;
            }

            /// Implements `floatFn` for `getty.ser.Serializer`.
            ///
            /// TODO: Handle Inf for comptime_floats.
            fn serializeFloat(self: *Self, value: anytype) Error!Ok {
                //if (std.math.isNan(value) or std.math.isInf(value)) {
                if (std.math.isNan(value)) {
                    self.formatter.writeNull(self.writer) catch return Error.Io;
                } else {
                    self.formatter.writeFloat(self.writer, value) catch return Error.Io;
                }
            }

            /// Implements `nullFn` for `getty.ser.Serializer`.
            fn serializeNull(self: *Self) Error!Ok {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            }

            /// Implements `sequenceFn` for `getty.ser.Serializer`.
            fn serializeSequence(self: *Self, length: ?usize) Error!Sequence {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endArray(self.writer) catch return Error.Io;
                        return Map(W, F){ .ser = self, .state = .Empty };
                    }
                }

                return Map(W, F){ .ser = self, .state = .First };
            }

            /// Implements `stringFn` for `getty.ser.Serializer`.
            fn serializeString(self: *Self, value: anytype) Error!Ok {
                self.formatter.beginString(self.writer) catch return Error.Io;
                formatEscapedString(self.writer, self.formatter, value) catch return Error.Io;
                self.formatter.endString(self.writer) catch return Error.Io;
            }

            /// Implements `structFn` for `getty.ser.Serializer`.
            fn serializeStruct(self: *Self) Error!Struct {
                self.writer.writeByte('{') catch return Error.Io;

                return self.getStruct();
            }

            /// Implements `variantFn` for `getty.ser.Serializer`.
            fn serializeVariant(self: *Self, value: anytype) Error!Ok {
                serializeString(self, @tagName(value)) catch return Error.Io;
            }
        };

        /// Implements `getty.ser.SerializeStruct`.
        pub const SST = getty.ser.SerializeStruct(
            *Self,
            Ok,
            Error,
            _SST.serializeField,
            _SST.end,
        );

        pub fn getStruct(self: *Self) SST {
            return .{ .context = self };
        }

        const _SST = struct {
            /// Implements `fieldFn` for `getty.ser.SerializeStruct`.
            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Error!void {
                if (self._written > 0) {
                    self.writer.writeByte(',') catch return Error.Io;
                }

                self._written += 1;

                getty.ser.serialize(self, key) catch return Error.Io;
                self.writer.writeByte(':') catch return Error.Io;
                getty.ser.serialize(self, value) catch return Error.Io;
            }

            /// Implements `endFn` for `getty.ser.SerializeStruct`.
            fn end(self: *Self) Error!Ok {
                self.writer.writeByte('}') catch return Error.Io;
            }
        };
    };
}

/// Serializes a value using the JSON serializer into a provided writer.
pub fn toWriter(writer: anytype, value: anytype) !void {
    var cf = CompactFormatter(@TypeOf(writer)){};
    const f = cf.getFormatter();
    var s = Serializer(@TypeOf(writer), @TypeOf(f)).init(writer, f);

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

pub const State = enum {
    Empty,
    First,
    Rest,
};

pub fn Map(comptime W: type, comptime F: type) type {
    const S = Serializer(W, F);

    return struct {
        ser: *S,
        state: State,

        const Self = @This();

        pub const SSE = getty.ser.SerializeSequence(
            *Self,
            S.Ok,
            S.Error,
            _SSE.serializeElement,
            _SSE.end,
        );

        pub fn getSequence(self: *Self) SSE {
            return .{ .context = self };
        }

        const _SSE = struct {
            /// Implements `elementFn` for `getty.ser.SerializeSequence`.
            fn serializeElement(self: *Self, value: anytype) S.Error!S.Ok {
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .First) catch return S.Error.Io;

                self.state = .Rest;
                getty.ser.serialize(self.ser, value) catch return S.Error.Io;

                self.ser.formatter.endArrayValue(self.ser.writer) catch return S.Error.Io;
            }

            /// Implements `endFn` for `getty.ser.SerializeSequence`.
            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .Empty => {},
                    else => self.ser.formatter.endArray(self.ser.writer) catch return S.Error.Io,
                }
            }
        };
    };
}

test "toWriter - Array" {
    try t([_]i8{}, "[]");
    try t([_]i8{1}, "[1]");
    try t([_]i8{ 1, 2 }, "[1,2]");
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

test "toWriter - Float" {
    try t(1.0, "1");
    try t(3.1415, "3.1415");
    try t(-1.0, "-1");
    try t(0.0, "0");
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
