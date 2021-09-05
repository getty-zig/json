pub usingnamespace @import("de.zig");
pub usingnamespace @import("ser.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
