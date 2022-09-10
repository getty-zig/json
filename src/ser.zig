const getty = @import("getty");
const std = @import("std");

pub const ser = struct {
    pub usingnamespace @import("ser/serializer.zig");

    pub usingnamespace @import("ser/interface/formatter.zig");

    pub usingnamespace @import("ser/impl/formatter/compact.zig");
    pub usingnamespace @import("ser/impl/formatter/pretty.zig");
};

/// Serialize the given value as JSON into the given I/O stream with the given
/// `getty.Ser` interface value.
pub fn toWriterWith(value: anytype, writer: anytype, comptime user_sbt: anytype) !void {
    comptime concepts.@"std.io.Writer"(@TypeOf(writer));

    const F = ser.CompactFormatter(@TypeOf(writer));
    var f = F{};
    const S = ser.Serializer(@TypeOf(writer), @TypeOf(f.formatter()), user_sbt);
    var s = S.init(writer, f.formatter());

    try getty.serialize(value, s.serializer());
}

/// Serialize the given value as pretty-printed JSON into the given I/O stream
/// with the given `getty.Ser` interface value.
pub fn toPrettyWriterWith(value: anytype, writer: anytype, comptime user_sbt: anytype) !void {
    comptime concepts.@"std.io.Writer"(@TypeOf(writer));

    const F = ser.PrettyFormatter(@TypeOf(writer));
    var f = F.init();
    const S = ser.Serializer(@TypeOf(writer), @TypeOf(f.formatter()), user_sbt);
    var s = S.init(writer, f.formatter());

    try getty.serialize(value, s.serializer());
}

/// Serialize the given value as JSON into the given I/O stream.
pub fn toWriter(value: anytype, writer: anytype) !void {
    return try toWriterWith(value, writer, getty.default_st);
}

/// Serialize the given value as pretty-printed JSON into the given I/O stream.
pub fn toPrettyWriter(value: anytype, writer: anytype) !void {
    return try toPrettyWriterWith(value, writer, getty.default_st);
}

/// Serialize the given value as a JSON string.
///
/// The serialized string is an owned slice. The caller is responsible for
/// freeing the returned memory.
pub fn toSlice(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 128);
    errdefer list.deinit();

    try toWriter(value, list.writer());
    return list.toOwnedSlice();
}

/// Serialize the given value as a pretty-printed JSON string.
///
/// The serialized string is an owned slice. The caller is responsible for
/// freeing the returned memory.
pub fn toPrettySlice(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 128);
    errdefer list.deinit();

    try toPrettyWriter(value, list.writer());
    return list.toOwnedSlice();
}

/// Serialize the given value as a JSON string with the given `getty.Ser`
/// interface value.
///
/// The serialized string is an owned slice. The caller is responsible for
/// freeing the returned memory.
pub fn toSliceWith(allocator: std.mem.Allocator, value: anytype, comptime user_sbt: anytype) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 128);
    errdefer list.deinit();

    try toWriterWith(value, list.writer(), user_sbt);
    return list.toOwnedSlice();
}

/// Serialize the given value as a pretty-printed JSON string with the given
/// `getty.Ser` interface value.
///
/// The serialized string is an owned slice. The caller is responsible for
/// freeing the returned memory.
pub fn toPrettySliceWith(allocator: std.mem.Allocator, value: anytype, comptime user_sbt: anytype) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 128);
    errdefer list.deinit();

    try toPrettyWriterWith(value, list.writer(), user_sbt);
    return list.toOwnedSlice();
}

const concepts = struct {
    fn @"std.io.Writer"(comptime T: type) void {
        const err = "expected `std.io.Writer` interface value, found `" ++ @typeName(T) ++ "`";

        comptime {
            // Invariants
            if (!std.meta.trait.isContainer(T)) {
                @compileError(err);
            }

            // Constraints
            const has_name = std.mem.startsWith(u8, @typeName(T), "io.writer.Writer");
            const has_field = std.meta.trait.hasField("context")(T);
            const has_decl = @hasDecl(T, "Error");
            const has_funcs = std.meta.trait.hasFunctions(T, .{
                "write",
                "writeAll",
                "print",
                "writeByte",
                "writeByteNTimes",
                "writeIntNative",
                "writeIntForeign",
                "writeIntLittle",
                "writeIntBig",
                "writeInt",
                "writeStruct",
            });

            if (!(has_name and has_field and has_decl and has_funcs)) {
                @compileError(err);
            }
        }
    }
};

test "toWriter - Array" {
    try t(.compact, [_]i8{}, "[]");
    try t(.compact, [_]i8{1}, "[1]");
    try t(.compact, [_]i8{ 1, 2, 3, 4 }, "[1,2,3,4]");

    const T = struct { x: i32 };
    try t(.compact, [_]T{ T{ .x = 10 }, T{ .x = 100 }, T{ .x = 1000 } }, "[{\"x\":10},{\"x\":100},{\"x\":1000}]");
}

test "toWriter - ArrayList" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    try t(.compact, list, "[1,2,3]");
}

