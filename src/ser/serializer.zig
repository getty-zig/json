const getty = @import("getty");
const std = @import("std");

const CompactFormatter = @import("impl/formatter/compact.zig").Formatter;
const PrettyFormatter = @import("impl/formatter/pretty.zig").Formatter;
const writeEscaped = @import("impl/formatter/details/escape.zig").writeEscaped;

pub fn serializer(
    ally: ?std.mem.Allocator,
    w: anytype,
    sbt: anytype,
) blk: {
    var f = CompactFormatter(@TypeOf(w)){};
    const ff = f.formatter();

    break :blk Serializer(@TypeOf(w), @TypeOf(ff), sbt);
} {
    var f = CompactFormatter(@TypeOf(w)){};
    const ff = f.formatter();

    return Serializer(@TypeOf(w), @TypeOf(ff), sbt).init(ally, w, ff);
}

pub fn Serializer(
    comptime Writer: type,
    comptime Formatter: type,
    comptime sbt: anytype,
) type {
    return struct {
        ally: ?std.mem.Allocator = null,

        writer: Writer,
        formatter: Formatter,

        const Self = @This();

        pub fn init(ally: ?std.mem.Allocator, w: Writer, f: Formatter) Self {
            return .{ .ally = ally, .writer = w, .formatter = f };
        }

        pub usingnamespace getty.Serializer(
            *Self,
            Ok,
            Error,
            sbt,
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
        const Error = getty.ser.Error || std.mem.Allocator.Error || error{
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

        fn serializeBool(self: *Self, v: bool) Error!Ok {
            self.formatter.writeBool(self.writer, v) catch return Error.Io;
        }

        fn serializeEnum(self: *Self, _: anytype, variant: []const u8) Error!Ok {
            serializeString(self, variant) catch return Error.Io;
        }

        fn serializeFloat(self: *Self, v: anytype) Error!Ok {
            if (@TypeOf(v) != comptime_float and (std.math.isNan(v) or std.math.isInf(v))) {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            } else {
                self.formatter.writeFloat(self.writer, v) catch return Error.Io;
            }
        }

        fn serializeInt(self: *Self, v: anytype) Error!Ok {
            self.formatter.writeInt(self.writer, v) catch return Error.Io;
        }

        fn serializeMap(self: *Self, len: ?usize) Error!Serialize {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (len) |l| {
                if (l == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return Serialize{ .ser = self, .max = 0 };
                }

                return Serialize{ .ser = self, .state = .first, .max = l };
            }

            return Serialize{ .ser = self, .state = .first };
        }

        fn serializeNull(self: *Self) Error!Ok {
            self.formatter.writeNull(self.writer) catch return Error.Io;
        }

        fn serializeSeq(self: *Self, len: ?usize) Error!Serialize {
            self.formatter.beginArray(self.writer) catch return Error.Io;

            if (len) |l| {
                if (l == 0) {
                    self.formatter.endArray(self.writer) catch return Error.Io;
                    return Serialize{ .ser = self, .max = 0 };
                }

                return Serialize{ .ser = self, .state = .first, .max = l };
            }

            return Serialize{ .ser = self, .state = .first };
        }

        fn serializeSome(self: *Self, v: anytype) Error!Ok {
            try getty.serialize(self.ally, v, self.serializer());
        }

        fn serializeString(self: *Self, v: anytype) Error!Ok {
            if (!std.unicode.utf8ValidateSlice(v)) {
                return Error.Syntax;
            }

            self.formatter.beginString(self.writer) catch return Error.Io;
            writeEscaped(v, self.writer, self.formatter) catch return Error.Io;
            self.formatter.endString(self.writer) catch return Error.Io;
        }

        fn serializeStruct(self: *Self, comptime _: []const u8, len: usize) Error!Serialize {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (len == 0) {
                self.formatter.endObject(self.writer) catch return Error.Io;
                return Serialize{ .ser = self, .max = 0 };
            }

            return Serialize{ .ser = self, .state = .first, .max = len };
        }

        // Implementation of Getty's aggregate serialization interfaces.
        const Serialize = struct {
            ser: *Self,
            state: enum { empty, first, rest } = .empty,

            // Maximum number of elements/entries to serialize.
            max: ?usize = null,

            // Number of elements/entries serialized.
            count: usize = 0,

            ////////////////////////////////////////////////////////////////////
            // Sequence
            ////////////////////////////////////////////////////////////////////

            pub usingnamespace getty.ser.Seq(
                *Serialize,
                Ok,
                Error,
                .{
                    .serializeElement = serializeElement,
                    .end = seq_end,
                },
            );

            fn serializeElement(s: *Serialize, v: anytype) Error!void {
                // Number of elements in sequence is unknown, so just try to
                // serialize an element and return an error if there are none.
                if (s.max == null) {
                    return try s._serializeElement(v);
                }

                // Number of elements in sequence is known but we've already
                // serialized all elements, so just return from the function.
                if (s.count >= s.max.?) {
                    return;
                }

                // Number of elements in sequence is known but we haven't
                // serialized all of them yet, so serialize an element and
                // increment the current count.
                var elem = try s._serializeElement(v);
                defer s.count += 1;

                return elem;
            }

            fn seq_end(s: *Serialize) Error!Ok {
                if (s.state != .empty) {
                    s.ser.formatter.endArray(s.ser.writer) catch return error.Io;
                }
            }

            ////////////////////////////////////////////////////////////////////
            // Map
            ////////////////////////////////////////////////////////////////////

            pub usingnamespace getty.ser.Map(
                *Serialize,
                Ok,
                Error,
                .{
                    .serializeKey = serializeKey,
                    .serializeValue = serializeValue,
                    .end = map_end,
                },
            );

            fn serializeKey(s: *Serialize, k: anytype) Error!void {
                if (s.max) |max| {
                    // Number of elements in map is known but we've already
                    // serialized all entries, so just return from the function.
                    if (s.count >= max) {
                        return;
                    }
                }

                // Number of entries in map is either:
                //
                //   1) Unknown, so try to serialize a key and return an error
                //      if there are none.
                //
                //   2) Known, but we haven't serialized all of them yet so
                //      start serializing an entry by serializing a key. The
                //      count will be incremented in serializeValue.
                var mks = MapKeySerializer{ .ser = s.ser };
                const ss = mks.serializer();

                try s._serializeKey(k, ss);
            }

            fn serializeValue(s: *Serialize, v: anytype) Error!void {
                // Number of entries in map is unknown, so just try to
                // serialize an entry and return an error if there are none.
                if (s.max == null) {
                    return try s._serializeElement(v);
                }

                // Number of entries in map is known but we've already
                // serialized all entries, so just return from the function.
                if (s.count >= s.max.?) {
                    return;
                }

                // Number of entries in map is known but we haven't serialized
                // all of them yet, so serialize an entry and increment the
                // current count.
                var value = try s._serializeValue(v);
                defer s.count += 1;

                return value;
            }

            fn map_end(s: *Serialize) Error!Ok {
                if (s.state != .empty) {
                    s.ser.formatter.endObject(s.ser.writer) catch return error.Io;
                }
            }

            ////////////////////////////////////////////////////////////////////
            // Structure
            ////////////////////////////////////////////////////////////////////

            pub usingnamespace getty.ser.Structure(
                *Serialize,
                Ok,
                Error,
                .{
                    .serializeField = serializeField,
                    .end = map_end,
                },
            );

            fn serializeField(s: *Serialize, comptime k: []const u8, v: anytype) Error!void {
                // Number of fields in struct is unknown, so just try to
                // serialize a field and return an error if there are none.
                if (s.max == null) {
                    return try s._serializeField(k, v);
                }

                // Number of fields in struct is known but we've already
                // serialized all fields, so just return from the function.
                if (s.count >= s.max.?) {
                    return;
                }

                var f = try s._serializeField(k, v);
                defer s.count += 1;

                return f;
            }

            ////////////////////////////////////////////////////////////////////
            // Private methods
            ////////////////////////////////////////////////////////////////////

            fn _serializeElement(s: *Serialize, v: anytype) Error!void {
                s.ser.formatter.beginArrayValue(s.ser.writer, s.state == .first) catch return error.Io;
                try getty.serialize(s.ser.ally, v, s.ser.serializer());
                s.ser.formatter.endArrayValue(s.ser.writer) catch return error.Io;

                s.state = .rest;
            }

            fn _serializeKey(s: *Serialize, k: anytype, ser: anytype) Error!void {
                s.ser.formatter.beginObjectKey(s.ser.writer, s.state == .first) catch return error.Io;
                try getty.serialize(s.ser.ally, k, ser);
                s.ser.formatter.endObjectKey(s.ser.writer) catch return error.Io;

                s.state = .rest;
            }

            fn _serializeValue(s: *Serialize, v: anytype) Error!void {
                s.ser.formatter.beginObjectValue(s.ser.writer) catch return error.Io;
                try getty.serialize(s.ser.ally, v, s.ser.serializer());
                s.ser.formatter.endObjectValue(s.ser.writer) catch return error.Io;
            }

            fn _serializeField(s: *Serialize, comptime k: []const u8, v: anytype) Error!void {
                if (comptime !std.unicode.utf8ValidateSlice(k)) {
                    return Error.Syntax;
                }

                var sks = StructKeySerializer{ .ser = s.ser };
                const ss = sks.serializer();

                try s._serializeKey(k, ss);
                try s._serializeValue(v);
            }
        };

        // An internal Getty serializer for map keys.
        const MapKeySerializer = struct {
            ser: *Self,

            pub usingnamespace getty.Serializer(
                MapKeySerializer,
                Ok,
                Error,
                Self.@"getty.Serializer".user_st,
                Self.@"getty.Serializer".serializer_st,
                null,
                null,
                null,
                .{
                    .serializeBool = _serializeBool,
                    .serializeInt = _serializeInt,
                    .serializeString = _serializeString,
                },
            );

            fn _serializeBool(s: MapKeySerializer, v: bool) Error!Ok {
                try getty.serialize(s.ser.ally, if (v) "true" else "false", s.ser.serializer());
            }

            fn _serializeInt(s: MapKeySerializer, v: anytype) Error!Ok {
                // TODO: Change to buffer size to digits10 + 1 for better space efficiency.
                var buf: [@max(@bitSizeOf(@TypeOf(v)), 1) + 1]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);

                // We have to manually format the integer into a string
                // ourselves instead of using the serializer's formatter. The
                // formatter's expecting the user's writer type, so we can't
                // use it here.
                std.fmt.formatInt(v, 10, .lower, .{}, fbs.writer()) catch return error.Io;

                try getty.serialize(s.ser.ally, fbs.getWritten(), s.ser.serializer());
            }

            fn _serializeString(s: MapKeySerializer, v: anytype) Error!Ok {
                try getty.serialize(s.ser.ally, v, s.ser.serializer());
            }
        };

        // An internal Getty serializer for struct keys.
        //
        // The main difference between key serialization for structs
        // and maps is that keys are compile-time known for structs,
        // meaning we can avoid having to validate them at runtime,
        // which gives us a pretty significant performance increase.
        const StructKeySerializer = struct {
            ser: *Self,

            pub usingnamespace getty.Serializer(
                StructKeySerializer,
                Ok,
                Error,
                Self.@"getty.Serializer".user_st,
                Self.@"getty.Serializer".serializer_st,
                null,
                null,
                null,
                .{
                    .serializeString = _serializeString,
                },
            );

            fn _serializeString(s: StructKeySerializer, v: anytype) Error!Ok {
                s.ser.formatter.beginString(s.ser.writer) catch return Error.Io;
                writeEscaped(v, s.ser.writer, s.ser.formatter) catch return Error.Io;
                s.ser.formatter.endString(s.ser.writer) catch return Error.Io;
            }
        };
    };
}
