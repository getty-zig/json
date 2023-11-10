const getty = @import("getty");
const std = @import("std");

/// A JSON deserializer.
pub const Deserializer = @import("de/deserializer.zig").Deserializer;

/// Deserializes into a value of type `T` from a slice of JSON.
pub fn fromSlice(
    ally: std.mem.Allocator,
    comptime T: type,
    s: []const u8,
) !getty.de.Result(T) {
    return try fromSliceWith(ally, T, s, null);
}

/// Deserializes into a value of type `T` from a slice of JSON using a
/// deserialization block or tuple.
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

/// Deserializes into a value of type `T` from the reader `r`.
pub fn fromReader(
    ally: std.mem.Allocator,
    comptime T: type,
    r: anytype,
) !getty.de.Result(T) {
    return try fromReaderWith(ally, T, r, null);
}

/// Deserializes into a value of type `T` from the reader `r` using a
/// deserialization block or tuple.
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

/// Deserializes into a value of type `T` from the deserializer `d`.
pub fn fromDeserializer(ally: std.mem.Allocator, comptime T: type, d: anytype) !getty.de.Result(T) {
    var result = try getty.deserialize(ally, T, d.deserializer());
    errdefer result.deinit();

    try d.end();

    return result;
}
