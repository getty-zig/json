const getty = @import("getty");
const std = @import("std");

const formatEscapedString = @import("formatter.zig").formatEscapedString;
const CompactFormatter = @import("formatters/compact.zig").Formatter;
const PrettyFormatter = @import("formatters/pretty.zig").Formatter;

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

        pub fn init(writer: W, formatter: F) Self {
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
            _S.serializeNull,
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

fn _Map(comptime W: type, comptime F: type) type {
    const S = Serializer(W, F);

    return struct {
        ser: *S,
        state: enum {
            empty,
            first,
            rest,
        },

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
                self.ser.formatter.beginObjectKey(self.ser.writer, self.state == .first) catch return S.Error.Io;
                self.state = .rest;
                // TODO: serde-json passes in a MapKeySerializer here instead
                // of self. This works though, so should we change it?
                getty.serialize(self.ser.serializer(), key) catch return S.Error.Io;
                self.ser.formatter.endObjectKey(self.ser.writer) catch return S.Error.Io;
            }

            fn serializeValue(self: *Self, value: anytype) S.Error!void {
                self.ser.formatter.beginObjectValue(self.ser.writer) catch return S.Error.Io;
                getty.serialize(self.ser.serializer(), value) catch return S.Error.Io;
                self.ser.formatter.endObjectValue(self.ser.writer) catch return S.Error.Io;
            }

            fn serializeEntry(self: *Self, key: anytype, value: anytype) S.Error!void {
                try serializeKey(self, key);
                try serializeValue(self, value);
            }

            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .empty => {},
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
                self.ser.formatter.beginArrayValue(self.ser.writer, self.state == .first) catch return S.Error.Io;
                self.state = .rest;
                getty.serialize(self.ser.serializer(), value) catch return S.Error.Io;
                self.ser.formatter.endArrayValue(self.ser.writer) catch return S.Error.Io;
            }

            fn end(self: *Self) S.Error!S.Ok {
                switch (self.state) {
                    .empty => {},
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

    try getty.serialize(s, value);
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

/// Serializes a value using the JSON serializer into a provided writer, using the pretty formatter.
pub fn toPrettyWriter(writer: anytype, value: anytype) !void {
    var formatter = PrettyFormatter(@TypeOf(writer)).init();
    const f = formatter.formatter();

    var serializer = Serializer(@TypeOf(writer), @TypeOf(f)).init(writer, f);
    const s = serializer.serializer();

    try getty.serialize(s, value);
}

/// Returns an owned slice of a serialized JSON string.
///
/// The caller is responsible for freeing the returned memory.
pub fn toPretty(allocator: *std.mem.Allocator, value: anytype) ![]const u8 {
    var array_list = std.ArrayList(u8).init(allocator);
    errdefer array_list.deinit();

    try toPrettyWriter(array_list.writer(), value);
    return array_list.toOwnedSlice();
}

test "toWriter - Array" {
    try t(.compact, [_]i8{}, "[]");
    try t(.compact, [_]i8{1}, "[1]");
    try t(.compact, [_]i8{ 1, 2, 3, 4 }, "[1,2,3,4]");

    const T = struct { x: i32 };
    try t(.compact, [_]T{ T{ .x = 10 }, T{ .x = 100 }, T{ .x = 1000 } }, "[{\"x\":10},{\"x\":100},{\"x\":1000}]");
}

test "toWriter - Bool" {
    try t(.compact, true, "true");
    try t(.compact, false, "false");
}

test "toWriter - Enum" {
    try t(.compact, enum { foo }.foo, "\"foo\"");
    try t(.compact, .foo, "\"foo\"");
}

test "toWriter - Error" {
    try t(.compact, error.Foobar, "\"Foobar\"");
}

test "toWriter - Integer" {
    try t(.compact, 'A', "65");
    try t(.compact, std.math.maxInt(u32), "4294967295");
    try t(.compact, std.math.maxInt(u64), "18446744073709551615");
    try t(.compact, std.math.minInt(i32), "-2147483648");
    try t(.compact, std.math.maxInt(i64), "9223372036854775807");
}

test "toWriter - Float" {
    try t(.compact, 0.0, "0.0e+00");
    try t(.compact, 1.0, "1.0e+00");
    try t(.compact, -1.0, "-1.0e+00");

    try t(.compact, @as(f32, 42.0), "4.2e+01");
    try t(.compact, @as(f64, 42.0), "4.2e+01");
}

test "toWriter - Null" {
    try t(.compact, null, "null");

    try t(.compact, @as(?u8, null), "null");
    try t(.compact, @as(?*u8, null), "null");
}

test "toWriter - String" {
    try t(.compact, "foobar", "\"foobar\"");
    try t(.compact, "with\nescapes\r", "\"with\\nescapes\\r\"");
    try t(.compact, "with unicode\u{1}", "\"with unicode\\u0001\"");
    try t(.compact, "with unicode\u{80}", "\"with unicode\u{80}\"");
    try t(.compact, "with unicode\u{FF}", "\"with unicode\u{FF}\"");
    try t(.compact, "with unicode\u{100}", "\"with unicode\u{100}\"");
    try t(.compact, "with unicode\u{800}", "\"with unicode\u{800}\"");
    try t(.compact, "with unicode\u{8000}", "\"with unicode\u{8000}\"");
    try t(.compact, "with unicode\u{D799}", "\"with unicode\u{D799}\"");
    try t(.compact, "with unicode\u{10000}", "\"with unicode\u{10000}\"");
    try t(.compact, "with unicode\u{10FFFF}", "\"with unicode\u{10FFFF}\"");
    try t(.compact, "/", "\"/\"");
}

test "toWriter - Struct" {
    try t(.compact, struct {}{}, "{}");
    try t(.compact, struct { x: void }{ .x = {} }, "{}");
    try t(
        .compact,
        struct { x: i32, y: i32, z: struct { x: bool, y: [3]i8 } }{ .x = 1, .y = 2, .z = .{ .x = true, .y = .{ 1, 2, 3 } } },
        "{\"x\":1,\"y\":2,\"z\":{\"x\":true,\"y\":[1,2,3]}}",
    );
}

test "toWriter - Tuple" {
    try t(.compact, .{ 1, true, "ring" }, "[1,true,\"ring\"]");
}

test "toWriter - Tagged Union" {
    try t(.compact, union(enum) { Foo: i32, Bar: bool }{ .Foo = 42 }, "42");
}

test "toWriter - Vector" {
    try t(.compact, @splat(2, @as(u32, 1)), "[1,1]");
}

test "toWriter - Void" {
    try t(.compact, {}, "null");
}

test "toWriter - ArrayList" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try t(.compact, list, "[1,2,3]");
}

test "toWriter - HashMap" {
    var map = std.StringHashMap(i32).init(std.testing.allocator);
    defer map.deinit();

    try map.put("x", 1);
    try map.put("y", 2);

    try t(.compact, map, "{\"x\":1,\"y\":2}");
}

test "toPrettyWriter - Struct" {
    try t(.pretty, struct {}{}, "{}");
    try t(.pretty, struct { x: i32, y: i32, z: struct { x: bool, y: [3]i8 } }{
        .x = 1,
        .y = 2,
        .z = .{ .x = true, .y = .{ 1, 2, 3 } },
    },
        \\{
        \\  "x": 1,
        \\  "y": 2,
        \\  "z": {
        \\    "x": true,
        \\    "y": [
        \\      1,
        \\      2,
        \\      3
        \\    ]
        \\  }
        \\}
    );
}

const Formatters = enum { compact, pretty };

fn t(formatter: Formatters, value: anytype, expected: []const u8) !void {
    const ValidationWriter = struct {
        remaining: []const u8,

        const Self = @This();

        pub const Error = error{
            TooMuchData,
            DifferentData,
        };

        fn init(s: []const u8) Self {
            return .{ .remaining = s };
        }

        /// Implements `std.io.Writer`.
        pub fn writer(self: *Self) std.io.Writer(*Self, Error, write) {
            return .{ .context = self };
        }

        fn write(self: *Self, bytes: []const u8) Error!usize {
            if (self.remaining.len < bytes.len) {
                std.debug.warn("\n" ++
                    \\======= expected: =======
                    \\{s}
                    \\======== found: =========
                    \\{s}
                    \\=========================
                , .{
                    self.remaining,
                    bytes,
                });
                return error.TooMuchData;
            }

            if (!std.mem.eql(u8, self.remaining[0..bytes.len], bytes)) {
                std.debug.warn("\n" ++
                    \\======= expected: =======
                    \\{s}
                    \\======== found: =========
                    \\{s}
                    \\=========================
                , .{
                    self.remaining[0..bytes.len],
                    bytes,
                });
                return error.DifferentData;
            }

            self.remaining = self.remaining[bytes.len..];

            return bytes.len;
        }
    };

    var w = ValidationWriter.init(expected);

    try switch (formatter) {
        .compact => toWriter(w.writer(), value),
        .pretty => toPrettyWriter(w.writer(), value),
    };

    if (w.remaining.len > 0) {
        return error.NotEnoughData;
    }
}

test {
    std.testing.refAllDecls(@This());
}
