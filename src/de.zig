const getty = @import("getty");
const std = @import("std");

const eql = std.mem.eql;
const testing = std.testing;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;
const expectError = testing.expectError;

/// A JSON deserializer.
pub const Deserializer = @import("de/deserializer.zig").Deserializer;

/// Deserialization-specific types and functions.
pub const de = struct {
    /// Frees resources allocated by Getty during deserialization.
    pub fn free(
        /// A memory allocator.
        allocator: std.mem.Allocator,
        /// A value to deallocate.
        value: anytype,
        /// A deserialization block.
        comptime user_dbt: anytype,
    ) void {
        return getty.de.free(
            allocator,
            Deserializer(
                user_dbt,
                // TODO: wonk
                std.io.FixedBufferStream([]u8).Reader,
            ).@"getty.Deserializer",
            value,
        );
    }
};

/// Deserializes into a value of type `T` from the deserializer `d`.
pub fn fromDeserializer(comptime T: type, d: anytype) !T {
    const value = try getty.deserialize(d.allocator, T, d.deserializer());
    errdefer de.free(d.allocator, value, null);
    try d.end();

    return value;
}

pub fn fromReaderWith(allocator: std.mem.Allocator, comptime T: type, reader: anytype, comptime user_dbt: anytype) !T {
    var d = Deserializer(user_dbt, @TypeOf(reader)).init(allocator, reader);
    defer d.deinit();
    return fromDeserializer(T, &d);
}

pub fn fromReader(allocator: std.mem.Allocator, comptime T: type, reader: anytype) !T {
    return try fromReaderWith(allocator, T, reader, null);
}

/// Deserializes into a value of type `T` from a slice of JSON using a deserialization block or tuple.
pub fn fromSliceWith(allocator: std.mem.Allocator, comptime T: type, slice: []const u8, comptime user_dbt: anytype) !T {
    var fbs = std.io.fixedBufferStream(slice);
    return try fromReaderWith(allocator, T, fbs.reader(), user_dbt);
}

/// Deserializes into a value of type `T` from a slice of JSON.
pub fn fromSlice(allocator: std.mem.Allocator, comptime T: type, slice: []const u8) !T {
    return try fromSliceWith(allocator, T, slice, null);
}

test "array" {
    try expectEqual([0]bool{}, try fromSlice(testing.allocator, [0]bool, "[]"));
    try expectEqual([1]bool{true}, try fromSlice(testing.allocator, [1]bool, "[true]"));
    try expectEqual([2]bool{ true, false }, try fromSlice(testing.allocator, [2]bool, "[true,false]"));
    try expectEqual([5]i32{ 1, 2, 3, 4, 5 }, try fromSlice(testing.allocator, [5]i32, "[1,2,3,4,5]"));
    try expectEqual([2][1]i32{ .{1}, .{2} }, try fromSlice(testing.allocator, [2][1]i32, "[[1],[2]]"));
    try expectEqual([2][1][3]i32{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} }, try fromSlice(testing.allocator, [2][1][3]i32, "[[[1,2,3]],[[4,5,6]]]"));
}

test "array list" {
    // scalar child
    {
        const got = try fromSlice(testing.allocator, std.ArrayList(u8), "[1,2,3,4,5]");
        defer got.deinit();

        try expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, got.items);
    }

    // array list child
    {
        const got = try fromSlice(testing.allocator, std.ArrayList(std.ArrayList(u8)), "[[1, 2],[3,4]]");
        defer de.free(testing.allocator, got, null);

        try expectEqual(std.ArrayList(std.ArrayList(u8)), @TypeOf(got));
        try expectEqual(std.ArrayList(u8), @TypeOf(got.items[0]));
        try expectEqual(std.ArrayList(u8), @TypeOf(got.items[1]));
        try expectEqualSlices(u8, &.{ 1, 2 }, got.items[0].items);
        try expectEqualSlices(u8, &.{ 3, 4 }, got.items[1].items);
    }
}

