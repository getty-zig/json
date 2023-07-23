//! JSON escaping-related code.
//!
//! The escaping rules used in this module originate from Fastly:
//! https://developer.fastly.com/reference/vcl/functions/strings/json-escape/.
//!
//! The rules are as follows (in priority order):
//!
//!   1. If the code point is the double quote (0x22), it is escaped as \".
//!
//!   2. If the code point is the backslash (0x5C), it is escaped as \\.
//!
//!   3. If the code point is listed below, they are escaped accordingly:
//!
//!       * 0x08 (backspace)        ->  \b
//!       * 0x09 (horizontal tab)   ->  \t
//!       * 0x0A (newline)          ->  \n
//!       * 0x0C (form feed)        ->  \f
//!       * 0x0D (carriage return)  ->  \r
//!
//!   4. If the code point is less than or equal to 0x1F, or is equal to
//!   0x7F, 0x2028, or 0x2029, then it is a control character that wasn't
//!   listed above, and is escaped as \uHHHH where 'HHHH' is the hexadecimal
//!   value of the code point.
//!
//!   5. If the code point is greater than 0xFFFF (i.e., it is beyond the Basic
//!   Multilingual Plane of Unicode), the code point is converted into a UTF-16
//!   surrogate pair with the \\u notation (e.g., U+1F601, or '😁', would be
//!   escaped as \uD83D\uDE01).
//!
//!   6. If none of the preceding rules match and there is a sequence of
//!   valid UTF-8 bytes, the bytes are passed through as-is (e.g., the code
//!   point U+0061 would be passed through as 'a').
//!
//!   7. If there is a byte sequence of invalid UTF-8, the conversion fails.
const std = @import("std");

const DOUBLE_QUOTE = '\"';
const BACKSLASH = '\\';
const BACKSPACE = 0x08;
const TAB = '\t';
const NEWLINE = '\n';
const FORM_FEED = 0x0C;
const CARRIAGE_RETURN = '\r';

const HEX_DIGITS = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };

// ASCII characters that require escaping.
//
// The list of ASCII characters that require escaping include: 0x00-0x1F, 0x22
// (double quote), 0x5C (backslash), and 0x7F.
const escape_characters_ascii = [_]bool{
    true,  true,  true,  true,  true,  true,  true,  true,
    true,  true,  true,  true,  true,  true,  true,  true,
    true,  true,  true,  true,  true,  true,  true,  true,
    true,  true,  true,  true,  true,  true,  true,  true,
    false, false, true,  false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, true,  false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, true,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    // Ensures that 0xFF is not out of bounds.
    false,
};

/// Escapes a UTF-8 encoded code point using JSON escape sequences.
pub fn escapeChar(rune: u21, w: anytype) !void {
    switch (rune) {
        DOUBLE_QUOTE => try w.writeAll("\\\""),
        BACKSLASH => try w.writeAll("\\\\"),
        BACKSPACE => try w.writeAll("\\b"),
        TAB => try w.writeAll("\\t"),
        NEWLINE => try w.writeAll("\\n"),
        FORM_FEED => try w.writeAll("\\f"),
        CARRIAGE_RETURN => try w.writeAll("\\r"),
        else => switch (rune) {
            0x00...0x1F, 0x7F, 0x2028, 0x2029 => {
                try w.writeAll(&[_]u8{
                    '\\',
                    'u',
                    HEX_DIGITS[rune >> 12 & 0xF],
                    HEX_DIGITS[rune >> 8 & 0xF],
                    HEX_DIGITS[rune >> 4 & 0xF],
                    HEX_DIGITS[rune & 0xF],
                });
            },
            else => if (rune > 0xFFFF) {
                std.debug.assert(rune <= 0x10FFFF);

                const high = @as(u16, @intCast((rune - 0x10000) >> 10)) + 0xD800;
                const low = @as(u16, @intCast(rune & 0x3FF)) + 0xDC00;

                try w.writeAll(&[_]u8{
                    '\\',
                    'u',
                    HEX_DIGITS[high >> 12 & 0xF],
                    HEX_DIGITS[high >> 8 & 0xF],
                    HEX_DIGITS[high >> 4 & 0xF],
                    HEX_DIGITS[high & 0xF],
                    '\\',
                    'u',
                    HEX_DIGITS[low >> 12 & 0xF],
                    HEX_DIGITS[low >> 8 & 0xF],
                    HEX_DIGITS[low >> 4 & 0xF],
                    HEX_DIGITS[low & 0xF],
                });
            } else {
                @panic("Received code point that does not require escaping.");
            },
        },
    }
}

/// Escapes characters of a UTF-8 encoded string using JSON escape sequences.
pub fn writeEscaped(bytes: []const u8, w: anytype, f: anytype) !void {
    var i: usize = 0;
    var start: usize = 0;

    while (i < bytes.len) : (i += 1) {
        const length = std.unicode.utf8ByteSequenceLength(bytes[i]) catch unreachable;

        // Skip ASCII characters that don't require escaping.
        if (length == 1 and !escape_characters_ascii[bytes[i]]) {
            continue;
        }

        const rune = std.unicode.utf8Decode(bytes[i .. i + length]) catch unreachable;

        // Skip all other code points that don't require escaping.
        //
        // Oddly enough, all attempts to refactor this section have resulted in
        // lower performance when serializing strings that don't have any
        // characters that need escaping, and I have no idea why. Additionally,
        // overall performance is actually lowered even when we don't execute
        // the refactored versions of this section! Very weird.
        //
        // In any case, this switch lets us be faster than std.json, so I guess
        // it's fine as it is for now.
        switch (rune) {
            0x00...0x1F, DOUBLE_QUOTE, BACKSLASH, 0x7F, 0x2028, 0x2029 => {},
            else => if (rune <= 0xFFFF) {
                i += length - 1;
                continue;
            },
        }

        // Write out any buffered non-escaped code points.
        if (start < i) {
            try f.writeRawFragment(w, bytes[start..i]);
        }

        // Escape and write out the current code point.
        try f.writeCharEscape(w, rune);

        i += length - 1;
        start = i + 1;
    }

    // If the input string is suffixed by code points that do not require
    // escaping, then they've been buffered, but not written. So, we must write
    // them out.
    if (start != bytes.len) {
        try f.writeRawFragment(w, bytes[start..]);
    }
}
