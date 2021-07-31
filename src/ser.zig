const getty = @import("getty");
const std = @import("std");

const formatEscapedString = @import("formatter.zig").formatEscapedString;
const CompactFormatter = @import("formatters/compact.zig").Formatter;

pub fn Serializer(comptime W: type, comptime F: type) type {
    return struct {
        writer: W,
        formatter: F,

        const Self = @This();

        pub fn init(writer: anytype, formatter: anytype) Self {
            return .{
                .writer = writer,
                .formatter = formatter,
            };
        }

        pub fn interface(self: *Self, comptime iface: []const u8) blk: {
            if (std.mem.eql(u8, iface, "map")) {
                break :blk Map(W, F);
            } else if (std.mem.eql(u8, iface, "serializer")) {
                const Impl = struct {
                    /// Implements `boolFn` for `getty.ser.Serializer`.
                    fn serializeBool(serializer: *Self, value: bool) Error!Ok {
                        serializer.formatter.writeBool(serializer.writer, value) catch return Error.Io;
                    }

                    /// Implements `intFn` for `getty.ser.Serializer`.
                    fn serializeInt(serializer: *Self, value: anytype) Error!Ok {
                        serializer.formatter.writeInt(serializer.writer, value) catch return Error.Io;
                    }

                    /// Implements `floatFn` for `getty.ser.Serializer`.
                    ///
                    /// TODO: Handle Inf for comptime_floats.
                    fn serializeFloat(serializer: *Self, value: anytype) Error!Ok {
                        //if (std.math.isNan(value) or std.math.isInf(value)) {
                        if (std.math.isNan(value)) {
                            serializer.formatter.writeNull(serializer.writer) catch return Error.Io;
                        } else {
                            serializer.formatter.writeFloat(serializer.writer, value) catch return Error.Io;
                        }
                    }

                    /// Implements `nullFn` for `getty.ser.Serializer`.
                    fn serializeNull(serializer: *Self) Error!Ok {
                        serializer.formatter.writeNull(serializer.writer) catch return Error.Io;
                    }

                    /// Implements `sequenceFn` for `getty.ser.Serializer`.
                    fn serializeSequence(serializer: *Self, length: ?usize) Error!Map(W, F) {
                        serializer.formatter.beginArray(serializer.writer) catch return Error.Io;

                        if (length) |l| {
                            if (l == 0) {
                                serializer.formatter.endArray(serializer.writer) catch return Error.Io;
                                return Map(W, F){ .ser = serializer, .state = .Empty };
                            }
                        }

                        return Map(W, F){ .ser = serializer, .state = .First };
                    }

                    /// Implements `stringFn` for `getty.ser.Serializer`.
                    fn serializeString(serializer: *Self, value: anytype) Error!Ok {
                        serializer.formatter.beginString(serializer.writer) catch return Error.Io;
                        formatEscapedString(serializer.writer, serializer.formatter, value) catch return Error.Io;
                        serializer.formatter.endString(serializer.writer) catch return Error.Io;
                    }

                    /// Implements `mapFn` for `getty.ser.Serializer`.
                    fn serializeMap(serializer: *Self, length: ?usize) Error!Map(W, F) {
                        serializer.formatter.beginObject(serializer.writer) catch return Error.Io;

                        if (length) |l| {
                            if (l == 0) {
                                serializer.formatter.endObject(serializer.writer) catch return Error.Io;
                                return Map(W, F){ .ser = serializer, .state = .Empty };
                            }
                        }

                        return Map(W, F){ .ser = serializer, .state = .First };
                    }

                    /// Implements `structFn` for `getty.ser.Serializer`.
                    fn serializeStruct(serializer: *Self, name: []const u8, length: usize) Error!Map(W, F) {
                        _ = name;

                        return serializeMap(serializer, length);
                    }

                    /// Implements `variantFn` for `getty.ser.Serializer`.
                    fn serializeVariant(serializer: *Self, value: anytype) Error!Ok {
                        serializeString(serializer, @tagName(value)) catch return Error.Io;
                    }
                };

                break :blk getty.ser.Serializer(
                    *Self,
                    Ok,
                    Error,
                    Map(W, F),
                    Map(W, F),
                    Map(W, F),
                    //Tuple,
                    Impl.serializeBool,
                    Impl.serializeFloat,
                    Impl.serializeInt,
                    Impl.serializeNull,
                    Impl.serializeSequence,
                    Impl.serializeString,
                    Impl.serializeMap,
                    Impl.serializeStruct,
                    Impl.serializeVariant,
                );
            } else if (std.mem.eql(u8, iface, "sequence")) {
                break :blk Map(W, F);
            } else if (std.mem.eql(u8, iface, "struct")) {
                break :blk Map(W, F);
            } else {
                @compileError("Unknown interface name");
            }
        } {
            return .{ .context = self };
        }

        pub const Ok = void;
        pub const Error = error{
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

        pub fn interface(self: *Self, comptime iface: []const u8) blk: {
            if (std.mem.eql(u8, iface, "map")) {
                const Impl = struct {
                    /// Implements `keyFn` for `getty.ser.SerializeMap`.
                    fn serializeKey(map: *Self, key: anytype) S.Error!void {
                        map.ser.formatter.beginObjectKey(map.ser.writer, map.state == .First) catch return S.Error.Io;
                        map.state = .Rest;
                        // TODO: serde-json passes in a MapKeySerializer here instead
                        // of map. This works though, so should we change it?
                        getty.ser.serialize(map.ser, key) catch return S.Error.Io;
                        map.ser.formatter.endObjectKey(map.ser.writer) catch return S.Error.Io;
                    }

                    /// Implements `valueFn` for `getty.ser.SerializeMap`.
                    fn serializeValue(map: *Self, value: anytype) S.Error!void {
                        map.ser.formatter.beginObjectValue(map.ser.writer) catch return S.Error.Io;
                        getty.ser.serialize(map.ser, value) catch return S.Error.Io;
                        map.ser.formatter.endObjectValue(map.ser.writer) catch return S.Error.Io;
                    }

                    /// Implements `entryFn` for `getty.ser.SerializeMap`.
                    fn serializeEntry(map: *Self, key: anytype, value: anytype) S.Error!void {
                        try serializeKey(map, key);
                        try serializeValue(map, value);
                    }

                    /// Implements `endFn` for `getty.ser.SerializeMap`.
                    fn end(map: *Self) S.Error!S.Ok {
                        switch (map.state) {
                            .Empty => {},
                            else => map.ser.formatter.endObject(map.ser.writer) catch return S.Error.Io,
                        }
                    }
                };

                break :blk getty.ser.SerializeMap(
                    *Self,
                    S.Ok,
                    S.Error,
                    Impl.serializeKey,
                    Impl.serializeValue,
                    Impl.serializeEntry,
                    Impl.end,
                );
            } else if (std.mem.eql(u8, iface, "sequence")) {
                const Impl = struct {
                    /// Implements `elementFn` for `getty.ser.SerializeSequence`.
                    fn serializeElement(seq: *Self, value: anytype) S.Error!S.Ok {
                        seq.ser.formatter.beginArrayValue(seq.ser.writer, seq.state == .First) catch return S.Error.Io;
                        seq.state = .Rest;
                        getty.ser.serialize(seq.ser, value) catch return S.Error.Io;
                        seq.ser.formatter.endArrayValue(seq.ser.writer) catch return S.Error.Io;
                    }

                    /// Implements `endFn` for `getty.ser.SerializeSequence`.
                    fn end(seq: *Self) S.Error!S.Ok {
                        switch (seq.state) {
                            .Empty => {},
                            else => seq.ser.formatter.endArray(seq.ser.writer) catch return S.Error.Io,
                        }
                    }
                };

                break :blk getty.ser.SerializeSequence(
                    *Self,
                    S.Ok,
                    S.Error,
                    Impl.serializeElement,
                    Impl.end,
                );
            } else if (std.mem.eql(u8, iface, "struct")) {
                const Impl = struct {
                    /// Implements `fieldFn` for `getty.ser.SerializeStruct`.
                    fn serializeField(s: *Self, comptime key: []const u8, value: anytype) S.Error!void {
                        const map = s.interface("map");
                        try map.serializeEntry(key, value);
                    }

                    /// Implements `endFn` for `getty.ser.SerializeStruct`.
                    fn end(s: *Self) S.Error!S.Ok {
                        const map = s.interface("map");
                        try map.end();
                    }
                };

                break :blk getty.ser.SerializeStruct(
                    *Self,
                    S.Ok,
                    S.Error,
                    Impl.serializeField,
                    Impl.end,
                );
            } else {
                @compileError("Unknown interface name");
            }
        } {
            return .{ .context = self };
        }
    };
}

/// Serializes a value using the JSON serializer into a provided writer.
pub fn toWriter(writer: anytype, value: anytype) !void {
    var cf = CompactFormatter(@TypeOf(writer)){};
    const f = cf.interface("formatter");
    var s = Serializer(@TypeOf(writer), @TypeOf(f)).init(writer, f);

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