test "std.AutoHashMap" {
    // scalar
    {
        var got = try fromSlice(testing.allocator, std.AutoHashMap(i32, []u8),
            \\{
            \\  "1": "foo",
            \\  "2": "bar",
            \\  "3": "baz"
            \\}
        );
        defer de.free(testing.allocator, got, null);

        try expectEqual(std.AutoHashMap(i32, []u8), @TypeOf(got));
        try expectEqual(@as(u32, 3), got.count());
        try expectEqualSlices(u8, "foo", got.get(1).?);
        try expectEqualSlices(u8, "bar", got.get(2).?);
        try expectEqualSlices(u8, "baz", got.get(3).?);
    }

    // nested
    {
        var got = try fromSlice(testing.allocator, std.AutoHashMap(i32, std.AutoHashMap(i32, []const u8)),
            \\{
            \\  "1": { "4": "foo" },
            \\  "2": { "5": "bar" },
            \\  "3": { "6": "baz" }
            \\}
        );
        defer de.free(testing.allocator, got, null);

        var a = std.AutoHashMap(i32, []const u8).init(testing.allocator);
        var b = std.AutoHashMap(i32, []const u8).init(testing.allocator);
        var c = std.AutoHashMap(i32, []const u8).init(testing.allocator);
        defer {
            a.deinit();
            b.deinit();
            c.deinit();
        }

        try a.put(4, "foo");
        try b.put(5, "bar");
        try c.put(6, "baz");

        try expectEqual(std.AutoHashMap(i32, std.AutoHashMap(i32, []const u8)), @TypeOf(got));
        try expectEqual(@as(u32, 3), got.count());
        try expectEqual(@TypeOf(a), @TypeOf(got.get(1).?));
        try expectEqual(@TypeOf(b), @TypeOf(got.get(2).?));
        try expectEqual(@TypeOf(c), @TypeOf(got.get(3).?));
        try expectEqualSlices(u8, a.get(4).?, got.get(1).?.get(4).?);
        try expectEqualSlices(u8, b.get(5).?, got.get(2).?.get(5).?);
        try expectEqualSlices(u8, c.get(6).?, got.get(3).?.get(6).?);
    }
}

test "std.StringHashMap" {
    // stack child
    {
        var got = try fromSlice(testing.allocator, std.StringHashMap(u8),
            \\{
            \\  "\"a": 1,
            \\  "b": 2,
            \\  "c": 3
            \\}
        );
        defer de.free(testing.allocator, got, null);

        try expectEqual(std.StringHashMap(u8), @TypeOf(got));
        try expectEqual(@as(u32, 3), got.count());
        try expectEqual(@as(u8, 1), got.get("\"a").?);
        try expectEqual(@as(u8, 2), got.get("b").?);
        try expectEqual(@as(u8, 3), got.get("c").?);
    }

    // heap child
    {
        var got = try fromSlice(testing.allocator, std.StringHashMap([]u8),
            \\{
            \\  "\"a": "foo",
            \\  "b": "bar",
            \\  "c": "baz"
            \\}
        );
        defer de.free(testing.allocator, got, null);

        try expectEqual(std.StringHashMap([]u8), @TypeOf(got));
        try expectEqual(@as(u32, 3), got.count());
        try expectEqualSlices(u8, "foo", got.get("\"a").?);
        try expectEqualSlices(u8, "bar", got.get("b").?);
        try expectEqualSlices(u8, "baz", got.get("c").?);
    }

    // nested child
    {
        var got = try fromSlice(testing.allocator, std.StringHashMap(std.StringHashMap([]const u8)),
            \\{
            \\  "\"a": { "\"d": "foo" },
            \\  "b": { "e": "bar" },
            \\  "c": { "f": "baz" }
            \\}
        );
        defer de.free(testing.allocator, got, null);

        var a = std.StringHashMap([]const u8).init(testing.allocator);
        var b = std.StringHashMap([]const u8).init(testing.allocator);
        var c = std.StringHashMap([]const u8).init(testing.allocator);
        defer {
            a.deinit();
            b.deinit();
            c.deinit();
        }

        try a.put("\"d", "foo");
        try b.put("e", "bar");
        try c.put("f", "baz");

        try expectEqual(std.StringHashMap(std.StringHashMap([]const u8)), @TypeOf(got));
        try expectEqual(@as(u32, 3), got.count());
        try expectEqual(@TypeOf(a), @TypeOf(got.get("\"a").?));
        try expectEqual(@TypeOf(b), @TypeOf(got.get("b").?));
        try expectEqual(@TypeOf(c), @TypeOf(got.get("c").?));
        try expectEqualSlices(u8, a.get("\"d").?, got.get("\"a").?.get("\"d").?);
        try expectEqualSlices(u8, b.get("e").?, got.get("b").?.get("e").?);
        try expectEqualSlices(u8, c.get("f").?, got.get("c").?.get("f").?);
    }
}

test "bool" {
    try expectEqual(true, try fromSlice(testing.allocator, bool, "true"));
    try expectEqual(false, try fromSlice(testing.allocator, bool, "false"));
}

