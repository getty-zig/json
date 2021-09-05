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
            _S.Ok,
            _S.Error,
            _S.Map,
            _S.Sequence,
            _S.Struct,
            _S.Tuple,
            _S.serializeBool,
            _S.serializeEnum,
            _S.serializeFloat,
            _S.serializeInt,
            _S.serializeMap,
            _S.serializeNull,
            _S.serializeSequence,
            _S.serializeString,
            _S.serializeStruct,
            _S.serializeTuple,
            _S.serializeNull,
        );

        const _S = struct {
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

            const Map = Access(Self, Ok, Error);
            const Sequence = Access(Self, Ok, Error);
            const Struct = Access(Self, Ok, Error);
            const Tuple = Access(Self, Ok, Error);

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

            fn serializeSequence(self: *Self, length: ?usize) Error!Sequence {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endArray(self.writer) catch return Error.Io;
                        return Sequence{ .ser = self, .state = .empty };
                    }
                }

                return Sequence{ .ser = self, .state = .first };
            }

            fn serializeString(self: *Self, value: anytype) Error!Ok {
                self.formatter.beginString(self.writer) catch return Error.Io;
                formatEscapedString(self.writer, self.formatter, value) catch return Error.Io;
                self.formatter.endString(self.writer) catch return Error.Io;
            }

            fn serializeStruct(self: *Self, name: []const u8, length: usize) Error!Struct {
                _ = name;

                return serializeMap(self, length);
            }

            fn serializeTuple(self: *Self, length: ?usize) Error!Tuple {
                return serializeSequence(self, length);
            }
        };
    };
}

fn Access(S: anytype, comptime Ok: type, comptime Error: type) type {
    return struct {
        ser: *S,
        state: enum {
            empty,
            first,
            rest,
        },

        const Self = @This();

        /// Implements `getty.ser.Map`.
        pub usingnamespace getty.ser.Map(
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
                getty.serialize(self.ser.serializer(), key) catch return Error.Io;
                self.ser.formatter.endObjectKey(self.ser.writer) catch return Error.Io;
            }

            fn serializeValue(self: *Self, value: anytype) Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return Error.Io;
                getty.serialize(self.ser.serializer(), value) catch return Error.Io;
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

        /// Implements `getty.ser.Sequence`.
        pub usingnamespace getty.ser.Sequence(
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
                getty.serialize(self.ser.serializer(), value) catch return Error.Io;
                self.ser.formatter.endArrayValue(self.ser.writer) catch return Error.Io;
            }

            fn end(self: *Self) Error!Ok {
                switch (self.state) {
                    .empty => {},
                    else => self.ser.formatter.endArray(self.ser.writer) catch return Error.Io,
                }
            }
        };

        /// Implements `getty.ser.Struct`.
        pub usingnamespace getty.ser.Structure(
            *Self,
            Ok,
            Error,
            _ST.serializeField,
            _ST.end,
        );

        const _ST = struct {
            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Error!void {
                const m = self.map();
                try m.serializeEntry(key, value);
            }

            fn end(self: *Self) Error!Ok {
                const m = self.map();
                try m.end();
            }
        };

        /// Implements `getty.ser.Sequence`.
        pub usingnamespace getty.ser.Tuple(
            *Self,
            Ok,
            Error,
            _SE.serializeElement,
            _SE.end,
        );
    };
}
