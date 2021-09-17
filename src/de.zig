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

    return try getty.deserialize(allocator, T, deserializer.deserializer());
}

pub fn fromSlice(comptime T: type, slice: []const u8) !T {
    return try getty.deserialize(null, T, de.Deserializer.init(slice).deserializer());
}

pub fn fromSliceAlloc(allocator: *std.mem.Allocator, comptime T: type, slice: []const u8) !T {
    return try getty.deserialize(allocator, T, de.Deserializer.init(slice).deserializer());
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

test "int" {
    try expectEqual(@as(u32, 1), try fromSlice(u32, "1"));
    try expectEqual(@as(i32, -1), try fromSlice(i32, "-1"));
    try expectEqual(@as(u32, 1), try fromSlice(u32, "1.0"));
    try expectEqual(@as(i32, -1), try fromSlice(i32, "-1.0"));
}

test "float" {
    try expectEqual(@as(f32, 3.14), try fromSlice(f32, "3.14"));
    try expectEqual(@as(f64, 3.14), try fromSlice(f64, "3.14"));
    try expectEqual(@as(f32, 3.0), try fromSlice(f32, "3"));
    try expectEqual(@as(f64, 3.0), try fromSlice(f64, "3"));
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
    const got = try fromSliceAlloc(testing.allocator, struct { x: i32, y: []const u8 },
        \\{"x":1,"y":"Hello"}
    );
    defer testing.allocator.free(got.y);

    try expectEqual(@as(i32, 1), got.x);
    try expect(eql(u8, "Hello", got.y));
}

test "optional" {
    try expectEqual(@as(?i32, null), try fromSlice(?i32, "null"));
    try expectEqual(@as(?i32, 42), try fromSlice(?i32, "42"));
}

test "void" {
    try expectEqual({}, try fromSlice(void, "null"));
    try testing.expectError(error.Input, fromSlice(void, "true"));
    try testing.expectError(error.Input, fromSlice(void, "1"));
}

test {
    testing.refAllDecls(@This());
}
