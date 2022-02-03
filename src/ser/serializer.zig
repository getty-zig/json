const getty = @import("getty");
const std = @import("std");

const escape = @import("impl/formatter/details/escape.zig").escape;

pub fn Serializer(comptime Writer: type, comptime Formatter: type, comptime with: ?type) type {
    comptime {
        if (with) |w| getty.concepts.@"getty.with"(w);
    }

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
            impl.@"getty.Serializer".Ok,
            impl.@"getty.Serializer".Error,
            with,
            impl.@"getty.Serializer".Map,
            impl.@"getty.Serializer".Seq,
            impl.@"getty.Serializer".Structure,
            impl.@"getty.Serializer".Tuple,
            impl.@"getty.Serializer".serializeBool,
            impl.@"getty.Serializer".serializeEnum,
            impl.@"getty.Serializer".serializeFloat,
            impl.@"getty.Serializer".serializeInt,
            impl.@"getty.Serializer".serializeMap,
            impl.@"getty.Serializer".serializeNull,
            impl.@"getty.Serializer".serializeSequence,
            impl.@"getty.Serializer".serializeSome,
            impl.@"getty.Serializer".serializeString,
            impl.@"getty.Serializer".serializeStruct,
            impl.@"getty.Serializer".serializeTuple,
            impl.@"getty.Serializer".serializeNull,
        );
    };
}

fn @"impl Serializer"(comptime Self: type) type {
    const S = Serialize(Self);

    return struct {
        pub const @"getty.Serializer" = struct {
            pub const Ok = void;
            pub const Error = std.mem.Allocator.Error || error{
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

            pub const Map = S;
            pub const Seq = S;
            pub const Structure = S;
            pub const Tuple = S;

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

            pub fn serializeMap(self: *Self, length: ?usize) Error!Map {
                self.formatter.beginObject(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endObject(self.writer) catch return Error.Io;
                        return Map{ .ser = self, .state = .empty };
                    }
                }

                return Map{ .ser = self, .state = .first };
            }

            pub fn serializeNull(self: *Self) Error!Ok {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            }

            pub fn serializeSequence(self: *Self, length: ?usize) Error!Seq {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endArray(self.writer) catch return Error.Io;
                        return Seq{ .ser = self, .state = .empty };
                    }
                }

                return Seq{ .ser = self, .state = .first };
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

            pub fn serializeStruct(self: *Self, comptime name: []const u8, length: usize) Error!Structure {
                _ = name;

                self.formatter.beginObject(self.writer) catch return Error.Io;

                if (length == 0) {
                    self.formatter.endObject(self.writer) catch return Error.Io;
                    return Structure{ .ser = self, .state = .empty };
                }

                return Structure{ .ser = self, .state = .first };
            }

            pub fn serializeTuple(self: *Self, length: ?usize) Error!Tuple {
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

        pub usingnamespace getty.ser.Map(
            *Self,
            impl.@"getty.ser.Map".Ok,
            impl.@"getty.ser.Map".Error,
            impl.@"getty.ser.Map".serializeKey,
            impl.@"getty.ser.Map".serializeValue,
            impl.@"getty.ser.Map".end,
        );

        pub usingnamespace getty.ser.Seq(
            *Self,
            impl.@"getty.ser.Seq".Ok,
            impl.@"getty.ser.Seq".Error,
            impl.@"getty.ser.Seq".serializeElement,
            impl.@"getty.ser.Seq".end,
        );

        pub usingnamespace getty.ser.Structure(
            *Self,
            impl.@"getty.ser.Structure".Ok,
            impl.@"getty.ser.Structure".Error,
            impl.@"getty.ser.Structure".serializeField,
            impl.@"getty.ser.Map".end,
        );

        pub usingnamespace getty.ser.Tuple(
            *Self,
            impl.@"getty.ser.Seq".Ok,
            impl.@"getty.ser.Seq".Error,
            impl.@"getty.ser.Seq".serializeElement,
            impl.@"getty.ser.Seq".end,
        );
    };
}

fn @"impl Serialize"(comptime Ser: type) type {
    const Self = Serialize(Ser);

    return struct {
        pub const @"getty.ser.Map" = struct {
            pub const Ok = @"impl Serializer"(Ser).@"getty.Serializer".Ok;
            pub const Error = @"impl Serializer"(Ser).@"getty.Serializer".Error;

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

        pub const @"getty.ser.Seq" = struct {
            pub const Ok = @"impl Serializer"(Ser).@"getty.Serializer".Ok;
            pub const Error = @"impl Serializer"(Ser).@"getty.Serializer".Error;

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

        pub const @"getty.ser.Structure" = struct {
            pub const Ok = @"impl Serializer"(Ser).@"getty.Serializer".Ok;
            pub const Error = @"impl Serializer"(Ser).@"getty.Serializer".Error;

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

                try self.map().serializeValue(value);

                self.state = .rest;
            }
        };
    };
}
