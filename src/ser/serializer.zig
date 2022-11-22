const getty = @import("getty");
const std = @import("std");

const fmt = @import("impl/formatter/details/fmt.zig");

const escape = @import("impl/formatter/details/escape.zig").escape;

pub fn Serializer(comptime Writer: type, comptime Formatter: type, comptime user_sbt: anytype) type {
    return struct {
        writer: Writer,
        formatter: Formatter,

        const Self = @This();

        pub fn init(writer: Writer, formatter: Formatter) Self {
            return .{
                .writer = writer,
                .formatter = formatter,
            };
        }

        pub usingnamespace getty.Serializer(
            *Self,
            Ok,
            Error,
            user_sbt,
            null,
            Serialize,
            Serialize,
            Serialize,
            .{
                .serializeBool = serializeBool,
                .serializeEnum = serializeEnum,
                .serializeFloat = serializeFloat,
                .serializeInt = serializeInt,
                .serializeMap = serializeMap,
                .serializeNull = serializeNull,
                .serializeSeq = serializeSeq,
                .serializeSome = serializeSome,
                .serializeString = serializeString,
                .serializeStruct = serializeStruct,
                .serializeVoid = serializeNull,
            },
        );

        const Ok = void;
        const Error = std.mem.Allocator.Error || error{
            /// Failure to read or write bytes on an IO stream.
            Io,

            /// Input was syntactically incorrect.
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

        fn serializeBool(self: *Self, value: bool) Error!Ok {
            self.formatter.writeBool(self.writer, value) catch return Error.Io;
        }

        fn serializeEnum(self: *Self, value: anytype) Error!Ok {
            serializeString(self, @tagName(value)) catch return Error.Io;
        }

        fn serializeFloat(self: *Self, value: anytype) Error!Ok {
            if (@TypeOf(value) != comptime_float and (std.math.isNan(value) or std.math.isInf(value))) {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            } else {
                self.formatter.writeFloat(self.writer, value) catch return Error.Io;
            }
        }

        fn serializeInt(self: *Self, value: anytype) Error!Ok {
            self.formatter.writeInt(self.writer, value) catch return Error.Io;
        }

        fn serializeMap(self: *Self, length: ?usize) Error!Serialize {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (length) |l| {
                if (l == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return Serialize{ .ser = self, .state = .empty };
                }
            }

            return Serialize{ .ser = self, .state = .first };
        }

        fn serializeNull(self: *Self) Error!Ok {
            self.formatter.writeNull(self.writer) catch return Error.Io;
        }

        fn serializeSeq(self: *Self, length: ?usize) Error!Serialize {
            self.formatter.beginArray(self.writer) catch return Error.Io;

            if (length) |l| {
                if (l == 0) {
                    self.formatter.endArray(self.writer) catch return Error.Io;
                    return Serialize{ .ser = self, .state = .empty };
                }
            }

            return Serialize{ .ser = self, .state = .first };
        }

        fn serializeSome(self: *Self, value: anytype) Error!Ok {
            try getty.serialize(value, self.serializer());
        }

        fn serializeString(self: *Self, value: anytype) Error!Ok {
            if (!std.unicode.utf8ValidateSlice(value)) {
                return Error.Syntax;
            }

            self.formatter.beginString(self.writer) catch return Error.Io;
            escape(value, self.writer, self.formatter) catch return Error.Syntax;
            self.formatter.endString(self.writer) catch return Error.Io;
        }

        fn serializeStruct(self: *Self, comptime name: []const u8, length: usize) Error!Serialize {
            _ = name;

            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (length == 0) {
                self.formatter.endObject(self.writer) catch return Error.Io;
                return Serialize{ .ser = self, .state = .empty };
            }

            return Serialize{ .ser = self, .state = .first };
        }

        const Serialize = struct {
            ser: *Self,
            state: enum { empty, first, rest },

            pub usingnamespace getty.ser.Map(
                *Serialize,
                Ok,
                Error,
                .{
                    .serializeKey = _map.serializeKey,
                    .serializeValue = _map.serializeValue,
                    .end = _map.end,
                },
            );

            pub usingnamespace getty.ser.Seq(
                *Serialize,
                Ok,
                Error,
                .{
                    .serializeElement = _seq.serializeElement,
                    .end = _seq.end,
                },
            );

            pub usingnamespace getty.ser.Structure(
                *Serialize,
                Ok,
                Error,
                .{
                    .serializeField = _structure.serializeField,
                    .end = _map.end,
                },
            );

            const _map = struct {
                fn serializeKey(s: *Serialize, key: anytype) Error!void {
                    var mks = MapKeySerializer(Self.@"getty.Serializer"){ .ser = s.ser.serializer() };

                    s.ser.formatter.beginObjectKey(s.ser.writer, s.state == .first) catch return error.Io;
                    try getty.serialize(key, mks.serializer());
                    s.ser.formatter.endObjectKey(s.ser.writer) catch return error.Io;

                    s.state = .rest;
                }

                fn serializeValue(s: *Serialize, value: anytype) Error!void {
                    s.ser.formatter.beginObjectValue(s.ser.writer) catch return error.Io;
                    try getty.serialize(value, s.ser.serializer());
                    s.ser.formatter.endObjectValue(s.ser.writer) catch return error.Io;
                }

                fn end(s: *Serialize) Error!Ok {
                    if (s.state != .empty) {
                        s.ser.formatter.endObject(s.ser.writer) catch return error.Io;
                    }
                }
            };

            const _seq = struct {
                fn serializeElement(s: *Serialize, value: anytype) Error!void {
                    s.ser.formatter.beginArrayValue(s.ser.writer, s.state == .first) catch return error.Io;
                    try getty.serialize(value, s.ser.serializer());
                    s.ser.formatter.endArrayValue(s.ser.writer) catch return error.Io;

                    s.state = .rest;
                }

                fn end(s: *Serialize) Error!Ok {
                    if (s.state != .empty) {
                        s.ser.formatter.endArray(s.ser.writer) catch return error.Io;
                    }
                }
            };

            const _structure = struct {
                fn serializeField(s: *Serialize, comptime key: []const u8, value: anytype) Error!void {
                    var k = blk: {
                        var k: [key.len + 2]u8 = undefined;
                        k[0] = '"';
                        k[k.len - 1] = '"';

                        var fbs = std.io.fixedBufferStream(&k);
                        fbs.seekTo(1) catch unreachable; // UNREACHABLE: The length of `k` is guaranteed to be > 1.
                        fbs.writer().writeAll(key) catch return error.Io;

                        break :blk k;
                    };

                    s.ser.formatter.beginObjectKey(s.ser.writer, s.state == .first) catch return error.Io;
                    s.ser.formatter.writeRawFragment(s.ser.writer, &k) catch return error.Io;
                    s.ser.formatter.endObjectKey(s.ser.writer) catch return error.Io;

                    try s.map().serializeValue(value);

                    s.state = .rest;
                }
            };
        };
    };
}

fn MapKeySerializer(comptime S: type) type {
    comptime getty.concepts.@"getty.Serializer"(S);

    return struct {
        ser: S,

        const Self = @This();

        pub usingnamespace getty.Serializer(
            Self,
            Ok,
            Error,
            S.user_st,
            S.serializer_st,
            null,
            null,
            null,
            .{
                .serializeBool = serializeBool,
                .serializeInt = serializeInt,
                .serializeString = serializeString,
            },
        );

        const Ok = S.Ok;
        const Error = S.Error;

        fn serializeBool(self: Self, value: bool) Error!Ok {
            try getty.serialize(if (value) "true" else "false", self.ser);
        }

        fn serializeInt(self: Self, value: anytype) Error!Ok {
            // TODO: Change to buffer size to digits10 + 1 for better space efficiency.
            var buf: [std.math.max(std.meta.bitCount(@TypeOf(value)), 1) + 1]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            fmt.formatInt(value, fbs.writer()) catch return error.Io;

            try getty.serialize(fbs.getWritten(), self.ser);
        }

        fn serializeString(self: Self, value: anytype) Error!Ok {
            try getty.serialize(value, self.ser);
        }
    };
}
