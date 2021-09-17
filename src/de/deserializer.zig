const getty = @import("getty");
const std = @import("std");

pub const Deserializer = struct {
    allocator: ?*std.mem.Allocator = null,
    tokens: std.json.TokenStream,

    const Self = @This();

    pub fn init(comptime slice: []const u8) Self {
        return Self{
            .tokens = std.json.TokenStream.init(slice),
        };
    }

    pub fn new(allocator: *std.mem.Allocator, reader: anytype) Self {
        var d = Self{
            .allocator = allocator,
            .tokens = blk: {
                const slice = reader.readAllAlloc(allocator, 10 * 1024 * 1024) catch unreachable;
                break :blk std.json.TokenStream.init(slice);
            },
        };

        return d;
    }

    pub fn destroy(self: *Self) void {
        if (self.allocator) |allocator| {
            allocator.free(self.tokens.slice);
        }
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
        deserializeMap,
        deserializeOptional,
        deserializeSequence,
        deserializeSlice,
        deserializeStruct,
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
                    std.fmt.parseFloat(@TypeOf(visitor).Value, num.slice(self.tokens.slice, self.tokens.i - 1)) catch return Error.Input,
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
                        std.fmt.parseInt(@TypeOf(visitor).Value, num.slice(self.tokens.slice, self.tokens.i - 1), 10) catch return Error.Input,
                    ),
                    false => return visitor.visitFloat(
                        Error,
                        std.fmt.parseFloat(f128, num.slice(self.tokens.slice, self.tokens.i - 1)) catch return Error.Input,
                    ),
                },
                else => {},
            }
        }

        return Error.Input;
    }

    fn deserializeMap(self: *Self, allocator: ?*std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            if (token == .ObjectBegin) {
                var access = MapAccess(
                    @typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?,
                    Error,
                ){ .allocator = allocator, .d = self.deserializer() };

                return try visitor.visitMap(allocator, access.mapAccess());
            }
        }

        return Error.Input;
    }

    fn deserializeSequence(self: *Self, allocator: ?*std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            if (token == .ArrayBegin) {
                var access = SequenceAccess(
                    @typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?,
                    Error,
                ){ .allocator = allocator, .d = self.deserializer() };

                return try visitor.visitSequence(allocator, access.sequenceAccess());
            }
        }

        return Error.Input;
    }

    fn deserializeSlice(self: *Self, allocator: *std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            switch (token) {
                .ArrayBegin => {
                    var access = SequenceAccess(
                        @typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?,
                        Error,
                    ){ .allocator = allocator, .d = self.deserializer() };

                    return try visitor.visitSequence(allocator, access.sequenceAccess());
                },
                .String => |str| {
                    if (std.meta.Child(@TypeOf(visitor).Value) == u8) {
                        return visitor.visitSlice(
                            allocator,
                            Error,
                            str.slice(self.tokens.slice, self.tokens.i - 1),
                        ) catch Error.Input;
                    }
                },
                else => {},
            }
        }

        return Error.Input;
    }

    fn deserializeStruct(self: *Self, allocator: ?*std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
        return try deserializeMap(self, allocator, visitor);
    }

    fn deserializeOptional(self: *Self, allocator: ?*std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
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
                    break :blk visitor.visitSome(allocator, self.deserializer());
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

fn SequenceAccess(comptime D: type, comptime Error: type) type {
    return struct {
        allocator: ?*std.mem.Allocator,
        d: D,

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
            return try seed.deserialize(a.allocator, a.d);
        }
    };
}

fn MapAccess(comptime D: type, comptime Error: type) type {
    return struct {
        allocator: ?*std.mem.Allocator,
        d: D,

        pub usingnamespace getty.de.MapAccess(
            *@This(),
            Error,
            nextKeySeed,
            nextValueSeed,
        );

        fn nextKeySeed(a: *@This(), seed: anytype) !?@TypeOf(seed).Value {
            const tokens = a.d.context.tokens;

            if (a.d.context.tokens.next() catch return Error.Input) |token| {
                if (token == .ObjectEnd) {
                    return null;
                }
            } else {
                return Error.Input;
            }

            a.d.context.tokens = tokens;
            return try seed.deserialize(a.allocator, a.d);
        }

        fn nextValueSeed(a: *@This(), seed: anytype) !@TypeOf(seed).Value {
            return try seed.deserialize(a.allocator, a.d);
        }
    };
}