test "enum" {
    const Enum = enum { foo, @"bar\n" };

    try expectEqual(Enum.foo, try fromSlice(testing.allocator, Enum, "0"));
    try expectEqual(Enum.@"bar\n", try fromSlice(testing.allocator, Enum, "1"));
    try expectEqual(Enum.foo, try fromSlice(testing.allocator, Enum, "\"foo\""));
    try expectEqual(Enum.@"bar\n", try fromSlice(testing.allocator, Enum, "\"bar\\n\""));
}

test "float" {
    try expectEqual(@as(f32, std.math.f32_min), try fromSlice(testing.allocator, f32, "1.17549435082228750797e-38"));
    try expectEqual(@as(f32, std.math.f32_max), try fromSlice(testing.allocator, f32, "3.40282346638528859812e+38"));
    try expectEqual(@as(f64, std.math.f64_min), try fromSlice(testing.allocator, f64, "2.2250738585072014e-308"));
    try expectEqual(@as(f64, std.math.f64_max), try fromSlice(testing.allocator, f64, "1.79769313486231570815e+308"));
    try expectEqual(@as(f32, 1.0), try fromSlice(testing.allocator, f32, "1"));
    try expectEqual(@as(f64, 2.0), try fromSlice(testing.allocator, f64, "2"));
}

test "int" {
    try expectEqual(@as(u8, std.math.maxInt(u8)), try fromSlice(testing.allocator, u8, "255"));
    try expectEqual(@as(u32, std.math.maxInt(u32)), try fromSlice(testing.allocator, u32, "4294967295"));
    try expectEqual(@as(u64, std.math.maxInt(u64)), try fromSlice(testing.allocator, u64, "18446744073709551615"));
    try expectEqual(@as(i8, std.math.maxInt(i8)), try fromSlice(testing.allocator, i8, "127"));
    try expectEqual(@as(i32, std.math.maxInt(i32)), try fromSlice(testing.allocator, i32, "2147483647"));
    try expectEqual(@as(i64, std.math.maxInt(i64)), try fromSlice(testing.allocator, i64, "9223372036854775807"));
    try expectEqual(@as(i8, std.math.minInt(i8)), try fromSlice(testing.allocator, i8, "-128"));
    try expectEqual(@as(i32, std.math.minInt(i32)), try fromSlice(testing.allocator, i32, "-2147483648"));
    try expectEqual(@as(i64, std.math.minInt(i64)), try fromSlice(testing.allocator, i64, "-9223372036854775808"));

    // TODO: higher-bit conversions from float don't seem to work.
}

test "optional" {
    try expectEqual(@as(?bool, null), try fromSlice(testing.allocator, ?bool, "null"));
    try expectEqual(@as(?bool, true), try fromSlice(testing.allocator, ?bool, "true"));
}

test "pointer" {
    // one level of indirection
    {
        const value = try fromSlice(testing.allocator, *bool, "true");
        defer de.free(testing.allocator, value, null);

        try expectEqual(true, value.*);
    }

    // two levels of indirection
    {
        const value = try fromSlice(testing.allocator, **[]const u8, "\"Hello, World!\"");
        defer de.free(testing.allocator, value, null);

        try expectEqualSlices(u8, "Hello, World!", value.*.*);
    }

    // enum
    {
        const T = enum { foo, bar };

        // Tag value
        {
            const value = try fromSlice(testing.allocator, *T, "0");
            defer de.free(testing.allocator, value, null);

            try expectEqual(T.foo, value.*);
        }

        // Tag name
        {
            const value = try fromSlice(testing.allocator, *T, "\"bar\"");
            defer de.free(testing.allocator, value, null);

            try expectEqual(T.bar, value.*);
        }
    }

    // optional
    {
        // some
        {
            const value = try fromSlice(testing.allocator, *?bool, "true");
            defer de.free(testing.allocator, value, null);

            try expectEqual(true, value.*.?);
        }

        // none
        {
            const value = try fromSlice(testing.allocator, *?bool, "null");
            defer de.free(testing.allocator, value, null);

            try expectEqual(false, value.* orelse false);
        }
    }

    // sequence
    {
        const value = try fromSlice(testing.allocator, *[3]i8, "[1,2,3]");
        defer de.free(testing.allocator, value, null);

        try expectEqual([_]i8{ 1, 2, 3 }, value.*);
    }

    // struct
    {
        const T = struct { x: i32, y: []const u8, z: *[]const u8 };
        const value = try fromSlice(testing.allocator, *T,
            \\{"x":1,"y":"hello","z":"world"}
        );
        defer de.free(testing.allocator, value, null);

        try expectEqual(@as(i32, 1), value.*.x);
        try expectEqualSlices(u8, "hello", value.*.y);
        try expectEqualSlices(u8, "world", value.*.z.*);
    }

    // void
    {
        const value = try fromSlice(testing.allocator, *void, "null");
        defer de.free(testing.allocator, value, null);

        try expectEqual({}, value.*);
    }
}

