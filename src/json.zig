//! A (de)serialization library for the JSON data format.

////////////////////////////////////////////////////////////////////////////////
// Types
////////////////////////////////////////////////////////////////////////////////

pub const Serializer = @import("ser.zig").Serializer;
pub const Deserializer = @import("de.zig").Deserializer;

////////////////////////////////////////////////////////////////////////////////
// Namespaces
////////////////////////////////////////////////////////////////////////////////

pub const ser = @import("ser.zig").ser;
pub const de = @import("de.zig").de;

////////////////////////////////////////////////////////////////////////////////
// Functions
////////////////////////////////////////////////////////////////////////////////

/// Deserializes into a value of type `T` from the deserializer `d`.
pub const fromDeserializer = @import("de.zig").fromDeserializer;

/// Deserializes into a value of type `T` from a reader of JSON data using a
/// deserialization block or tuple.
pub const fromReaderWith = @import("de.zig").fromReaderWith;

/// Deserializes into a value of type `T` from a reader of JSON data.
pub const fromReader = @import("de.zig").fromReader;

/// Deserializes into a value of type `T` from a slice of JSON using a
/// deserialization block or tuple.
pub const fromSliceWith = @import("de.zig").fromSliceWith;

/// Deserializes into a value of type `T` from a slice of JSON.
pub const fromSlice = @import("de.zig").fromSlice;

/// Serializes a value as JSON into an I/O stream using a serialization block
/// or tuple.
pub const toWriterWith = @import("ser.zig").toWriterWith;

/// Serializes a value as pretty-printed JSON into an I/O stream using a
/// serialization block or tuple.
pub const toPrettyWriterWith = @import("ser.zig").toPrettyWriterWith;

/// Serializes a value as JSON into an I/O stream.
pub const toWriter = @import("ser.zig").toWriter;

/// Serializes a value as pretty-printed JSON into an I/O stream.
pub const toPrettyWriter = @import("ser.zig").toPrettyWriter;

/// Serializes a value as a JSON string using a serialization block or tuple.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub const toSliceWith = @import("ser.zig").toSliceWith;

/// Serializes a value as a pretty-printed JSON string using a serialization
/// block or tuple.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub const toPrettySliceWith = @import("ser.zig").toPrettySliceWith;

/// Serializes a value as a JSON string.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub const toSlice = @import("ser.zig").toSlice;

/// Serializes a value as a pretty-printed JSON string.
///
/// The returned string is an owned slice. The caller is responsible for
/// freeing its memory.
pub const toPrettySlice = @import("ser.zig").toPrettySlice;
