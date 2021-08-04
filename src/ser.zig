const getty = @import("getty");
const std = @import("std");

const formatEscapedString = @import("formatter.zig").formatEscapedString;
const CompactFormatter = @import("formatters/compact.zig").Formatter;

pub fn Serializer(comptime W: type, comptime F: type) type {
    return struct {
        writer: W,
        formatter: F,

        const Self = @This();

        const Ok = void;
        const Error = error{
            /// Failure to read or write bytes on an IO stream.
            Io,

            /// Input was not syntactically valid JSON.
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

        const Map = _Map(W, F);
        const Sequence = _Map(W, F);
        const Struct = _Map(W, F);
        const Tuple = _Map(W, F);

        pub fn init(writer: anytype, formatter: anytype) Self {
            return .{
                .writer = writer,
                .formatter = formatter,
            };
        }

        /// Implements `getty.ser.Serializer`.
        pub fn serializer(self: *Self) S {
            return .{ .context = self };
        }

        const S = getty.ser.Serializer(
            *Self,
            Ok,
            Error,
            Map,
            Sequence,
            Struct,
            Tuple,
            _S.serializeBool,
            _S.serializeFloat,
            _S.serializeInt,
            _S.serializeNull,
            _S.serializeSequence,
            _S.serializeString,
            _S.serializeMap,
            _S.serializeStruct,
            _S.serializeTuple,
            _S.serializeVariant,
        );

        const _S = struct {
            fn serializeBool(self: *Self, value: bool) Error!Ok {
                self.formatter.writeBool(self.writer, value) catch return Error.Io;
            }

            fn serializeInt(self: *Self, value: anytype) Error!Ok {
                self.formatter.writeInt(self.writer, value) catch return Error.Io;
            }

            fn serializeFloat(self: *Self, value: anytype) Error!Ok {
                if (@TypeOf(value) != comptime_float and (std.math.isNan(value) or std.math.isInf(value))) {
                    self.formatter.writeNull(self.writer) catch return Error.Io;
                } else {
                    self.formatter.writeFloat(self.writer, value) catch return Error.Io;
                }
            }

            fn serializeNull(self: *Self) Error!Ok {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            }

            fn serializeSequence(self: *Self, length: ?usize) Error!Sequence {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endArray(self.writer) catch return Error.Io;
                        return Sequence{ .ser = self, .state = .Empty };
                    }
                }

                return Sequence{ .ser = self, .state = .First };
            }

            fn serializeString(self: *Self, value: anytype) Error!Ok {
                self.formatter.beginString(self.writer) catch return Error.Io;
                formatEscapedString(self.writer, self.formatter, value) catch return Error.Io;
                self.formatter.endString(self.writer) catch return Error.Io;
            }

            fn serializeMap(self: *Self, length: ?usize) Error!Map {
                self.formatter.beginObject(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endObject(self.writer) catch return Error.Io;
                        return Map{ .ser = self, .state = .Empty };
                    }
                }

                return Map{ .ser = self, .state = .First };
            }

            fn serializeStruct(self: *Self, name: []const u8, length: usize) Error!Struct {
                _ = name;

                return serializeMap(self, length);
            }

            fn serializeTuple(self: *Self, length: ?usize) Error!Tuple {
                return serializeSequence(self, length);
            }

            fn serializeVariant(self: *Self, value: anytype) Error!Ok {
                serializeString(self, @tagName(value)) catch return Error.Io;
            }
        };
    };
}

const State = enum {
    Empty,
    First,
    Rest,
};

