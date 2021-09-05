pub const CharEscape = union(enum) {
    // An escaped ASCII plane control character (usually escaped as `\u00XX`
    // where `XX` are two hex characters)
    ascii: u8,

    non_ascii: enum(u8) {
        /// An escaped quote `"`
        Quote,

        /// An escaped reverse solidus `\`
        ReverseSolidus,

        /// An escaped solidus `/`
        Solidus,

        /// An escaped backspace character (usually escaped as `\b`)
        Backspace,

        /// An escaped form feed character (usually escaped as `\f`)
        FormFeed,

        /// An escaped line feed character (usually escaped as `\n`)
        LineFeed,

        /// An escaped carriage return character (usually escaped as `\r`)
        CarriageReturn,

        /// An escaped tab character (usually escaped as `\t`)
        Tab,
    },

    fn fromEscapeTable(escape: u8, byte: u8) @This() {
        switch (escape) {
            BB => return .{ .non_ascii = .Backspace },
            TT => return .{ .non_ascii = .Tab },
            NN => return .{ .non_ascii = .LineFeed },
            FF => return .{ .non_ascii = .FormFeed },
            RR => return .{ .non_ascii = .CarriageReturn },
            QU => return .{ .non_ascii = .Quote },
            BS => return .{ .non_ascii = .ReverseSolidus },
            UU => return .{ .ascii = byte },
            else => unreachable,
        }
    }
};

pub fn formatEscapedString(writer: anytype, formatter: anytype, bytes: []const u8) !void {
    var start: usize = 0;

    for (bytes) |byte, i| {
        // TODO: Does byte need to be casted?
        const escape = ESCAPE[@as(usize, byte)];

        if (escape == 0) {
            continue;
        }

        if (start < i) {
            try formatter.writeStringFragment(writer, bytes[start..i]);
        }

        const char_escape = CharEscape.fromEscapeTable(escape, byte);
        try formatter.writeCharEscape(writer, char_escape);

        start = i + 1;
    }

    if (start != bytes.len) {
        try formatter.writeStringFragment(writer, bytes[start..]);
    }
}

const BB: u8 = 'b'; // \x08
const TT: u8 = 't'; // \x09
const NN: u8 = 'n'; // \x0A
const FF: u8 = 'f'; // \x0C
const RR: u8 = 'r'; // \x0D
const QU: u8 = '"'; // \x22
const BS: u8 = '\\'; // \x5C
const UU: u8 = 'u'; // \x00...\x1F except the ones above
const __: u8 = 0;

// Lookup table of escape sequences. A value of b'x' at index i means that byte
// i is escaped as "\x" in JSON. A value of 0 means that byte i is not escaped.
const ESCAPE = [256]u8{
    //   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
    UU, UU, UU, UU, UU, UU, UU, UU, BB, TT, NN, UU, FF, RR, UU, UU, // 0
    UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, UU, // 1
    __, __, QU, __, __, __, __, __, __, __, __, __, __, __, __, __, // 2
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 3
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 4
    __, __, __, __, __, __, __, __, __, __, __, __, BS, __, __, __, // 5
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 6
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 7
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 8
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // 9
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // A
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // B
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // C
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // D
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // E
    __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, __, // F
};
