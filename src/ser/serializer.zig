const getty = @import("getty");
const std = @import("std");

const writeEscaped = @import("impl/formatter/details/escape.zig").writeEscaped;

pub fn Serializer(
    comptime Writer: type,
    comptime Formatter: type,
    comptime user_sbt: anytype,
) type {
    return struct {
        allocator: ?std.mem.Allocator = null,

        writer: Writer,
        formatter: Formatter,

        const Self = @This();

        pub fn init(
            allocator: ?std.mem.Allocator,
            writer: Writer,
            formatter: Formatter,
        ) Self {
            return .{
                .allocator = allocator,
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

        fn serializeBool(self: *Self, value: bool) Error!Ok {
            self.formatter.writeBool(self.writer, value) catch return Error.Io;
        }

        fn serializeEnum(self: *Self, _: anytype, name: []const u8) Error!Ok {
            serializeString(self, name) catch return Error.Io;
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
                    return Serialize{ .ser = self, .max = 0 };
                }

                return Serialize{ .ser = self, .state = .first, .max = l };
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
                    return Serialize{ .ser = self, .max = 0 };
                }

                return Serialize{ .ser = self, .state = .first, .max = l };
            }

            return Serialize{ .ser = self, .state = .first };
        }

        fn serializeSome(self: *Self, value: anytype) Error!Ok {
            try getty.serialize(self.allocator, value, self.serializer());
        }

        fn serializeString(self: *Self, value: anytype) Error!Ok {
            if (!std.unicode.utf8ValidateSlice(value)) {
                return Error.Syntax;
            }

            self.formatter.beginString(self.writer) catch return Error.Io;
            writeEscaped(value, self.writer, self.formatter) catch return Error.Io;
            self.formatter.endString(self.writer) catch return Error.Io;
        }

        fn serializeStruct(self: *Self, comptime _: []const u8, length: usize) Error!Serialize {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (length == 0) {
                self.formatter.endObject(self.writer) catch return Error.Io;
                return Serialize{ .ser = self, .max = 0 };
            }

            return Serialize{ .ser = self, .state = .first, .max = length };
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

            fn serializeElement(s: *Serialize, value: anytype) Error!void {
                // Number of elements in sequence is unknown, so just try to
                // serialize an element and return an error if there are none.
                if (s.max == null) {
                    return try s._serializeElement(value);
                }

                // Number of elements in sequence is known but we've already
                // serialized all elements, so just return from the function.
                if (s.count >= s.max.?) {
                    return;
                }

                // Number of elements in sequence is known but we haven't
                // serialized all of them yet, so serialize an element and
                // increment the current count.
                var v = try s._serializeElement(value);
                s.count += 1;

                return v;
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

            fn serializeKey(s: *Serialize, key: anytype) Error!void {
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
                try s._serializeKey(key, mks.serializer());
            }

            fn serializeValue(s: *Serialize, value: anytype) Error!void {
                // Number of entries in map is unknown, so just try to
                // serialize an entry and return an error if there are none.
                if (s.max == null) {
                    return try s._serializeElement(value);
                }

                // Number of entries in map is known but we've already
                // serialized all entries, so just return from the function.
                if (s.count >= s.max.?) {
                    return;
                }

                // Number of entries in map is known but we haven't serialized
                // all of them yet, so serialize an entry and increment the
                // current count.
                var v = try s._serializeValue(value);
                s.count += 1;

                return v;
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

            fn serializeField(
                s: *Serialize,
                comptime key: []const u8,
                value: anytype,
            ) Error!void {
                // Number of fields in struct is unknown, so just try to
                // serialize a field and return an error if there are none.
                if (s.max == null) {
                    return try s._serializeField(key, value);
                }

                // Number of fields in struct is known but we've already
                // serialized all fields, so just return from the function.
                if (s.count >= s.max.?) {
                    return;
                }

                var v = try s._serializeField(key, value);
                s.count += 1;

                return v;
            }

            ////////////////////////////////////////////////////////////////////
            // Private methods
            ////////////////////////////////////////////////////////////////////

            fn _serializeElement(s: *Serialize, value: anytype) Error!void {
                s.ser.formatter.beginArrayValue(s.ser.writer, s.state == .first) catch return error.Io;
                try getty.serialize(s.ser.allocator, value, s.ser.serializer());
                s.ser.formatter.endArrayValue(s.ser.writer) catch return error.Io;

                s.state = .rest;
            }

            fn _serializeKey(s: *Serialize, key: anytype, serializer: anytype) Error!void {
                s.ser.formatter.beginObjectKey(s.ser.writer, s.state == .first) catch return error.Io;
                try getty.serialize(s.ser.allocator, key, serializer);
                s.ser.formatter.endObjectKey(s.ser.writer) catch return error.Io;

                s.state = .rest;
            }

            fn _serializeValue(s: *Serialize, value: anytype) Error!void {
                s.ser.formatter.beginObjectValue(s.ser.writer) catch return error.Io;
                try getty.serialize(s.ser.allocator, value, s.ser.serializer());
                s.ser.formatter.endObjectValue(s.ser.writer) catch return error.Io;
            }

            fn _serializeField(s: *Serialize, comptime key: []const u8, value: anytype) Error!void {
                if (comptime !std.unicode.utf8ValidateSlice(key)) {
                    return Error.Syntax;
                }

                var sks = StructKeySerializer{ .ser = s.ser };
                try s._serializeKey(key, sks.serializer());
                try s._serializeValue(value);
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

            fn _serializeBool(s: MapKeySerializer, value: bool) Error!Ok {
                try getty.serialize(s.ser.allocator, if (value) "true" else "false", s.ser.serializer());
            }

            fn _serializeInt(s: MapKeySerializer, value: anytype) Error!Ok {
                // TODO: Change to buffer size to digits10 + 1 for better space efficiency.
                var buf: [std.math.max(@bitSizeOf(@TypeOf(value)), 1) + 1]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);

                // We have to manually format the integer into a string
                // ourselves instead of using the serializer's formatter. The
                // formatter's expecting the user's writer type, so we can't
                // use it here.
                std.fmt.formatInt(value, 10, .lower, .{}, fbs.writer()) catch return error.Io;

                try getty.serialize(s.ser.allocator, fbs.getWritten(), s.ser.serializer());
            }

            fn _serializeString(s: MapKeySerializer, value: anytype) Error!Ok {
                try getty.serialize(s.ser.allocator, value, s.ser.serializer());
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

            fn _serializeString(s: StructKeySerializer, value: anytype) Error!Ok {
                s.ser.formatter.beginString(s.ser.writer) catch return Error.Io;
                writeEscaped(value, s.ser.writer, s.ser.formatter) catch return Error.Io;
                s.ser.formatter.endString(s.ser.writer) catch return Error.Io;
            }
        };
    };
}