fn _Map(comptime W: type, comptime F: type) type {
    const S = Serializer(W, F);

    return struct {
        ser: *S,
        state: State,

        const Self = @This();

        /// Implements `getty.ser.Map`.
        pub fn map(self: *Self) M {
            return .{ .context = self };
        }

        const M = getty.ser.Map(
            *Self,
            S.Ok,
            S.Error,
            _M.serializeKey,
            _M.serializeValue,
            _M.serializeEntry,
            _M.end,
        );

        const _M = struct {
            fn serializeKey(self: *Self, key: anytype) S.Error!void {
                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .First) catch return S.Error.Io;
                self.state = .Rest;
                // TODO: serde-json passes in a MapKeySerializer here instead
                // of self. This works though, so should we change it?
                getty.ser.serialize(&self.ser.serializer(), key) catch return S.Error.Io;
                self.ser.formatter.endObjectKey(self.ser.writer) catch return S.Error.Io;
            }

            fn serializeValue(self: *Self, value: anytype) S.Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return S.Error.Io;
                getty.ser.serialize(&self.ser.serializer(), value) catch return S.Error.Io;
                self.ser.formatter.endObjectValue(self.ser.writer) catch return S.Error.Io;
            }

            fn serializeEntry(self: *Self, key: anytype, value: anytype) S.Error!void {
                try serializeKey(self, key);
                try serializeValue(self, value);
            }

            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .Empty => {},
                    else => self.ser.formatter.endObject(self.ser.writer) catch return S.Error.Io,
                }
            }
        };

        /// Implements `getty.ser.Sequence`.
        pub fn sequence(self: *Self) SE {
            return .{ .context = self };
        }

        const SE = getty.ser.Sequence(
            *Self,
            S.Ok,
            S.Error,
            _SE.serializeElement,
            _SE.end,
        );

        const _SE = struct {
            fn serializeElement(self: *Self, value: anytype) S.Error!S.Ok {
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .First) catch return S.Error.Io;
                self.state = .Rest;
                getty.ser.serialize(&self.ser.serializer(), value) catch return S.Error.Io;
                self.ser.formatter.endArrayValue(self.ser.writer) catch return S.Error.Io;
            }

            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .Empty => {},
                    else => self.ser.formatter.endArray(self.ser.writer) catch return S.Error.Io,
                }
            }
        };

        /// Implements `getty.ser.Struct`.
        pub fn structure(self: *Self) ST {
            return .{ .context = self };
        }

        const ST = getty.ser.Structure(
            *Self,
            S.Ok,
            S.Error,
            _ST.serializeField,
            _ST.end,
        );

        const _ST = struct {
            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) S.Error!void {
                const m = self.map();
                try m.serializeEntry(key, value);
            }

            fn end(self: *Self) S.Error!S.Ok {
                const m = self.map();
                try m.end();
            }
        };

        /// Implements `getty.ser.Sequence`.
        pub fn tuple(self: *Self) T {
            return .{ .context = self };
        }

        const T = getty.ser.Tuple(
            *Self,
            S.Ok,
            S.Error,
            _SE.serializeElement,
            _SE.end,
        );
    };
}

/// Serializes a value using the JSON serializer into a provided writer.
pub fn toWriter(writer: anytype, value: anytype) !void {
    var formatter = CompactFormatter(@TypeOf(writer)){};
    const f = formatter.formatter();

    var serializer = Serializer(@TypeOf(writer), @TypeOf(f)).init(writer, f);
    const s = serializer.serializer();

    try getty.ser.serialize(&s, value);
}

/// Returns an owned slice of a serialized JSON string.
///
/// The caller is responsible for freeing the returned memory.
pub fn toString(allocator: *std.mem.Allocator, value: anytype) ![]const u8 {
    var array_list = std.ArrayList(u8).init(allocator);
    errdefer array_list.deinit();

    try toWriter(array_list.writer(), value);
    return array_list.toOwnedSlice();
}

test "toWriter - Array" {
    try t([_]i8{}, "[]");
    try t([_]i8{1}, "[1]");
    try t([_]i8{ 1, 2 }, "[1,2]");
}

test "toWriter - Bool" {
    try t(true, "true");
    try t(false, "false");
}

test "toWriter - Enum" {
    try t(enum { Foo }.Foo, "\"Foo\"");
    try t(.Foo, "\"Foo\"");
}

test "toWriter - Integer" {
    try t('A', "65");
    try t(std.math.maxInt(u32), "4294967295");
    try t(std.math.maxInt(u64), "18446744073709551615");
    try t(std.math.minInt(i32), "-2147483648");
    try t(std.math.maxInt(i64), "9223372036854775807");
}

test "toWriter - Float" {
    try t(1.0, "1");
    try t(3.1415, "3.1415");
    try t(-1.0, "-1");
    try t(0.0, "0");
}

test "toWriter - Null" {
    try t(null, "null");
}

test "toWriter - String" {
    try t("Foobar", "\"Foobar\"");
}

test "toWriter - Struct" {
    const T = struct { x: i32, y: i32, z: struct { x: bool, y: [3]i8 } };

    try t(struct {}{}, "{}");
    try t(T{
        .x = 1,
        .y = 2,
        .z = .{ .x = true, .y = .{ 1, 2, 3 } },
    }, "{\"x\":1,\"y\":2,\"z\":{\"x\":true,\"y\":[1,2,3]}}");
}

test "toWriter - Tuple" {
    try t(.{ 1, true, "hello" }, "[1,true,\"hello\"]");
}

fn t(input: anytype, output: []const u8) !void {
    var array_list = std.ArrayList(u8).init(std.testing.allocator);
    defer array_list.deinit();

    try toWriter(array_list.writer(), input);
    try std.testing.expectEqualSlices(u8, array_list.items, output);
}

comptime {
    std.testing.refAllDecls(@This());
}
