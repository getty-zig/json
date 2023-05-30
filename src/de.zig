const getty = @import("getty");
const std = @import("std");

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

    return try fromDeserializer(T, &d);
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