test "toWriter - AutoHashMap" {
    var map = std.AutoHashMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    try map.put(1, 10);
    try map.put(-1, -10);

    try t(.compact, map, "{\"1\":10,\"-1\":-10}");
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
    try t(.compact, 1, "1");
    try t(.compact, -1, "-1");

    try t(.compact, std.math.maxInt(u8), "255");
    try t(.compact, std.math.maxInt(u32), "4294967295");
    try t(.compact, std.math.maxInt(u64), "18446744073709551615");
    try t(.compact, std.math.maxInt(u128), "340282366920938463463374607431768211455");

    try t(.compact, std.math.maxInt(i8), "127");
    try t(.compact, std.math.maxInt(i32), "2147483647");
    try t(.compact, std.math.maxInt(i64), "9223372036854775807");
    try t(.compact, std.math.maxInt(i128), "170141183460469231731687303715884105727");
    try t(.compact, std.math.minInt(i8) + 1, "-127");
    try t(.compact, std.math.minInt(i32) + 1, "-2147483647");
    try t(.compact, std.math.minInt(i64) + 1, "-9223372036854775807");
    try t(.compact, std.math.minInt(i128) + 1, "-170141183460469231731687303715884105727");
    try t(.compact, std.math.minInt(i8), "-128");
    try t(.compact, std.math.minInt(i32), "-2147483648");
    try t(.compact, std.math.minInt(i64), "-9223372036854775808");
    try t(.compact, std.math.minInt(i128), "-170141183460469231731687303715884105728");
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
    {
        // Basic strings
        try t(.compact, "string", "\"string\"");
    }

    {
        // Control characters
        try t(.compact, "\"", "\"\\\"\"");
        try t(.compact, "\\", "\"\\\\\"");
        try t(.compact, "\x08", "\"\\b\"");
        try t(.compact, "\t", "\"\\t\"");
        try t(.compact, "\n", "\"\\n\"");
        try t(.compact, "\x0C", "\"\\f\"");
        try t(.compact, "\r", "\"\\r\"");

        try t(.compact, "\u{0}", "\"\\u0000\"");
        try t(.compact, "\u{1F}", "\"\\u001f\"");
        try t(.compact, "\u{7F}", "\"\\u007f\"");
        try t(.compact, "\u{2028}", "\"\\u2028\"");
        try t(.compact, "\u{2029}", "\"\\u2029\"");
    }

    {
        // Basic Multilingual Plane
        try t(.compact, "\u{FF}", "\"\u{FF}\"");
        try t(.compact, "\u{100}", "\"\u{100}\"");
        try t(.compact, "\u{800}", "\"\u{800}\"");
        try t(.compact, "\u{8000}", "\"\u{8000}\"");
        try t(.compact, "\u{D799}", "\"\u{D799}\"");
    }

    {
        // Non-Basic Multilingual Plane
        try t(.compact, "\u{10000}", "\"\\ud800\\udc00\"");
        try t(.compact, "\u{10FFFF}", "\"\\udbff\\udfff\"");
        try t(.compact, "😁", "\"\\ud83d\\ude01\"");
        try t(.compact, "😂", "\"\\ud83d\\ude02\"");

        try t(.compact, "hello😁", "\"hello\\ud83d\\ude01\"");
        try t(.compact, "hello😁world😂", "\"hello\\ud83d\\ude01world\\ud83d\\ude02\"");
    }
}

test "toWriter - StringHashMap" {
    var map = std.StringHashMap(i32).init(std.testing.allocator);
    defer map.deinit();

    try map.put("x", 1);
    try map.put("y", 2);

    try t(.compact, map, "{\"x\":1,\"y\":2}");
}

test "toWriter - Struct" {
    try t(.compact, struct {}{}, "{}");
    try t(.compact, struct { x: void }{ .x = {} }, "{}");
    try t(
        .compact,
        struct { x: i32, y: i32, z: struct { x: bool, y: [3]i8 } }{
            .x = 1,
            .y = 2,
            .z = .{ .x = true, .y = .{ 1, 2, 3 } },
        },
        "{\"x\":1,\"y\":2,\"z\":{\"x\":true,\"y\":[1,2,3]}}",
    );
}

test "toWriter - Tuple" {
    try t(.compact, .{ 1, true, "ring" }, "[1,true,\"ring\"]");
}

test "toWriter - Tagged Union" {
    try t(
        .compact,
        union(enum) { Foo: i32, Bar: bool }{ .Foo = 42 },
        "{\"Foo\":42}",
    );
}

test "toWriter - Vector" {
    try t(.compact, @splat(2, @as(u32, 1)), "[1,1]");
}

test "toWriter - Void" {
    try t(.compact, {}, "null");
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

const Format = enum { compact, pretty };

fn t(format: Format, value: anytype, expected: []const u8) !void {
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
                std.log.warn("\n" ++
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
                std.log.warn("\n" ++
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

    try switch (format) {
        .compact => toWriter(value, w.writer()),
        .pretty => toPrettyWriter(value, w.writer()),
    };

    if (w.remaining.len > 0) {
        return error.NotEnoughData;
    }
}
