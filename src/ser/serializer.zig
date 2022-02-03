const getty = @import("getty");
const std = @import("std");

const escape = @import("impl/formatter/details/escape.zig").escape;

pub fn Serializer(comptime Writer: type, comptime Formatter: type, comptime Ser: type) type {
    comptime getty.concepts.@"getty.ser"(Ser);

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
            Ser,
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
        pub const serializer = struct {
            pub const Ok = void;
            pub const Error = getty.ser.Error || error{
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

            pub const MapSerialize = S;
            pub const SequenceSerialize = S;
            pub const StructSerialize = S;
            pub const TupleSerialize = S;

            pub fn serializeBool(self: *Self, value: bool) Error!Ok {
                self.formatter.writeBool(self.writer, value) catch return Error.Io;
            }

            pub fn serializeEnum(self: *Self, value: anytype) Error!Ok {
                serializeString(self, @tagName(value)) catch return Error.Io;
            }

            pub fn serializeFloat(self: *Self, value: anytype) Error!Ok {
                if (@TypeOf(value) != comptime_float and (std.math.isNan(value) or std.math.isInf(value))) {
                    self.formatter.writeNull(self.writer) catch return Error.Io;
                } else {
                    self.formatter.writeFloat(self.writer, value) catch return Error.Io;
                }
            }

            pub fn serializeInt(self: *Self, value: anytype) Error!Ok {
                self.formatter.writeInt(self.writer, value) catch return Error.Io;
            }

            pub fn serializeMap(self: *Self, length: ?usize) Error!MapSerialize {
                self.formatter.beginObject(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endObject(self.writer) catch return Error.Io;
                        return MapSerialize{ .ser = self, .state = .empty };
                    }
                }

                return MapSerialize{ .ser = self, .state = .first };
            }

            pub fn serializeNull(self: *Self) Error!Ok {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            }

            pub fn serializeSequence(self: *Self, length: ?usize) Error!SequenceSerialize {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endArray(self.writer) catch return Error.Io;
                        return SequenceSerialize{ .ser = self, .state = .empty };
                    }
                }

                return SequenceSerialize{ .ser = self, .state = .first };
            }

            pub fn serializeSome(self: *Self, value: anytype) Error!Ok {
                try getty.serialize(value, self.serializer());
            }

            pub fn serializeString(self: *Self, value: anytype) Error!Ok {
                if (!std.unicode.utf8ValidateSlice(value)) {
                    return Error.Syntax;
                }

                self.formatter.beginString(self.writer) catch return Error.Io;
                escape(value, self.writer, self.formatter) catch return Error.Syntax;
                self.formatter.endString(self.writer) catch return Error.Io;
            }

            pub fn serializeStruct(self: *Self, comptime name: []const u8, length: usize) Error!StructSerialize {
                _ = name;

                self.formatter.beginObject(self.writer) catch return Error.Io;

                if (length == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return StructSerialize{ .ser = self, .state = .empty };
                }

                return StructSerialize{ .ser = self, .state = .first };
            }

            pub fn serializeTuple(self: *Self, length: ?usize) Error!TupleSerialize {
                return serializeSequence(self, length);
            }
        };
    };
}

fn Serialize(comptime Ser: type) type {
    return struct {
        ser: *Ser,
        state: enum { empty, first, rest },

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
            impl.mapSerialize.end,
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
        pub const mapSerialize = struct {
            pub const Ok = @"impl Serializer"(Ser).serializer.Ok;
            pub const Error = @"impl Serializer"(Ser).serializer.Error;

            // TODO: serde-json passes in MapKeySerializer instead of self to
            // `getty.serialize`. This works though, so should we change it?
            pub fn serializeKey(self: *Self, key: anytype) Error!void {
                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .first) catch return Error.Io;
                try getty.serialize(key, self.ser.serializer());
                self.ser.formatter.endObjectKey(self.ser.writer) catch return Error.Io;

                self.state = .rest;
            }

            pub fn serializeValue(self: *Self, value: anytype) Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return Error.Io;
                try getty.serialize(value, self.ser.serializer());
                self.ser.formatter.endObjectValue(self.ser.writer) catch return Error.Io;
            }

            pub fn end(self: *Self) Error!Ok {
                if (self.state != .empty) {
                    self.ser.formatter.endObject(self.ser.writer) catch return Error.Io;
                }
            }
        };

        pub const sequenceSerialize = struct {
            pub const Ok = @"impl Serializer"(Ser).serializer.Ok;
            pub const Error = @"impl Serializer"(Ser).serializer.Error;

            pub fn serializeElement(self: *Self, value: anytype) Error!Ok {
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .first) catch return Error.Io;
                try getty.serialize(value, self.ser.serializer());
                self.ser.formatter.endArrayValue(self.ser.writer) catch return Error.Io;

                self.state = .rest;
            }

            pub fn end(self: *Self) Error!Ok {
                if (self.state != .empty) {
                    self.ser.formatter.endArray(self.ser.writer) catch return Error.Io;
                }
            }
        };

        pub const structSerialize = struct {
            pub const Ok = @"impl Serializer"(Ser).serializer.Ok;
            pub const Error = @"impl Serializer"(Ser).serializer.Error;

            pub fn serializeField(self: *Self, comptime key: []const u8, value: anytype) Error!void {
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

                try self.mapSerialize().serializeValue(value);

                self.state = .rest;
            }
        };
    };
}
