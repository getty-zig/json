const getty = @import("getty");
const std = @import("std");

const eql = std.mem.eql;
const testing = std.testing;

const expect = testing.expect;
const expectEqual = testing.expectEqual;

pub const de = struct {
    pub usingnamespace @import("de/deserializer.zig");
};

pub fn fromReader(allocator: *std.mem.Allocator, comptime T: type, reader: anytype) !T {
    var deserializer = de.Deserializer.fromReader(allocator, reader);
    defer deserializer.deinit();
    const value = try getty.deserialize(allocator, T, deserializer.deserializer());

    try deserializer.end();
    return value;
}

pub fn fromSlice(comptime T: type, slice: []const u8) !T {
    if (@typeInfo(T) == .Pointer) {
        @compileError("cannot deserialize into type `" ++ @typeName(T) ++ "` without allocation. Use `json.fromSliceAlloc` instead.");
    }

    var deserializer = de.Deserializer.init(slice);
    const value = try getty.deserialize(null, T, deserializer.deserializer());

    try deserializer.end();
    return value;
}

pub fn fromSliceAlloc(allocator: *std.mem.Allocator, comptime T: type, slice: []const u8) !T {
    var deserializer = de.Deserializer.withAllocator(allocator, slice);
    const value = try getty.deserialize(allocator, T, deserializer.deserializer());
    errdefer free(allocator, value);

    try deserializer.end();
    return value;
}

pub fn free(allocator: *std.mem.Allocator, value: anytype) void {
    return getty.free(allocator, value);
}

test "array" {
    try expectEqual([2]bool{ false, false }, try fromSlice([2]bool, "[false,false]"));
    try expectEqual([2]bool{ true, true }, try fromSlice([2]bool, "[true,true]"));
    try expectEqual([2]bool{ true, false }, try fromSlice([2]bool, "[true,false]"));
    try expectEqual([2]bool{ false, true }, try fromSlice([2]bool, "[false,true]"));

    try expectEqual([5]i32{ 1, 2, 3, 4, 5 }, try fromSlice([5]i32, "[1,2,3,4,5]"));

    try expectEqual([2][1]i32{ .{1}, .{2} }, try fromSlice([2][1]i32, "[[1],[2]]"));
    try expectEqual([2][1][3]i32{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} }, try fromSlice([2][1][3]i32, "[[[1,2,3]],[[4,5,6]]]"));
}

test "bool" {
    try expectEqual(true, try fromSlice(bool, "true"));
    try expectEqual(false, try fromSlice(bool, "false"));
}

test "enum" {
    const T = enum { foo, bar };

    {
        // integers
        try expectEqual(T.foo, try fromSlice(T, "0"));
        try expectEqual(T.bar, try fromSlice(T, "1"));
    }

    {
        // strings
        try expectEqual(T.foo, try fromSlice(T, "\"foo\""));
        try expectEqual(T.bar, try fromSlice(T, "\"bar\""));
    }
}

test "float" {
    {
        // floats
        try expectEqual(@as(f32, 3.14), try fromSlice(f32, "3.14"));
        try expectEqual(@as(f64, 3.14), try fromSlice(f64, "3.14"));
    }

    {
        // integers
        try expectEqual(@as(f32, 3.0), try fromSlice(f32, "3"));
        try expectEqual(@as(f64, 3.0), try fromSlice(f64, "3"));
    }
}

test "int" {
    {
        // integers
        try expectEqual(@as(u32, 1), try fromSlice(u32, "1"));
        try expectEqual(@as(i32, -1), try fromSlice(i32, "-1"));
    }

    {
        // floats
        try expectEqual(@as(u32, 1), try fromSlice(u32, "1.0"));
        try expectEqual(@as(i32, -1), try fromSlice(i32, "-1.0"));
    }
}

test "optional" {
    try expectEqual(@as(?i32, null), try fromSlice(?i32, "null"));
    try expectEqual(@as(?i32, 42), try fromSlice(?i32, "42"));
}

