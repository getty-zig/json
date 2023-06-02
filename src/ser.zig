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
    allocator: ?std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
    /// A `std.io.Writer` interface value.
    writer: anytype,
    /// A serialization block or tuple.
    comptime user_sbt: anytype,
) !void {
    comptime concepts.@"std.io.Writer"(@TypeOf(writer));

    var cs = serializer(allocator, writer, user_sbt);
    const s = cs.serializer();

    try getty.serialize(allocator, value, s);
}

/// Serializes a value as pretty-printed JSON into an I/O stream using a
/// serialization block or tuple.
pub fn toPrettyWriterWith(
    /// An optional memory allocator.
    allocator: ?std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
    /// A `std.io.Writer` interface value.
    writer: anytype,
    /// A serialization block or tuple.
    comptime user_sbt: anytype,
) !void {
    comptime concepts.@"std.io.Writer"(@TypeOf(writer));

    var f = ser.PrettyFormatter(@TypeOf(writer)).init();
    const formatter = f.formatter();

    var ps = Serializer(
        @TypeOf(writer),
        @TypeOf(formatter),
        user_sbt,
    ).init(
        allocator,
        writer,
        formatter,
    );
    var s = ps.serializer();

    try getty.serialize(allocator, value, s);
}

/// Serializes a value as JSON into an I/O stream.
pub fn toWriter(
    /// An optional memory allocator.
    allocator: ?std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
    /// A `std.io.Writer` interface value.
    writer: anytype,
) !void {
    try toWriterWith(allocator, value, writer, null);
}

/// Serializes a value as pretty-printed JSON into an I/O stream.
pub fn toPrettyWriter(
    /// An optional memory allocator.
    allocator: ?std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
    /// A `std.io.Writer` interface value.
    writer: anytype,
) !void {
    try toPrettyWriterWith(allocator, value, writer, null);
}

/// Serializes a value as a JSON string using a serialization block or tuple.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toSliceWith(
    /// A memory allocator.
    allocator: std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
    /// A serialization block or tuple.
    comptime user_sbt: anytype,
) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 128);
    defer list.deinit();

    try toWriterWith(allocator, value, list.writer(), user_sbt);
    return try list.toOwnedSlice();
}

/// Serializes a value as a pretty-printed JSON string using a serialization
/// block or tuple.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toPrettySliceWith(
    /// A memory allocator.
    allocator: std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
    /// A serialization block or tuple.
    comptime user_sbt: anytype,
) ![]const u8 {
    var list = try std.ArrayList(u8).initCapacity(allocator, 128);
    defer list.deinit();

    try toPrettyWriterWith(allocator, value, list.writer(), user_sbt);
    return try list.toOwnedSlice();
}

/// Serializes a value as a JSON string.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toSlice(
    /// A memory allocator.
    allocator: std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
) ![]const u8 {
    return try toSliceWith(allocator, value, null);
}

/// Serializes a value as a pretty-printed JSON string.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub fn toPrettySlice(
    /// A memory allocator.
    allocator: std.mem.Allocator,
    /// A value to serialize.
    value: anytype,
) ![]const u8 {
    return try toPrettySliceWith(allocator, value, null);
}

const concepts = struct {
    fn @"std.io.Writer"(comptime T: type) void {
        const err = "expected `std.io.Writer` interface value, found `" ++ @typeName(T) ++ "`";

        comptime {
            // Invariants
            if (!std.meta.trait.isContainer(T)) {
                @compileError(err);
            }

            // Constraints
            const has_name = std.mem.startsWith(u8, @typeName(T), "io.writer.Writer");
            const has_field = std.meta.trait.hasField("context")(T);
            const has_decl = @hasDecl(T, "Error");
            const has_funcs = std.meta.trait.hasFunctions(T, .{
                "write",
                "writeAll",
                "print",
                "writeByte",
                "writeByteNTimes",
                "writeIntNative",
                "writeIntForeign",
                "writeIntLittle",
                "writeIntBig",
                "writeInt",
                "writeStruct",
            });

            if (!(has_name and has_field and has_decl and has_funcs)) {
                @compileError(err);
            }
        }
    }
};
