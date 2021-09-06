const getty = @import("getty");
const std = @import("std");

pub const de = struct {
    pub usingnamespace @import("de/deserializer.zig");
};

pub fn fromReader(allocator: *std.mem.Allocator, comptime T: type, reader: anytype) !T {
    var deserializer = de.Deserializer(@TypeOf(reader)).init(allocator, reader);
    defer deserializer.deinit();

    return try getty.deserialize(T, deserializer.deserializer());
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
