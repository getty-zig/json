const getty = @import("getty");
const std = @import("std");

const CompactFormatter = @import("impl/formatter/compact.zig").Formatter;
const PrettyFormatter = @import("impl/formatter/pretty.zig").Formatter;
const writeEscaped = @import("impl/formatter/details/escape.zig").writeEscaped;

pub fn serializer(ally: ?std.mem.Allocator, w: anytype, sbt: anytype) blk: {
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
            Aggregate,
            Aggregate,
            Aggregate,
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

        fn serializeMap(self: *Self, len: ?usize) Error!Aggregate {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (len) |l| {
                if (l == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return Aggregate{ .ser = self, .max = 0 };
                }

                return Aggregate{ .ser = self, .state = .first, .max = l };
            }

            return Aggregate{ .ser = self, .state = .first };
        }

        fn serializeNull(self: *Self) Error!Ok {
            self.formatter.writeNull(self.writer) catch return Error.Io;
        }

        fn serializeSeq(self: *Self, len: ?usize) Error!Aggregate {
            self.formatter.beginArray(self.writer) catch return Error.Io;

            if (len) |l| {
                if (l == 0) {
                    self.formatter.endArray(self.writer) catch return Error.Io;
                    return Aggregate{ .ser = self, .max = 0 };
                }

                return Aggregate{ .ser = self, .state = .first, .max = l };
            }

            return Aggregate{ .ser = self, .state = .first };
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

        fn serializeStruct(self: *Self, comptime _: []const u8, len: usize) Error!Aggregate {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (len == 0) {
                self.formatter.endObject(self.writer) catch return Error.Io;
                return Aggregate{ .ser = self, .max = 0 };
            }

            return Aggregate{ .ser = self, .state = .first, .max = len };
        }

        // Implementation of Getty's aggregate serialization interfaces.
        const Aggregate = struct {
            ser: *Self,
            state: enum { empty, first, rest } = .empty,

            // Maximum number of elements/entries to serialize.
            max: ?usize = null,

            // Number of elements/entries serialized.
            count: usize = 0,

            const A = @This();

            ////////////////////////////////////////////////////////////////////
            // Sequence
            ////////////////////////////////////////////////////////////////////

            pub usingnamespace getty.ser.Seq(
                *A,
                Ok,
                Error,
                .{
                    .serializeElement = serializeElement,
                    .end = seq_end,
                },
            );

            fn serializeElement(a: *A, v: anytype) Error!void {
                // Number of elements in sequence is unknown, so just try to
                // serialize an element and return an error if there are none.
                if (a.max == null) {
                    return try a._serializeElement(v);
                }

                // Number of elements in sequence is known but we've already
                // serialized all elements, so just return from the function.
                if (a.count >= a.max.?) {
                    return;
                }

                // Number of elements in sequence is known but we haven't
                // serialized all of them yet, so serialize an element and
                // increment the current count.
                var elem = try a._serializeElement(v);
                defer a.count += 1;

                return elem;
            }

            fn seq_end(a: *A) Error!Ok {
                if (a.state != .empty) {
                    a.ser.formatter.endArray(a.ser.writer) catch return error.Io;
                }
            }

            ////////////////////////////////////////////////////////////////////
            // Map
            ////////////////////////////////////////////////////////////////////

            pub usingnamespace getty.ser.Map(
                *A,
                Ok,
                Error,
                .{
                    .serializeKey = serializeKey,
                    .serializeValue = serializeValue,
                    .end = map_end,
                },
            );

            fn serializeKey(a: *A, k: anytype) Error!void {
                if (a.max) |max| {
                    // Number of elements in map is known but we've already
                    // serialized all entries, so just return from the function.
                    if (a.count >= max) {
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
                var s = MapKeySerializer{ .ser = a.ser };
                const ss = s.serializer();

                try a._serializeKey(k, ss);
            }

            fn serializeValue(a: *A, v: anytype) Error!void {
                // Number of entries in map is unknown, so just try to
                // serialize an entry and return an error if there are none.
                if (a.max == null) {
                    return try a._serializeElement(v);
                }

                // Number of entries in map is known but we've already
                // serialized all entries, so just return from the function.
                if (a.count >= a.max.?) {
                    return;
                }

                // Number of entries in map is known but we haven't serialized
                // all of them yet, so serialize an entry and increment the
                // current count.
                var value = try a._serializeValue(v);
                defer a.count += 1;

                return value;
            }

            fn map_end(a: *A) Error!Ok {
                if (a.state != .empty) {
                    a.ser.formatter.endObject(a.ser.writer) catch return error.Io;
                }
            }

            ////////////////////////////////////////////////////////////////////
            // Structure
            ////////////////////////////////////////////////////////////////////

            pub usingnamespace getty.ser.Structure(
                *A,
                Ok,
                Error,
                .{
                    .serializeField = serializeField,
                    .end = map_end,
                },
            );

            fn serializeField(a: *A, comptime k: []const u8, v: anytype) Error!void {
                // Number of fields in struct is unknown, so just try to
                // serialize a field and return an error if there are none.
                if (a.max == null) {
                    return try a._serializeField(k, v);
                }

                // Number of fields in struct is known but we've already
                // serialized all fields, so just return from the function.
                if (a.count >= a.max.?) {
                    return;
                }

                var f = try a._serializeField(k, v);
                defer a.count += 1;

                return f;
            }

            ////////////////////////////////////////////////////////////////////
            // Private methods
            ////////////////////////////////////////////////////////////////////

            fn _serializeElement(a: *A, v: anytype) Error!void {
                a.ser.formatter.beginArrayValue(a.ser.writer, a.state == .first) catch return error.Io;
                try getty.serialize(a.ser.ally, v, a.ser.serializer());
                a.ser.formatter.endArrayValue(a.ser.writer) catch return error.Io;

                a.state = .rest;
            }

            fn _serializeKey(a: *A, k: anytype, ser: anytype) Error!void {
                a.ser.formatter.beginObjectKey(a.ser.writer, a.state == .first) catch return error.Io;
                try getty.serialize(a.ser.ally, k, ser);
                a.ser.formatter.endObjectKey(a.ser.writer) catch return error.Io;

                a.state = .rest;
            }

            fn _serializeValue(a: *A, v: anytype) Error!void {
                a.ser.formatter.beginObjectValue(a.ser.writer) catch return error.Io;
                try getty.serialize(a.ser.ally, v, a.ser.serializer());
                a.ser.formatter.endObjectValue(a.ser.writer) catch return error.Io;
            }

            fn _serializeField(a: *A, comptime k: []const u8, v: anytype) Error!void {
                if (comptime !std.unicode.utf8ValidateSlice(k)) {
                    return Error.Syntax;
                }

                var s = StructKeySerializer{ .ser = a.ser };
                const ss = s.serializer();

                try a._serializeKey(k, ss);
                try a._serializeValue(v);
            }
        };

        // An internal Getty serializer for map keys.
        const MapKeySerializer = struct {
            ser: *Self,

            const S = @This();

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

            fn _serializeBool(m: S, v: bool) Error!Ok {
                const ss = m.ser.serializer();
                try getty.serialize(m.ser.ally, if (v) "true" else "false", ss);
            }

            fn _serializeInt(m: S, v: anytype) Error!Ok {
                // TODO: Change to buffer size to digits10 + 1 for better space efficiency.
                var buf: [@max(@bitSizeOf(@TypeOf(v)), 1) + 1]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&buf);
                const w = fbs.writer();

                // We have to manually format the integer into a string
                // ourselves instead of using the serializer's formatter. The
                // formatter's expecting the user's writer type, so we can't
                // use it here.
                std.fmt.formatInt(v, 10, .lower, .{}, w) catch return error.Io;

                const ss = m.ser.serializer();
                try getty.serialize(m.ser.ally, fbs.getWritten(), ss);
            }

            fn _serializeString(m: S, v: anytype) Error!Ok {
                try getty.serialize(m.ser.ally, v, m.ser.serializer());
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

            const S = @This();

            pub usingnamespace getty.Serializer(
                S,
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

            fn _serializeString(s: S, v: anytype) Error!Ok {
                s.ser.formatter.beginString(s.ser.writer) catch return Error.Io;
                writeEscaped(v, s.ser.writer, s.ser.formatter) catch return Error.Io;
                s.ser.formatter.endString(s.ser.writer) catch return Error.Io;
            }
        };
    };
}
