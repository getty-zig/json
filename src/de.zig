const getty = @import("getty");
const std = @import("std");

/// A JSON deserializer.
pub const Deserializer = @import("de/deserializer.zig").Deserializer;

/// Deserialization-specific types and functions.
pub const de = struct {
    /// Frees resources allocated by Getty during deserialization.
    pub fn free(
        /// A memory allocator.
        ally: std.mem.Allocator,
        /// A value to deallocate.
        v: anytype,
        /// A deserialization block.
        comptime dbt: anytype,
    ) void {
        const D = Deserializer(
            dbt,
            std.io.FixedBufferStream([]u8).Reader, // TODO: wonk
        );

        return getty.de.free(ally, D.@"getty.Deserializer", v);
    }
};

/// Deserializes into a value of type `T` from the deserializer `d`.
pub fn fromDeserializer(comptime T: type, d: anytype) !T {
    const value = try getty.deserialize(d.ally, T, d.deserializer());
    errdefer de.free(d.ally, value, null);
    try d.end();

    return value;
}

pub fn fromReaderWith(ally: std.mem.Allocator, comptime T: type, r: anytype, comptime dbt: anytype) !T {
    var d = Deserializer(dbt, @TypeOf(r)).init(ally, r);
    defer d.deinit();

    return try fromDeserializer(T, &d);
}

pub fn fromReader(ally: std.mem.Allocator, comptime T: type, r: anytype) !T {
    return try fromReaderWith(ally, T, r, null);
}

/// Deserializes into a value of type `T` from a slice of JSON using a deserialization block or tuple.
pub fn fromSliceWith(ally: std.mem.Allocator, comptime T: type, s: []const u8, comptime dbt: anytype) !T {
    var fbs = std.io.fixedBufferStream(s);
    return try fromReaderWith(ally, T, fbs.reader(), dbt);
}

/// Deserializes into a value of type `T` from a slice of JSON.
pub fn fromSlice(ally: std.mem.Allocator, comptime T: type, s: []const u8) !T {
    return try fromSliceWith(ally, T, s, null);
}
