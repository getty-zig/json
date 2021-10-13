const getty = @import("getty");
const std = @import("std");

pub usingnamespace @import("de.zig");
pub usingnamespace @import("ser.zig");

pub fn free(allocator: *std.mem.Allocator, value: anytype) void {
    return getty.free(allocator, value);
}

test {
    @import("std").testing.refAllDecls(@This());
}
