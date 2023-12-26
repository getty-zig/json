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

////////////////////////////////////////////////////////////////////////////////
// Functions
////////////////////////////////////////////////////////////////////////////////

/// Deserializes JSON data from the deserializer `d` into a managed value of
/// type `T`.
pub const fromDeserializer = @import("de.zig").fromDeserializer;

/// Deserializes JSON data from the deserializer `d` into an unmanaged value of
/// type `T`.
pub const fromDeserializerLeaky = @import("de.zig").fromDeserializerLeaky;

/// Deserializes JSON data from the reader `r` into a managed value of type
/// `T`.
pub const fromReader = @import("de.zig").fromReader;

/// Deserializes JSON data from the reader `r` into an unmanaged value of type
/// `T`.
pub const fromReaderLeaky = @import("de.zig").fromReaderLeaky;

/// Deserializes JSON data from the reader `r` into a managed value of type `T`,
/// with an additional deserialization block or tuple.
pub const fromReaderWith = @import("de.zig").fromReaderWith;

/// Deserializes JSON data from the reader `r` into an unmanaged value of type
/// `T`, with an additional deserialization block or tuple.
pub const fromReaderWithLeaky = @import("de.zig").fromReaderWithLeaky;

/// Deserializes JSON data from a string into a managed value of type `T`.
pub const fromSlice = @import("de.zig").fromSlice;

/// Deserializes JSON data from a string into an unmanaged value of type `T`.
pub const fromSliceLeaky = @import("de.zig").fromSliceLeaky;

/// Deserializes JSON data from a string into a managed value of type `T`, with
/// an additional deserialization block or tuple.
pub const fromSliceWith = @import("de.zig").fromSliceWith;

/// Deserializes JSON data from a string into an unmanaged value of type `T`,
/// with an additional deserialization block or tuple.
pub const fromSliceWithLeaky = @import("de.zig").fromSliceWithLeaky;

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
