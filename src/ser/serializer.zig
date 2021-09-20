const getty = @import("getty");
const std = @import("std");

const ser = @import("../lib.zig").ser;

const formatEscapedString = ser.formatEscapedString;
const CompactFormatter = ser.CompactFormatter;
const PrettyFormatter = ser.PrettyFormatter;

pub fn Serializer(comptime Writer: type, comptime Formatter: type) type {
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

        /// Implements `getty.ser.Serializer`.
        pub usingnamespace getty.ser.Serializer(
            *Self,
            Ok,
            Error,
            MapSerialize,
            SequenceSerialize,
            StructSerialize,
            TupleSerialize,
            serializeBool,
            serializeEnum,
            serializeFloat,
            serializeInt,
            serializeMap,
            serializeNull,
            serializeSequence,
            serializeString,
            serializeStruct,
            serializeTuple,
            serializeNull,
        );

        const Ok = void;
        const Error = error{
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

        const MapSerialize = Serialize(Self);
        const SequenceSerialize = Serialize(Self);
        const StructSerialize = Serialize(Self);
        const TupleSerialize = Serialize(Self);

        fn serializeBool(self: *Self, value: bool) Error!Ok {
            self.formatter.writeBool(self.writer, value) catch return Error.Io;
        }

        fn serializeEnum(self: *Self, value: anytype) Error!Ok {
            self.serializeString(@tagName(value)) catch return Error.Io;
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

        fn serializeMap(self: *Self, length: ?usize) Error!MapSerialize {
            self.formatter.beginObject(self.writer) catch return Error.Io;

            if (length) |l| {
                if (l == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return MapSerialize{ .ser = self, .state = .empty };
                }
            }

            return MapSerialize{ .ser = self, .state = .first };
        }

        fn serializeNull(self: *Self) Error!Ok {
            self.formatter.writeNull(self.writer) catch return Error.Io;
        }

        fn serializeSequence(self: *Self, length: ?usize) Error!SequenceSerialize {
            self.formatter.beginArray(self.writer) catch return Error.Io;

            if (length) |l| {
                if (l == 0) {
                    self.formatter.endArray(self.writer) catch return Error.Io;
                    return SequenceSerialize{ .ser = self, .state = .empty };
                }
            }

            return SequenceSerialize{ .ser = self, .state = .first };
        }

        fn serializeString(self: *Self, value: anytype) Error!Ok {
            self.formatter.beginString(self.writer) catch return Error.Io;
            formatEscapedString(self.writer, self.formatter, value) catch return Error.Io;
            self.formatter.endString(self.writer) catch return Error.Io;
        }

        fn serializeStruct(self: *Self, name: []const u8, length: usize) Error!StructSerialize {
            _ = name;

            return self.serializeMap(length);
        }

        fn serializeTuple(self: *Self, length: ?usize) Error!TupleSerialize {
            return self.serializeSequence(length);
        }
    };
}

fn Serialize(comptime S: type) type {
    const Ok = S.Ok;
    const Error = S.Error;

    return struct {
        ser: *S,
        state: enum {
            empty,
            first,
            rest,
        },

        const Self = @This();

        /// Implements `getty.ser.MapSerialize`.
        pub usingnamespace getty.ser.MapSerialize(
            *Self,
            Ok,
            Error,
            _M.serializeKey,
            _M.serializeValue,
            _M.serializeEntry,
            _M.end,
        );

        const _M = struct {
            fn serializeKey(self: *Self, key: anytype) Error!void {
                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .first) catch return Error.Io;
                self.state = .rest;
                // TODO: serde-json passes in a MapKeySerializer here instead
                // of self. This works though, so should we change it?
                try getty.serialize(key, self.ser.serializer());
                self.ser.formatter.endObjectKey(self.ser.writer) catch return Error.Io;
            }

            fn serializeValue(self: *Self, value: anytype) Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return Error.Io;
                try getty.serialize(value, self.ser.serializer());
                self.ser.formatter.endObjectValue(self.ser.writer) catch return Error.Io;
            }

            fn serializeEntry(self: *Self, key: anytype, value: anytype) Error!void {
                try serializeKey(self, key);
                try serializeValue(self, value);
            }

            fn end(self: *Self) Error!Ok {
                switch (self.state) {
                    .empty => {},
                    else => self.ser.formatter.endObject(self.ser.writer) catch return Error.Io,
                }
            }
        };

        /// Implements `getty.ser.SequenceSerialize`.
        pub usingnamespace getty.ser.SequenceSerialize(
            *Self,
            Ok,
            Error,
            _SE.serializeElement,
            _SE.end,
        );

        const _SE = struct {
            fn serializeElement(self: *Self, value: anytype) Error!Ok {
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .first) catch return Error.Io;
                self.state = .rest;
                try getty.serialize(value, self.ser.serializer());
                self.ser.formatter.endArrayValue(self.ser.writer) catch return Error.Io;
            }

            fn end(self: *Self) Error!Ok {
                switch (self.state) {
                    .empty => {},
                    else => self.ser.formatter.endArray(self.ser.writer) catch return Error.Io,
                }
            }
        };

        /// Implements `getty.ser.StructSerialize`.
        pub usingnamespace getty.ser.StructSerialize(
            *Self,
            Ok,
            Error,
            _ST.serializeField,
            _ST.end,
        );

        const _ST = struct {
            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Error!void {
                const m = self.mapSerialize();
                try m.serializeEntry(key, value);
            }

            fn end(self: *Self) Error!Ok {
                const m = self.mapSerialize();
                try m.end();
            }
        };

        /// Implements `getty.ser.TupleSerialize`.
        pub usingnamespace getty.ser.TupleSerialize(
            *Self,
            Ok,
            Error,
            _SE.serializeElement,
            _SE.end,
        );
    };
}