test "slice (string)" {
    // Zig string
    {
        // Not escaped
        {
            const got = try fromSlice(testing.allocator, []u8, "\"Hello, World!\"");
            defer de.free(testing.allocator, got, null);
            try expect(eql(u8, "Hello, World!", got));
        }

        // Escaped
        {
            const got = try fromSlice(testing.allocator, []u8, "\"Hello\\nWorld!\"");
            defer de.free(testing.allocator, got, null);
            try expect(eql(u8, "Hello\nWorld!", got));
        }

        // Sentinel-terminated
        {
            const got = try fromSlice(testing.allocator, [:0]u8, "\"Hello\\nWorld!\"");
            defer de.free(testing.allocator, got, null);
            try expect(eql(u8, "Hello\nWorld!", got));
        }
    }

    // Non-zig string
    try expectError(error.InvalidType, fromSlice(testing.allocator, []i8, "\"Hello\\nWorld!\""));
}

test "slice (non-string)" {
    // scalar child
    {
        const got = try fromSlice(testing.allocator, []i32, "[1,2,3,4,5]");
        defer de.free(testing.allocator, got, null);

        try expectEqual([]i32, @TypeOf(got));
        try expect(eql(i32, &[_]i32{ 1, 2, 3, 4, 5 }, got));
    }

    // array child
    {
        const wants = .{
            [3]u32{ 1, 2, 3 },
            [3]u32{ 4, 5, 6 },
            [3]u32{ 7, 8, 9 },
        };
        const got = try fromSlice(testing.allocator, [][3]u32,
            \\[[1,2,3],[4,5,6],[7,8,9]]
        );
        defer de.free(testing.allocator, got, null);

        try expectEqual([][3]u32, @TypeOf(got));
        inline for (wants, got) |w, g| try expect(eql(u32, &w, &g));
    }

    // slice child
    {
        const wants = .{
            [_]i8{ 1, 2, 3 },
            [_]i8{ 4, 5 },
            [_]i8{6},
            [_]i8{ 7, 8, 9, 10 },
        };
        const got = try fromSlice(testing.allocator, [][]i8,
            \\[[1,2,3],[4,5],[6],[7,8,9,10]]
        );
        defer de.free(testing.allocator, got, null);

        try expectEqual([][]i8, @TypeOf(got));
        inline for (wants, got) |w, g| try expect(eql(i8, &w, g));
    }

    // string child
    {
        const wants = .{
            "Foo",
            "Bar",
            "Foobar",
        };
        const got = try fromSlice(testing.allocator, [][]const u8,
            \\["Foo","Bar","Foobar"]
        );
        defer de.free(testing.allocator, got, null);

        try expectEqual([][]const u8, @TypeOf(got));
        inline for (wants, got) |w, g| try expect(eql(u8, w, g));
    }
}

test "struct" {
    const got = try fromSlice(testing.allocator, struct { x: i32, y: []const u8 },
        \\{"x":1,"y":"Hello"}
    );
    defer de.free(testing.allocator, got, null);

    try expectEqual(@as(i32, 1), got.x);
    try expect(eql(u8, "Hello", got.y));
}

test "union" {
    {
        const Tagged = union(enum) { foo: bool, bar: void };
        const expected_foo = Tagged{ .foo = true };
        const expected_bar = Tagged{ .bar = {} };
        const got_foo = try fromSlice(testing.allocator, Tagged, "{\"foo\":true}");
        const got_bar = try fromSlice(testing.allocator, Tagged, "\"bar\"");

        try expectEqual(expected_foo, got_foo);
        try expectEqual(expected_bar, got_bar);
    }

    {
        const Untagged = union { foo: bool, bar: void };
        const expected_foo = Untagged{ .foo = false };
        const expected_bar = Untagged{ .bar = {} };
        const got_foo = try fromSlice(testing.allocator, Untagged, "{\"foo\":false}");
        const got_bar = try fromSlice(testing.allocator, Untagged, "\"bar\"");

        try expectEqual(expected_foo.foo, got_foo.foo);
        try expectEqual(expected_bar.bar, got_bar.bar);
    }
}

test "void" {
    try expectEqual({}, try fromSlice(testing.allocator, void, "null"));
    try testing.expectError(error.InvalidType, fromSlice(testing.allocator, void, "true"));
    try testing.expectError(error.InvalidType, fromSlice(testing.allocator, void, "1"));
}

test {
    testing.refAllDecls(@This());
}