test "pointer" {
    // one level of indirection
    {
        const value = try fromSliceAlloc(std.testing.allocator, *bool, "true");
        defer free(std.testing.allocator, value);

        try expectEqual(true, value.*);
    }

    // two levels of indirection
    {
        const value = try fromSliceAlloc(std.testing.allocator, **i32, "1234");
        defer free(std.testing.allocator, value);

        try expectEqual(@as(i32, 1234), value.*.*);
    }

    // enum
    {
        const T = enum { foo, bar };

        // Tag value
        {
            const value = try fromSliceAlloc(std.testing.allocator, *T, "0");
            defer free(std.testing.allocator, value);

            try expectEqual(T.foo, value.*);
        }

        // Tag name
        {
            const value = try fromSliceAlloc(std.testing.allocator, *T, "\"bar\"");
            defer free(std.testing.allocator, value);

            try expectEqual(T.bar, value.*);
        }
    }

    // optional
    {
        // some
        {
            const value = try fromSliceAlloc(std.testing.allocator, *?bool, "true");
            defer free(std.testing.allocator, value);

            try expectEqual(true, value.*.?);
        }

        // none
        {
            const value = try fromSliceAlloc(std.testing.allocator, *?bool, "null");
            defer free(std.testing.allocator, value);

            try expectEqual(false, value.* orelse false);
        }
    }

    // sequence
    {
        const value = try fromSliceAlloc(std.testing.allocator, *[3]i8, "[1,2,3]");
        defer free(std.testing.allocator, value);

        try expectEqual([_]i8{ 1, 2, 3 }, value.*);
    }

    // struct
    {
        const T = struct { x: i32, y: **[]const u8, z: []const u8 };
        const value = try fromSliceAlloc(std.testing.allocator, *T,
            \\{"x":1,"y":"hello","z":"world"}
        );
        defer free(std.testing.allocator, value);

        try expectEqual(@as(i32, 1), value.*.x);
        try testing.expectEqualSlices(u8, "hello", value.*.y.*.*);
        try testing.expectEqualSlices(u8, "world", value.*.z);
    }

    // void
    {
        const value = try fromSliceAlloc(std.testing.allocator, *void, "null");
        defer free(std.testing.allocator, value);

        try expectEqual({}, value.*);
    }
}

test "slice (string)" {
    const string = try fromSliceAlloc(testing.allocator, []const u8, "\"Hello, World!\"");
    defer testing.allocator.free(string);

    try expect(eql(u8, "Hello, World!", string));
}

test "slice (non-string)" {
    // scalar child
    {
        const want = [_]i32{ 1, 2, 3, 4, 5 };
        const got = try fromSliceAlloc(testing.allocator, []i32, "[1,2,3,4,5]");
        defer testing.allocator.free(got);

        try expectEqual([]i32, @TypeOf(got));
        try expect(eql(i32, &want, got));
    }

    // array child
    {
        const wants = .{
            [3]u32{ 1, 2, 3 },
            [3]u32{ 4, 5, 6 },
            [3]u32{ 7, 8, 9 },
        };
        const got = try fromSliceAlloc(testing.allocator, [][3]u32,
            \\[[1,2,3],[4,5,6],[7,8,9]]
        );
        defer testing.allocator.free(got);

        try expectEqual([][3]u32, @TypeOf(got));
        inline for (wants) |want, i| try expect(eql(u32, &want, &got[i]));
    }

    // slice child
    {
        const wants = .{
            [_]u8{ 1, 2, 3 },
            [_]u8{ 4, 5 },
            [_]u8{6},
            [_]u8{ 7, 8, 9, 10 },
        };
        const got = try fromSliceAlloc(testing.allocator, [][]u8,
            \\[[1,2,3],[4,5],[6],[7,8,9,10]]
        );
        defer {
            for (got) |elem| testing.allocator.free(elem);
            testing.allocator.free(got);
        }

        try expectEqual([][]u8, @TypeOf(got));
        inline for (wants) |want, i| try expect(eql(u8, &want, got[i]));
    }

    // string child
    {
        const wants = .{
            "Foo",
            "Bar",
            "Foobar",
        };
        const got = try fromSliceAlloc(testing.allocator, [][]const u8,
            \\["Foo","Bar","Foobar"]
        );
        defer {
            for (got) |elem| testing.allocator.free(elem);
            testing.allocator.free(got);
        }

        try expectEqual([][]const u8, @TypeOf(got));
        inline for (wants) |want, i| {
            try expect(eql(u8, want, got[i]));
        }
    }
}

test "struct" {
    // no allocation
    {
        const got = try fromSlice(struct { x: i32, y: i32 },
            \\{"x":1,"y":2}
        );

        try expectEqual(@as(i32, 1), got.x);
        try expectEqual(@as(i32, 2), got.y);
    }

    // allocation
    {
        const got = try fromSliceAlloc(testing.allocator, struct { x: []const u8 },
            \\{"x":"Hello"}
        );
        defer testing.allocator.free(got.x);

        try expect(eql(u8, "Hello", got.x));
    }
}

test "void" {
    try expectEqual({}, try fromSlice(void, "null"));
    try testing.expectError(error.Input, fromSlice(void, "true"));
    try testing.expectError(error.Input, fromSlice(void, "1"));
}

test {
    testing.refAllDecls(@This());
}
