const getty = @import("getty");
const std = @import("std");

/// A JSON deserializer.
pub const Deserializer = @import("de/deserializer.zig").Deserializer;

/// Deserializes JSON data from the deserializer `d` into a managed value of
/// type `T`.
pub fn fromDeserializer(
    ally: std.mem.Allocator,
    comptime T: type,
    d: anytype,
) !getty.de.Result(T) {
    var result = try getty.deserialize(ally, T, d.deserializer());
    errdefer result.deinit();

    try d.end();

    return result;
}

/// Deserializes JSON data from the deserializer `d` into an unmanaged value of
/// type `T`.
pub fn fromDeserializerLeaky(
    ally: std.mem.Allocator,
    comptime T: type,
    d: anytype,
) !T {
    const v = try getty.deserializeLeaky(ally, T, d.deserializer());
    try d.end();
    return v;
}

/// Deserializes JSON data from the reader `r` into a managed value of type
/// `T`.
pub fn fromReader(
    ally: std.mem.Allocator,
    comptime T: type,
    r: anytype,
) !getty.de.Result(T) {
    return try fromReaderWith(ally, T, r, null);
}

/// Deserializes JSON data from the reader `r` into an unmanaged value of type
/// `T`.
pub fn fromReaderLeaky(
    ally: std.mem.Allocator,
    comptime T: type,
    r: anytype,
) !T {
    return try fromReaderWithLeaky(ally, T, r, null);
}

/// Deserializes JSON data from the reader `r` into a managed value of type `T`,
/// with an additional deserialization block or tuple.
pub fn fromReaderWith(
    ally: std.mem.Allocator,
    comptime T: type,
    r: anytype,
    comptime dbt: anytype,
) !getty.de.Result(T) {
    var d = Deserializer(dbt, @TypeOf(r)).init(ally, r);
    defer d.deinit();

    return try fromDeserializer(ally, T, &d);
}

/// Deserializes JSON data from the reader `r` into an unmanaged value of type
/// `T`, with an additional deserialization block or tuple.
pub fn fromReaderWithLeaky(
    ally: std.mem.Allocator,
    comptime T: type,
    r: anytype,
    comptime dbt: anytype,
) !T {
    var d = Deserializer(dbt, @TypeOf(r)).init(ally, r);
    defer d.deinit();

    return try fromDeserializerLeaky(ally, T, &d);
}

/// Deserializes JSON data from a string into a managed value of type `T`.
pub fn fromSlice(
    ally: std.mem.Allocator,
    comptime T: type,
    s: []const u8,
) !getty.de.Result(T) {
    return try fromSliceWith(ally, T, s, null);
}

/// Deserializes JSON data from a string into an unmanaged value of type `T`.
pub fn fromSliceLeaky(
    ally: std.mem.Allocator,
    comptime T: type,
    s: []const u8,
) !T {
    return try fromSliceWithLeaky(ally, T, s, null);
}

/// Deserializes JSON data from a string into a managed value of type `T`, with
/// an additional deserialization block or tuple.
pub fn fromSliceWith(
    ally: std.mem.Allocator,
    comptime T: type,
    s: []const u8,
    comptime dbt: anytype,
) !getty.de.Result(T) {
    var fbs = std.io.fixedBufferStream(s);
    const r = fbs.reader();

    return try fromReaderWith(ally, T, r, dbt);
}

/// Deserializes JSON data from a string into an unmanaged value of type `T`,
/// with an additional deserialization block or tuple.
pub fn fromSliceWithLeaky(
    ally: std.mem.Allocator,
    comptime T: type,
    s: []const u8,
    comptime dbt: anytype,
) !T {
    var fbs = std.io.fixedBufferStream(s);
    const r = fbs.reader();

    return try fromReaderWithLeaky(ally, T, r, dbt);
}
