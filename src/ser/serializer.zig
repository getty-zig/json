const getty = @import("getty");
const std = @import("std");

const ser = @import("../lib.zig").ser;

pub fn Serializer(comptime Writer: type, comptime Formatter: type) type {
    return struct {
        writer: Writer,
        formatter: Formatter,

        const Self = @This();
        const impl = @"impl Serializer"(Self);

        pub fn init(writer: Writer, formatter: Formatter) Self {
            return .{
                .writer = writer,
                .formatter = formatter,
            };
        }

        pub usingnamespace getty.Serializer(
            *Self,
            impl.serializer.Ok,
            impl.serializer.Error,
            impl.serializer.MapSerialize,
            impl.serializer.SequenceSerialize,
            impl.serializer.StructSerialize,
            impl.serializer.TupleSerialize,
            impl.serializer.serializeBool,
            impl.serializer.serializeEnum,
            impl.serializer.serializeFloat,
            impl.serializer.serializeInt,
            impl.serializer.serializeMap,
            impl.serializer.serializeNull,
            impl.serializer.serializeSequence,
            impl.serializer.serializeSome,
            impl.serializer.serializeString,
            impl.serializer.serializeStruct,
            impl.serializer.serializeTuple,
            impl.serializer.serializeNull,
        );
    };
}

fn @"impl Serializer"(comptime Self: type) type {
    const S = Serialize(Self);

    return struct {
        const serializer = struct {
            const Ok = void;
            const Error = getty.ser.Error || error{
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

            const MapSerialize = S;
            const SequenceSerialize = S;
            const StructSerialize = S;
            const TupleSerialize = S;

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

            fn serializeSome(self: *Self, value: anytype) Error!Ok {
                try getty.serialize(value, self.serializer());
            }

            fn serializeString(self: *Self, value: anytype) Error!Ok {
                if (!std.unicode.utf8ValidateSlice(value)) {
                    return Error.Syntax;
                }

                self.formatter.beginString(self.writer) catch return Error.Io;
                ser.escape(value, self.writer, self.formatter) catch return Error.Syntax;
                self.formatter.endString(self.writer) catch return Error.Io;
            }

            fn serializeStruct(self: *Self, name: []const u8, length: usize) Error!StructSerialize {
                _ = name;

                return serializeMap(self, length);
            }

            fn serializeTuple(self: *Self, length: ?usize) Error!TupleSerialize {
                return serializeSequence(self, length);
            }
        };
    };
}

fn Serialize(comptime Ser: type) type {
    return struct {
        ser: *Ser,
        state: enum {
            empty,
            first,
            rest,
        },

        const Self = @This();
        const impl = @"impl Serialize"(Ser);

        pub usingnamespace getty.ser.MapSerialize(
            *Self,
            impl.mapSerialize.Ok,
            impl.mapSerialize.Error,
            impl.mapSerialize.serializeKey,
            impl.mapSerialize.serializeValue,
            impl.mapSerialize.end,
        );

        pub usingnamespace getty.ser.SequenceSerialize(
            *Self,
            impl.sequenceSerialize.Ok,
            impl.sequenceSerialize.Error,
            impl.sequenceSerialize.serializeElement,
            impl.sequenceSerialize.end,
        );

        pub usingnamespace getty.ser.StructSerialize(
            *Self,
            impl.structSerialize.Ok,
            impl.structSerialize.Error,
            impl.structSerialize.serializeField,
            impl.structSerialize.end,
        );

        pub usingnamespace getty.ser.TupleSerialize(
            *Self,
            impl.sequenceSerialize.Ok,
            impl.sequenceSerialize.Error,
            impl.sequenceSerialize.serializeElement,
            impl.sequenceSerialize.end,
        );
    };
}

fn @"impl Serialize"(comptime Ser: type) type {
    const Self = Serialize(Ser);

    return struct {
        const mapSerialize = struct {
            const Ok = @"impl Serializer"(Ser).serializer.Ok;
            const Error = @"impl Serializer"(Ser).serializer.Error;

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

            fn end(self: *Self) Error!Ok {
                switch (self.state) {
                    .empty => {},
                    else => self.ser.formatter.endObject(self.ser.writer) catch return Error.Io,
                }
            }
        };

        const sequenceSerialize = struct {
            const Ok = @"impl Serializer"(Ser).serializer.Ok;
            const Error = @"impl Serializer"(Ser).serializer.Error;

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

        const structSerialize = struct {
            const Ok = @"impl Serializer"(Ser).serializer.Ok;
            const Error = @"impl Serializer"(Ser).serializer.Error;

            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Error!void {
                const m = self.mapSerialize();
                try m.serializeEntry(key, value);
            }

            fn end(self: *Self) Error!Ok {
                const m = self.mapSerialize();
                try m.end();
            }
        };
    };
}
