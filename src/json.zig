const getty = @import("getty");
const std = @import("std");

const CompactFormatter = @import("formatter.zig").CompactFormatter;

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
        pub const SerializerIface = getty.ser.Serializer(
            *Self,
            Ok,
            Error,
            //Map,
            Sequence,
            Struct,
            //Tuple,
            SerializerImpl.serializeBool,
            SerializerImpl.serializeFloat,
            SerializerImpl.serializeInt,
            SerializerImpl.serializeNull,
            SerializerImpl.serializeSequence,
            SerializerImpl.serializeString,
            SerializerImpl.serializeStruct,
            SerializerImpl.serializeVariant,
        );

        pub fn getSerializer(self: *Self) SerializerIface {
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

        //pub const Map = SerializeMap;
        pub const Sequence = SerializeSequenceIface;
        pub const Struct = SerializeStructIface;
        //pub const Tuple = ST;

        pub const SerializerImpl = struct {
            /// Implements `boolFn` for `getty.ser.Serializer`.
            pub fn serializeBool(self: *Self, value: bool) Error!Ok {
                self.formatter.writeBool(self.writer, value) catch return Error.Io;
            }

            /// Implements `intFn` for `getty.ser.Serializer`.
            pub fn serializeInt(self: *Self, value: anytype) Error!Ok {
                self.formatter.writeInt(self.writer, value) catch return Error.Io;
            }

            /// Implements `floatFn` for `getty.ser.Serializer`.
            ///
            /// TODO: Handle Inf for comptime_floats.
            pub fn serializeFloat(self: *Self, value: anytype) Error!Ok {
                //if (std.math.isNan(value) or std.math.isInf(value)) {
                if (std.math.isNan(value)) {
                    self.formatter.writeNull(self.writer) catch return Error.Io;
                } else {
                    self.formatter.writeFloat(self.writer, value) catch return Error.Io;
                }
            }

            /// Implements `nullFn` for `getty.ser.Serializer`.
            pub fn serializeNull(self: *Self) Error!Ok {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            }

            /// Implements `sequenceFn` for `getty.ser.Serializer`.
            pub fn serializeSequence(self: *Self, length: ?usize) Error!Sequence {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |_| {
                    //self.formatter.endArray(self.writer) catch return Error.Io;

                    //return Map;
                    return self.getSequence();
                } else {
                    return self.getSequence();
                    //return Map;
                }
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
                serializeString(self, @tagName(value)) catch return Error.Io;
            }
        };

        /// Implements `getty.ser.SerializeSequence`.
        pub const SerializeSequenceIface = getty.ser.SerializeSequence(
            *Self,
            Ok,
            Error,
            SerializeSequenceImpl.serializeElement,
            SerializeSequenceImpl.end,
        );

        pub fn getSequence(self: *Self) SerializeSequenceIface {
            return .{ .context = self };
        }

        pub const SerializeSequenceImpl = struct {
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
            pub fn end(self: *Self) Error!Ok {
                self.writer.writeByte(']') catch return Error.Io;
            }
        };

        /// Implements `getty.ser.SerializeStruct`.
        pub const SerializeStructIface = getty.ser.SerializeStruct(
            *Self,
            Ok,
            Error,
            SerializeStructImpl.serializeField,
            SerializeStructImpl.end,
        );

        pub fn getStruct(self: *Self) SerializeStructIface {
            return .{ .context = self };
        }

        pub const SerializeStructImpl = struct {
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
            pub fn end(self: *Self) Error!Ok {
                self.writer.writeByte('}') catch return Error.Io;
            }
        };
    };
}

/// Serializes a value using the JSON serializer into a provided writer.
pub fn toWriter(writer: anytype, value: anytype) !void {
    var cf = CompactFormatter(@TypeOf(writer)){};
    const formatter = cf.formatter();
    var s = Serializer(@TypeOf(writer), @TypeOf(formatter)).init(writer, formatter);
    try getty.ser.serialize(&s, value);
}

//// Serialize the given data structure as pretty-printed JSON into the IO
//// stream.
//pub fn toWriterPretty(writer: anytype, value: anytype) !void {
//const pf = PrettyFormatter(@TypeOf(writer)){};
//var s = Serializer(@TypeOf(writer), @TypeOf(pf)).init(writer, pf);
//try getty.ser.serialize(&s, value);
//}

/// Returns an owned slice of a serialized JSON string.
///
/// The caller is responsible for freeing the returned memory.
pub fn toString(allocator: *std.mem.Allocator, value: anytype) ![]const u8 {
    var array_list = std.ArrayList(u8).init(allocator);
    errdefer array_list.deinit();

    try toWriter(array_list.writer(), value);
    return array_list.toOwnedSlice();
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
