const getty = @import("getty");
const std = @import("std");

pub fn Deserializer(comptime Reader: type) type {
    return struct {
        reader: Reader,
        scratch: std.ArrayList(u8),
        //remaining_depth: u8 = 128,
        //single_precision: bool = false,
        //disable_recursion_limit: bool = false,

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator, reader: Reader) Self {
            var d = Self{
                .reader = reader,
                .scratch = std.ArrayList(u8).init(allocator),
            };
            d.reader.readAllArrayList(&d.scratch, 10 * 1024 * 1024) catch unreachable;
            return d;
        }

        pub fn deinit(self: *Self) void {
            self.scratch.deinit();
        }

        pub fn deserializer(self: *Self) D {
            return .{ .context = self };
        }

        const D = getty.de.Deserializer(
            *Self,
            _D.Error,
            _D.deserializeBool,
            undefined,
            //_D.deserializeEnum,
            _D.deserializeFloat,
            _D.deserializeInt,
            undefined,
            //_D.deserializeMap,
            undefined,
            //_D.deserializeOptional,
            undefined,
            //_D.deserializeSequence,
            undefined,
            //_D.deserializeString,
            undefined,
            //_D.deserializeStruct,
            undefined,
            //_D.deserializeVoid,
        );

        const _D = struct {
            const Error = error{Input};

            fn deserializeBool(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    switch (token) {
                        .True => return try visitor.visitBool(Error, true),
                        .False => return try visitor.visitBool(Error, false),
                        else => {},
                    }
                }

                return Error.Input;
            }

            fn deserializeInt(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    switch (token) {
                        .Number => |num| {
                            if (!num.is_integer) return Error.Input;

                            return try visitor.visitInt(Error, std.fmt.parseInt(@TypeOf(visitor).Value, self.scratch.items, 10) catch return Error.Input);
                        },
                        else => {},
                    }
                }

                return Error.Input;
            }

            fn deserializeFloat(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
                var tokens = std.json.TokenStream.init(self.scratch.items);

                if (tokens.next() catch return Error.Input) |token| {
                    switch (token) {
                        .Number => |num| {
                            if (num.is_integer) return Error.Input;

                            return try visitor.visitFloat(Error, std.fmt.parseFloat(@TypeOf(visitor).Value, self.scratch.items) catch return Error.Input);
                        },
                        else => {},
                    }
                }

                return Error.Input;
            }
        };
    };
}

pub fn fromReader(allocator: *std.mem.Allocator, comptime T: type, reader: anytype) !T {
    var deserializer = Deserializer(@TypeOf(reader)).init(allocator, reader);
    defer deserializer.deinit();

    return try getty.deserialize(T, deserializer.deserializer());
}

pub fn fromString(allocator: *std.mem.Allocator, comptime T: type, string: []const u8) !T {
    var fbs = std.io.fixedBufferStream(string);
    return try fromReader(allocator, T, fbs.reader());
}

test {
    try std.testing.expectEqual(true, try fromString(std.testing.allocator, bool, "true"));
    try std.testing.expectEqual(false, try fromString(std.testing.allocator, bool, "false"));
}

test {
    try std.testing.expectEqual(@as(u32, 1), try fromString(std.testing.allocator, u32, "1"));
    try std.testing.expectEqual(@as(i32, -1), try fromString(std.testing.allocator, i32, "-1"));
}

test {
    try std.testing.expectEqual(@as(f32, 3.14), try fromString(std.testing.allocator, f32, "3.14"));
    try std.testing.expectEqual(@as(f64, 3.14), try fromString(std.testing.allocator, f64, "3.14"));
}

test {
    std.testing.refAllDecls(@This());
}
