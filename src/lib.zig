const serializer = @import("ser/serializer.zig");
const escape = @import("ser/fmt/escape.zig");

pub const Serializer = serializer.Serializer;
pub const toWriter = serializer.toWriter;
pub const toPrettyWriter = serializer.toPrettyWriter;
pub const toWriterWith = serializer.toWriterWith;
pub const toPrettyWriterWith = serializer.toPrettyWriterWith;
pub const toString = serializer.toString;
pub const toPrettyString = serializer.toPrettyString;
pub const toStringWith = serializer.toStringWith;
pub const toPrettyStringWith = serializer.toPrettyStringWith;

pub const CharEscape = escape.CharEscape;
pub const formatEscapedString = escape.formatEscapedString;

pub const Formatter = @import("ser/fmt/formatter.zig").Formatter;
pub const CompactFormatter = @import("ser/fmt/formatters/compact.zig").CompactFormatter;
pub const PrettyFormatter = @import("ser/fmt/formatters/pretty.zig").PrettyFormatter;

const Deserializer = @import("de/deserializer.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
