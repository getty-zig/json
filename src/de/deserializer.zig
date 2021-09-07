const getty = @import("getty");
const std = @import("std");

pub fn Deserializer(comptime Reader: type) type {
    return struct {
        buffer: std.ArrayList(u8),
        reader: Reader,
        tokens: std.json.TokenStream,

        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator, reader: Reader) Self {
            var d = Self{
                .buffer = std.ArrayList(u8).init(allocator),
                .reader = reader,
                .tokens = undefined,
            };
            d.reader.readAllArrayList(&d.buffer, 10 * 1024 * 1024) catch unreachable;
            d.tokens = std.json.TokenStream.init(d.buffer.items);
            return d;
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        /// Implements `getty.de.Deserializer`.
        pub usingnamespace getty.de.Deserializer(
            *Self,
            Error,
            deserializeBool,
            undefined,
            //deserializeEnum,
            deserializeFloat,
            deserializeInt,
            undefined,
            //deserializeMap,
            deserializeOptional,
            deserializeSequence,
            undefined,
            //deserializeString,
            undefined,
            //deserializeStruct,
            deserializeVoid,
        );

        const Error = error{Input};

        fn deserializeBool(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .True => return try visitor.visitBool(Error, true),
                    .False => return try visitor.visitBool(Error, false),
                    else => {},
                }
            }

            return Error.Input;
        }

        fn deserializeFloat(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .Number => |num| return try visitor.visitFloat(
                        Error,
                        std.fmt.parseFloat(@TypeOf(visitor).Value, num.slice(self.buffer.items, self.tokens.i - 1)) catch return Error.Input,
                    ),
                    else => {},
                }
            }

            return Error.Input;
        }

        fn deserializeInt(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .Number => |num| switch (num.is_integer) {
                        true => return try visitor.visitInt(
                            Error,
                            std.fmt.parseInt(@TypeOf(visitor).Value, num.slice(self.buffer.items, self.tokens.i - 1), 10) catch return Error.Input,
                        ),
                        false => return visitor.visitFloat(
                            Error,
                            std.fmt.parseFloat(f128, num.slice(self.buffer.items, self.tokens.i - 1)) catch return Error.Input,
                        ),
                    },
                    else => {},
                }
            }

            return Error.Input;
        }

        fn deserializeSequence(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
            var access = struct {
                d: @typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?,

                pub usingnamespace getty.de.SequenceAccess(
                    *@This(),
                    Error,
                    nextElementSeed,
                );

                fn nextElementSeed(a: *@This(), seed: anytype) !?@TypeOf(seed).Value {
                    const tokens = a.d.context.tokens;

                    if (a.d.context.tokens.next() catch return Error.Input) |token| {
                        if (token == .ArrayEnd) {
                            return null;
                        }
                    } else {
                        return Error.Input;
                    }

                    a.d.context.tokens = tokens;
                    return try seed.deserialize(a.d);
                }
            }{ .d = self.deserializer() };

            if (self.tokens.next() catch return Error.Input) |token| {
                if (token == .ArrayBegin) {
                    const value = try visitor.visitSequence(access.sequenceAccess());

                    if (self.tokens.next() catch return Error.Input) |tok| {
                        if (tok == .ArrayEnd) {
                            return value;
                        }
                    }
                }
            }

            return Error.Input;
        }

        fn deserializeOptional(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
            const tokens = self.tokens;

            if (self.tokens.next() catch return Error.Input) |token| {
                return try switch (token) {
                    .Null => visitor.visitNull(Error),
                    else => blk: {
                        // Get back the token we just ate if it was an
                        // actual value so that whenever the next
                        // deserialize method is called by visitSome,
                        // they'll eat the token we just saw instead of
                        // whatever is after it.
                        self.tokens = tokens;
                        break :blk visitor.visitSome(self.deserializer());
                    },
                };
            }

            return Error.Input;
        }

        fn deserializeVoid(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                if (token == .Null) {
                    return try visitor.visitVoid(Error);
                }
            }

            return Error.Input;
        }
    };
}
