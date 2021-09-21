const std = @import("std");

pub const DOUBLE_QUOTE = '\"';
pub const BACKSLASH = '\\';
pub const BACKSPACE = 0x08;
pub const TAB = '\t';
pub const NEWLINE = '\n';
pub const FORM_FEED = 0x0C;
pub const CARRIAGE_RETURN = '\r';

pub const HEX_DIGITS = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };

/// From Fastly, the JSON escape rules are as follows (in priority order):
///
///     1. If the code point is the double quote (0x22), it is escaped as \".
///
///     2. If the code point is the backslash (0x5C), it is escaped as \\.
///
///     3. The following code points are escaped as follows:
///
///         * 0x08 (backspace)       -> \b
///         * 0x09 (horizontal tab)  -> \t
///         * 0x0A (newline)         -> \n
///         * 0x0C (form feed)       -> \f
///         * 0x0D (carriage return) -> \r
///
///     4. If the code point is less than or equal to 0x1F, or is equal to
///     0x7F, 0x2028, or 0x2029, then it is a control character that wasn't
///     listed above, and is escaped as \uHHHH where 'HHHH' is the hexadecimal
///     value of the code point.
///
///     5. If the code point is greater than 0xFFFF (i.e., beyond the Basic
///     Multilingual Plane of Unicode), the code point is converted into a
///     UTF-16 surrogate pair with the \\u notation (e.g., U+1F601, or '😁',
///     would be escaped as \uD83D\uDE01).
///
///     6. If none of the preceding rules match and there is a sequence of
///     valid UTF-8 bytes, the bytes are passed through as-is (e.g., the code
///     point U+0061 would be passed through as 'a').
///
///     7. If there is a byte sequence of invalid UTF-8, the conversion fails.
///
/// Note that the rules imply that no code points between 0x7F and 0x10000 are
/// escaped as \\uHHHH except for the code poitns U+2028 and U+2029.
pub fn escape(bytes: []const u8, writer: anytype, formatter: anytype) !void {
    var i: usize = 0;
    var start: usize = 0;

    while (i < bytes.len) : (i += 1) {
        const byte = bytes[i];
        const length = std.unicode.utf8ByteSequenceLength(byte) catch unreachable;
        const codepoint = std.unicode.utf8Decode(bytes[i .. i + length]) catch unreachable;

        // Skip byte if it doesn't need escaping.
        switch (byte) {
            DOUBLE_QUOTE, BACKSLASH, BACKSPACE, TAB, NEWLINE, FORM_FEED, CARRIAGE_RETURN => {},
            else => {
                switch (codepoint) {
                    0x00...0x1F, 0x7F, 0x2028, 0x2029 => {},
                    else => if (codepoint <= 0xFFFF) {
                        i += length - 1;
                        continue;
                    },
                }
            },
        }

        // Write any non-escaped characters that have been buffered up until
        // this point.
        if (start < i) {
            try formatter.writeRawFragment(writer, bytes[start..i]);
        }

        switch (byte) {
            DOUBLE_QUOTE, BACKSLASH, BACKSPACE, TAB, NEWLINE, FORM_FEED, CARRIAGE_RETURN => {
                try formatter.writeCharEscape(writer, byte);
            },
            else => {
                switch (codepoint) {
                    0x00...0x1F, 0x7F, 0x2028, 0x2029 => try formatter.writeCharEscape(writer, codepoint),
                    else => if (codepoint > 0xFFFF) try formatter.writeCharEscape(writer, codepoint),
                }
            },
        }

        i += length - 1;
        start = i + 1;
    }

    if (start != bytes.len) {
        try formatter.writeRawFragment(writer, bytes[start..]);
    }
}
