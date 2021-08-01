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

        pub fn init(writer: anytype, formatter: anytype) Self {
            return .{
                .writer = writer,
                .formatter = formatter,
            };
        }

        pub fn map(self: *Self) Map(W, F) {
            return .{ .context = self };
        }

        pub fn sequence(self: *Self) Map(W, F) {
            return .{ .context = self };
        }

        pub fn structure(self: *Self) Map(W, F) {
            return .{ .context = self };
        }

        const S = getty.ser.Serializer(
            *Self,
            Ok,
            Error,
            Map(W, F),
            Map(W, F),
            Map(W, F),
            //Tuple,
            _S.serializeBool,
            _S.serializeFloat,
            _S.serializeInt,
            _S.serializeNull,
            _S.serializeSequence,
            _S.serializeString,
            _S.serializeMap,
            _S.serializeStruct,
            _S.serializeVariant,
        );

        pub fn serializer(self: *Self) S {
            return .{ .context = self };
        }

        const _S = struct {
            /// Implements `boolFn` for `getty.ser.Serializer`.
            fn serializeBool(self: *Self, value: bool) Error!Ok {
                self.formatter.writeBool(self.writer, value) catch return Error.Io;
            }

            /// Implements `intFn` for `getty.ser.Serializer`.
            fn serializeInt(self: *Self, value: anytype) Error!Ok {
                self.formatter.writeInt(self.writer, value) catch return Error.Io;
            }

            /// Implements `floatFn` for `getty.ser.self`.
            ///
            /// TODO: Handle Inf for comptime_floats.
            fn serializeFloat(self: *Self, value: anytype) Error!Ok {
                //if (std.math.isNan(value) or std.math.isInf(value)) {
                if (std.math.isNan(value)) {
                    self.formatter.writeNull(self.writer) catch return Error.Io;
                } else {
                    self.formatter.writeFloat(self.writer, value) catch return Error.Io;
                }
            }

            /// Implements `nullFn` for `getty.ser.self`.
            fn serializeNull(self: *Self) Error!Ok {
                self.formatter.writeNull(self.writer) catch return Error.Io;
            }

            /// Implements `sequenceFn` for `getty.ser.self`.
            fn serializeSequence(self: *Self, length: ?usize) Error!Map(W, F) {
                self.formatter.beginArray(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endArray(self.writer) catch return Error.Io;
                        return Map(W, F){ .ser = self, .state = .Empty };
                    }
                }

                return Map(W, F){ .ser = self, .state = .First };
            }

            /// Implements `stringFn` for `getty.ser.self`.
            fn serializeString(self: *Self, value: anytype) Error!Ok {
                self.formatter.beginString(self.writer) catch return Error.Io;
                formatEscapedString(self.writer, self.formatter, value) catch return Error.Io;
                self.formatter.endString(self.writer) catch return Error.Io;
            }

            /// Implements `mapFn` for `getty.ser.self`.
            fn serializeMap(self: *Self, length: ?usize) Error!Map(W, F) {
                self.formatter.beginObject(self.writer) catch return Error.Io;

                if (length) |l| {
                    if (l == 0) {
                        self.formatter.endObject(self.writer) catch return Error.Io;
                        return Map(W, F){ .ser = self, .state = .Empty };
                    }
                }

                return Map(W, F){ .ser = self, .state = .First };
            }

            /// Implements `structFn` for `getty.ser.self`.
            fn serializeStruct(self: *Self, name: []const u8, length: usize) Error!Map(W, F) {
                _ = name;

                return serializeMap(self, length);
            }

            /// Implements `variantFn` for `getty.ser.self`.
            fn serializeVariant(self: *Self, value: anytype) Error!Ok {
                serializeString(self, @tagName(value)) catch return Error.Io;
            }
        };
    };
}

pub const State = enum {
    Empty,
    First,
    Rest,
};

pub fn Map(comptime W: type, comptime F: type) type {
    const S = Serializer(W, F);

    return struct {
        ser: *S,
        state: State,

        const Self = @This();

        pub fn map(self: *Self) M {
            return .{ .context = self };
        }

        const M = getty.ser.SerializeMap(
            *Self,
            S.Ok,
            S.Error,
            _M.serializeKey,
            _M.serializeValue,
            _M.serializeEntry,
            _M.end,
        );

        const _M = struct {
            /// Implements `keyFn` for `getty.ser.SerializeMap`.
            fn serializeKey(self: *Self, key: anytype) S.Error!void {
                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .First) catch return S.Error.Io;
                self.state = .Rest;
                // TODO: serde-json passes in a MapKeySerializer here instead
                // of self. This works though, so should we change it?
                getty.ser.serialize(&self.ser.serializer(), key) catch return S.Error.Io;
                self.ser.formatter.endObjectKey(self.ser.writer) catch return S.Error.Io;
            }

            /// Implements `valueFn` for `getty.ser.SerializeMap`.
            fn serializeValue(self: *Self, value: anytype) S.Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return S.Error.Io;
                getty.ser.serialize(&self.ser.serializer(), value) catch return S.Error.Io;
                self.ser.formatter.endObjectValue(self.ser.writer) catch return S.Error.Io;
            }

            /// Implements `entryFn` for `getty.ser.SerializeMap`.
            fn serializeEntry(self: *Self, key: anytype, value: anytype) S.Error!void {
                try serializeKey(self, key);
                try serializeValue(self, value);
            }

            /// Implements `endFn` for `getty.ser.SerializeMap`.
            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .Empty => {},
                    else => self.ser.formatter.endObject(self.ser.writer) catch return S.Error.Io,
                }
            }
        };

        pub fn sequence(self: *Self) SE {
            return .{ .context = self };
        }

        const SE = getty.ser.SerializeSequence(
            *Self,
            S.Ok,
            S.Error,
            _SE.serializeElement,
            _SE.end,
        );

        const _SE = struct {
            /// Implements `elementFn` for `getty.ser.SerializeSequence`.
            fn serializeElement(self: *Self, value: anytype) S.Error!S.Ok {
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .First) catch return S.Error.Io;
                self.state = .Rest;
                getty.ser.serialize(&self.ser.serializer(), value) catch return S.Error.Io;
                self.ser.formatter.endArrayValue(self.ser.writer) catch return S.Error.Io;
            }

            /// Implements `endFn` for `getty.ser.SerializeSequence`.
            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .Empty => {},
                    else => self.ser.formatter.endArray(self.ser.writer) catch return S.Error.Io,
                }
            }
        };

        pub fn structure(self: *Self) ST {
            return .{ .context = self };
        }

        const ST = getty.ser.SerializeStruct(
            *Self,
            S.Ok,
            S.Error,
            _ST.serializeField,
            _ST.end,
        );

        const _ST = struct {
            /// Implements `fieldFn` for `getty.ser.SerializeStruct`.
            fn serializeField(self: *Self, comptime key: []const u8, value: anytype) S.Error!void {
                const m = self.map();
                try m.serializeEntry(key, value);
            }

            /// Implements `endFn` for `getty.ser.SerializeStruct`.
            fn end(self: *Self) S.Error!S.Ok {
                const m = self.map();
                try m.end();
            }
        };
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

fn t(input: anytype, output: []const u8) !void {
    var array_list = std.ArrayList(u8).init(std.testing.allocator);
    defer array_list.deinit();

    try toWriter(array_list.writer(), input);
    try std.testing.expectEqualSlices(u8, array_list.items, output);
}

comptime {
    std.testing.refAllDecls(@This());
}
