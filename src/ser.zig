const getty = @import("getty");
const std = @import("std");

/// A compact JSON serializer instance.
pub const serializer = @import("ser/serializer.zig").serializer;

/// A JSON serializer.
pub const Serializer = @import("ser/serializer.zig").Serializer;

/// Serialization-specific types and functions.
pub const ser = struct {
    // TODO: Cannot import Formatter like we do with the other decls in here.
    //
    //       It looks like there's some index out of bound bug in Autodoc that
    //       crashes everything when `zig build docs` is run. So, Formatter
    //       won't show up in the API docs for now.
    pub usingnamespace @import("ser/interface/formatter.zig");

    /// A compact formatter implementation.
    pub const CompactFormatter = @import("ser/impl/formatter/compact.zig").Formatter;

    /// A pretty formatter implementation.
    pub const PrettyFormatter = @import("ser/impl/formatter/pretty.zig").Formatter;
};

/// Serializes a value as JSON into an I/O stream using a serialization block
/// or tuple.
pub fn toWriterWith(
    /// An optional memory allocator.
    ally: ?std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
    /// A `std.io.Writer` interface value.
    w: anytype,
    /// A serialization block or tuple.
    comptime sbt: anytype,
) !void {
    var s = serializer(ally, w, sbt);
    const ss = s.serializer();

    try getty.serialize(ally, v, ss);
}

/// Serializes a value as pretty-printed JSON into an I/O stream using a
/// serialization block or tuple.
pub fn toPrettyWriterWith(
    /// An optional memory allocator.
    ally: ?std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
    /// A `std.io.Writer` interface value.
    w: anytype,
    /// A serialization block or tuple.
    comptime sbt: anytype,
) !void {
    var f = ser.PrettyFormatter(@TypeOf(w)).init();
    const ff = f.formatter();

    var s = Serializer(@TypeOf(w), @TypeOf(ff), sbt).init(ally, w, ff);
    var ss = s.serializer();

    try getty.serialize(ally, v, ss);
}

/// Serializes a value as JSON into an I/O stream.
pub fn toWriter(
    /// An optional memory allocator.
    ally: ?std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
    /// A `std.io.Writer` interface value.
    w: anytype,
) !void {
    try toWriterWith(ally, v, w, null);
}

/// Serializes a value as pretty-printed JSON into an I/O stream.
pub fn toPrettyWriter(
    /// An optional memory allocator.
    ally: ?std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
    /// A `std.io.Writer` interface value.
    w: anytype,
) !void {
    try toPrettyWriterWith(ally, v, w, null);
}

/// Serializes a value as a JSON string using a serialization block or tuple.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toSliceWith(
    /// A memory allocator.
    ally: std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
    /// A serialization block or tuple.
    comptime sbt: anytype,
) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(ally, 128);
    defer list.deinit();

    try toWriterWith(ally, v, list.writer(), sbt);

    return try list.toOwnedSlice();
}

/// Serializes a value as a pretty-printed JSON string using a serialization
/// block or tuple.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toPrettySliceWith(
    /// A memory allocator.
    ally: std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
    /// A serialization block or tuple.
    comptime sbt: anytype,
) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(ally, 128);
    defer list.deinit();

    try toPrettyWriterWith(ally, v, list.writer(), sbt);

    return try list.toOwnedSlice();
}

/// Serializes a value as a JSON string.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toSlice(
    /// A memory allocator.
    ally: std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
) ![]const u8 {
    return try toSliceWith(ally, v, null);
}

/// Serializes a value as a pretty-printed JSON string.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toPrettySlice(
    /// A memory allocator.
    ally: std.mem.Allocator,
    /// A value to serialize.
    v: anytype,
) ![]const u8 {
    return try toPrettySliceWith(ally, v, null);
}
