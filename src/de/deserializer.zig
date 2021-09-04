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
            //_D.deserializeBool,
            undefined,
            //_D.deserializeEnum,
            undefined,
            //_D.deserializeFloat,
            undefined,
            //_D.deserializeInt,
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
                    return try switch (token) {
                        .True => visitor.visitBool(Error, true),
                        .False => visitor.visitBool(Error, false),
                        else => Error.Input,
                    };
                }

                return Error.Input;
            }
        };
    };
}

pub fn fromString(allocator: *std.mem.Allocator, comptime T: type, string: []const u8) !T {
    var fbs = std.io.fixedBufferStream(string);
    const reader = fbs.reader();

    var deserializer = Deserializer(@TypeOf(reader)).init(allocator, reader);
    defer deserializer.deinit();

    return try getty.deserialize(T, deserializer.deserializer());
}

test {
    try std.testing.expectEqual(true, try fromString(std.testing.allocator, bool, "true"));
    try std.testing.expectEqual(false, try fromString(std.testing.allocator, bool, "false"));
}

test {
    std.testing.refAllDecls(@This());
}
