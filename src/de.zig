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
    var deserializer = de.Deserializer.init(allocator, reader);
    defer deserializer.deinit();

    return try getty.deserialize(allocator, T, deserializer.deserializer());
}

pub fn fromString(allocator: *std.mem.Allocator, comptime T: type, string: []const u8) !T {
    var fbs = std.io.fixedBufferStream(string);
    return try fromReader(allocator, T, fbs.reader());
}

test "array" {
    try expectEqual([2]bool{ false, false }, try fromString(testing.allocator, [2]bool, "[false,false]"));
    try expectEqual([2]bool{ true, true }, try fromString(testing.allocator, [2]bool, "[true,true]"));
    try expectEqual([2]bool{ true, false }, try fromString(testing.allocator, [2]bool, "[true,false]"));
    try expectEqual([2]bool{ false, true }, try fromString(testing.allocator, [2]bool, "[false,true]"));

    try expectEqual([5]i32{ 1, 2, 3, 4, 5 }, try fromString(testing.allocator, [5]i32, "[1,2,3,4,5]"));

    try expectEqual([2][1]i32{ .{1}, .{2} }, try fromString(testing.allocator, [2][1]i32, "[[1],[2]]"));
    try expectEqual([2][1][3]i32{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} }, try fromString(testing.allocator, [2][1][3]i32, "[[[1,2,3]],[[4,5,6]]]"));
}

test "bool" {
    try expectEqual(true, try fromString(testing.allocator, bool, "true"));
    try expectEqual(false, try fromString(testing.allocator, bool, "false"));
}

test "int" {
    try expectEqual(@as(u32, 1), try fromString(testing.allocator, u32, "1"));
    try expectEqual(@as(i32, -1), try fromString(testing.allocator, i32, "-1"));
    try expectEqual(@as(u32, 1), try fromString(testing.allocator, u32, "1.0"));
    try expectEqual(@as(i32, -1), try fromString(testing.allocator, i32, "-1.0"));
}

test "float" {
    try expectEqual(@as(f32, 3.14), try fromString(testing.allocator, f32, "3.14"));
    try expectEqual(@as(f64, 3.14), try fromString(testing.allocator, f64, "3.14"));
    try expectEqual(@as(f32, 3.0), try fromString(testing.allocator, f32, "3"));
    try expectEqual(@as(f64, 3.0), try fromString(testing.allocator, f64, "3"));
}

test "slice (string)" {
    const string = try fromString(testing.allocator, []const u8, "\"Hello, World!\"");
    defer testing.allocator.free(string);

    try expect(eql(u8, "Hello, World!", string));
}

test "struct" {
    const got = try fromString(testing.allocator, struct { x: i32, y: []const u8 },
        \\{"x":1,"y":"Hello"}
    );
    defer testing.allocator.free(got.y);

    try expectEqual(@as(i32, 1), got.x);
    try expect(eql(u8, "Hello", got.y));
}

test "optional" {
    try expectEqual(@as(?i32, null), try fromString(testing.allocator, ?i32, "null"));
    try expectEqual(@as(?i32, 42), try fromString(testing.allocator, ?i32, "42"));
}

test "void" {
    try expectEqual({}, try fromString(testing.allocator, void, "null"));
    try testing.expectError(error.Input, fromString(testing.allocator, void, "true"));
    try testing.expectError(error.Input, fromString(testing.allocator, void, "1"));
}

test {
    testing.refAllDecls(@This());
}
