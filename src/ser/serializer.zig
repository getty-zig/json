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
            Map,
            Seq,
            Structure,
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

        const Map = Serialize(Self);
        const Seq = Serialize(Self);
        const Structure = Serialize(Self);

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

        fn serializeMap(self: *Self, length: ?usize) Error!Map {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (length) |l| {
                if (l == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return Map{ .ser = self, .state = .empty };
                }
            }

            return Map{ .ser = self, .state = .first };
        }

        fn serializeNull(self: *Self) Error!Ok {
            self.formatter.writeNull(self.writer) catch return Error.Io;
        }

        fn serializeSeq(self: *Self, length: ?usize) Error!Seq {
            self.formatter.beginArray(self.writer) catch return Error.Io;

            if (length) |l| {
                if (l == 0) {
                    self.formatter.endArray(self.writer) catch return Error.Io;
                    return Seq{ .ser = self, .state = .empty };
                }
            }

            return Seq{ .ser = self, .state = .first };
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

        fn serializeStruct(self: *Self, comptime name: []const u8, length: usize) Error!Structure {
            _ = name;

            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (length == 0) {
                self.formatter.endObject(self.writer) catch return Error.Io;
                return Structure{ .ser = self, .state = .empty };
            }

            return Structure{ .ser = self, .state = .first };
        }
    };
}

fn Serialize(comptime Ser: type) type {
    return struct {
        ser: *Ser,
        state: enum { empty, first, rest },

        const Self = @This();

        pub usingnamespace getty.ser.Map(
            *Self,
            Ser.Ok,
            Ser.Error,
            .{
                .serializeKey = _map.serializeKey,
                .serializeValue = _map.serializeValue,
                .end = _map.end,
            },
        );

        pub usingnamespace getty.ser.Seq(
            *Self,
            Ser.Ok,
            Ser.Error,
            .{
                .serializeElement = _seq.serializeElement,
                .end = _seq.end,
            },
        );

        pub usingnamespace getty.ser.Structure(
            *Self,
            Ser.Ok,
            Ser.Error,
            .{
                .serializeField = _structure.serializeField,
                .end = _map.end,
            },
        );

        const _map = struct {
            fn serializeKey(self: *Self, key: anytype) Ser.Error!void {
                var mks = MapKeySerializer(Ser.@"getty.Serializer"){ .ser = self.ser.serializer() };
                const s = mks.serializer();

                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .first) catch return error.Io;
                try getty.serialize(key, s);
                self.ser.formatter.endObjectKey(self.ser.writer) catch return error.Io;

                self.state = .rest;
            }

            fn serializeValue(self: *Self, value: anytype) Ser.Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return error.Io;
                try getty.serialize(value, self.ser.serializer());
                self.ser.formatter.endObjectValue(self.ser.writer) catch return error.Io;
            }

            fn end(self: *Self) Ser.Error!Ser.Ok {
                if (self.state != .empty) {
                    self.ser.formatter.endObject(self.ser.writer) catch return error.Io;
                }
            }
        };

        const _seq = struct {
            fn serializeElement(self: *Self, value: anytype) Ser.Error!void {
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .first) catch return error.Io;
                try getty.serialize(value, self.ser.serializer());
                self.ser.formatter.endArrayValue(self.ser.writer) catch return error.Io;

                self.state = .rest;
            }

            fn end(self: *Self) Ser.Error!Ser.Ok {
                if (self.state != .empty) {
                    self.ser.formatter.endArray(self.ser.writer) catch return error.Io;
                }
            }
        };

        const _structure = struct {
            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Ser.Error!void {
                var k = blk: {
                    var k: [key.len + 2]u8 = undefined;
                    k[0] = '"';
                    k[k.len - 1] = '"';

                    var fbs = std.io.fixedBufferStream(&k);
                    fbs.seekTo(1) catch unreachable; // UNREACHABLE: The length of `k` is guaranteed to be > 1.
                    fbs.writer().writeAll(key) catch return error.Io;

                    break :blk k;
                };

                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .first) catch return error.Io;
                self.ser.formatter.writeRawFragment(self.ser.writer, &k) catch return error.Io;
                self.ser.formatter.endObjectKey(self.ser.writer) catch return error.Io;

                try self.map().serializeValue(value);

                self.state = .rest;
            }
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
