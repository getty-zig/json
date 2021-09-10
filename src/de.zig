const getty = @import("getty");
const std = @import("std");

pub const de = struct {
    pub usingnamespace @import("de/deserializer.zig");
};

pub fn fromReader(allocator: *std.mem.Allocator, comptime T: type, reader: anytype) !T {
    var deserializer = de.Deserializer(@TypeOf(reader)).init(allocator, reader);
    defer deserializer.deinit();

    return try getty.deserialize(allocator, T, deserializer.deserializer());
}

pub fn fromString(allocator: *std.mem.Allocator, comptime T: type, string: []const u8) !T {
    var fbs = std.io.fixedBufferStream(string);
    return try fromReader(allocator, T, fbs.reader());
}

test "array" {
    try std.testing.expectEqual([2]bool{ false, false }, try fromString(std.testing.allocator, [2]bool, "[false,false]"));
    try std.testing.expectEqual([2]bool{ true, true }, try fromString(std.testing.allocator, [2]bool, "[true,true]"));
    try std.testing.expectEqual([2]bool{ true, false }, try fromString(std.testing.allocator, [2]bool, "[true,false]"));
    try std.testing.expectEqual([2]bool{ false, true }, try fromString(std.testing.allocator, [2]bool, "[false,true]"));

    try std.testing.expectEqual([5]i32{ 1, 2, 3, 4, 5 }, try fromString(std.testing.allocator, [5]i32, "[1,2,3,4,5]"));

    try std.testing.expectEqual([2][1]i32{ .{1}, .{2} }, try fromString(std.testing.allocator, [2][1]i32, "[[1],[2]]"));
    try std.testing.expectEqual([2][1][3]i32{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} }, try fromString(std.testing.allocator, [2][1][3]i32, "[[[1,2,3]],[[4,5,6]]]"));
}

test "bool" {
    try std.testing.expectEqual(true, try fromString(std.testing.allocator, bool, "true"));
    try std.testing.expectEqual(false, try fromString(std.testing.allocator, bool, "false"));
}

test "int" {
    try std.testing.expectEqual(@as(u32, 1), try fromString(std.testing.allocator, u32, "1"));
    try std.testing.expectEqual(@as(i32, -1), try fromString(std.testing.allocator, i32, "-1"));
    try std.testing.expectEqual(@as(u32, 1), try fromString(std.testing.allocator, u32, "1.0"));
    try std.testing.expectEqual(@as(i32, -1), try fromString(std.testing.allocator, i32, "-1.0"));
}

test "float" {
    try std.testing.expectEqual(@as(f32, 3.14), try fromString(std.testing.allocator, f32, "3.14"));
    try std.testing.expectEqual(@as(f64, 3.14), try fromString(std.testing.allocator, f64, "3.14"));
    try std.testing.expectEqual(@as(f32, 3.0), try fromString(std.testing.allocator, f32, "3"));
    try std.testing.expectEqual(@as(f64, 3.0), try fromString(std.testing.allocator, f64, "3"));
}

test "slice" {
    const string = try fromString(std.testing.allocator, []const u8, "\"Hello, World!\"");
    defer std.testing.allocator.free(string);

    try std.testing.expect(std.mem.eql(u8, "Hello, World!", string));
}

test "struct" {
    const got = try fromString(std.testing.allocator, struct { x: i32, y: []const u8 },
        \\{"x":1,"y":"Hello"}
    );
    defer std.testing.allocator.free(got.y);

    try std.testing.expectEqual(@as(i32, 1), got.x);
    try std.testing.expect(std.mem.eql(u8, "Hello", got.y));
}

test "optional" {
    try std.testing.expectEqual(@as(?i32, null), try fromString(std.testing.allocator, ?i32, "null"));
    try std.testing.expectEqual(@as(?i32, 42), try fromString(std.testing.allocator, ?i32, "42"));
}

test "void" {
    try std.testing.expectEqual({}, try fromString(std.testing.allocator, void, "null"));
    try std.testing.expectError(error.Input, fromString(std.testing.allocator, void, "true"));
    try std.testing.expectError(error.Input, fromString(std.testing.allocator, void, "1"));
}

test {
    std.testing.refAllDecls(@This());
}
