const getty = @import("getty");
const std = @import("std");

pub const Deserializer = struct {
    allocator: ?*std.mem.Allocator = null,
    buffer: ?std.ArrayList(u8) = null,
    tokens: std.json.TokenStream,

    const Self = @This();

    pub fn init(slice: []const u8) Self {
        return Self{
            .tokens = std.json.TokenStream.init(slice),
        };
    }

    pub fn withAllocator(allocator: *std.mem.Allocator, slice: []const u8) Self {
        return Self{
            .allocator = allocator,
            .tokens = std.json.TokenStream.init(slice),
        };
    }

    pub fn fromReader(allocator: *std.mem.Allocator, reader: anytype) !Self {
        var d = Self{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .tokens = undefined,
        };

        try reader.readAllArrayList(d.buffer.?, 10 * 1024 * 1024);
        d.tokens = std.json.TokenStream.init(d.buffer.?.items);

        return d;
    }

    pub fn deinit(self: *Self) void {
        if (self.buffer) |list| {
            list.deinit();
        }
    }

    /// Validates that the input data has been fully deserialized.
    ///
    /// This method should always be called after a value has been fully
    /// deserialized.
    pub fn end(self: *Self) !void {
        if (self.tokens.next() catch return Error.Input) |_| return Error.Input else {}
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

    fn deserializeMap(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            if (token == .ObjectBegin) {
                var access = MapAccess(@typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?, Error){
                    .arena = if (self.allocator) |allocator| std.heap.ArenaAllocator.init(allocator) else null,
                    .d = self.deserializer(),
                };
                errdefer if (access.arena) |arena| arena.deinit();

                return try visitor.visitMap(access.mapAccess());
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

    fn deserializeSequence(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            if (token == .ArrayBegin) {
                var access = SequenceAccess(@typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?, Error){
                    .allocator = self.allocator,
                    .d = self.deserializer(),
                };

                return try visitor.visitSequence(access.sequenceAccess());
            }
        }

        return Error.Input;
    }

    fn deserializeSlice(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            switch (token) {
                .ArrayBegin => {
                    var access = SequenceAccess(
                        @typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?,
                        Error,
                    ){
                        .allocator = self.allocator,
                        .d = self.deserializer(),
                    };

                    return try visitor.visitSequence(access.sequenceAccess());
                },
                .String => |str| {
                    if (std.meta.Child(@TypeOf(visitor).Value) == u8) {
                        return visitor.visitSlice(
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

    fn deserializeStruct(self: *Self, visitor: anytype) !@TypeOf(visitor).Value {
        return try deserializeMap(self, visitor);
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

        /// Implements `getty.de.SequenceAccess`.
        pub usingnamespace getty.de.SequenceAccess(
            *@This(),
            Error,
            nextElementSeed,
        );

        fn nextElementSeed(self: *@This(), seed: anytype) !?@TypeOf(seed).Value {
            const tokens = self.d.context.tokens;

            if (self.d.context.tokens.next() catch return Error.Input) |token| {
                if (token == .ArrayEnd) {
                    return null;
                }
            } else {
                return Error.Input;
            }

            self.d.context.tokens = tokens;
            return try seed.deserialize(self.allocator orelse null, self.d);
        }
    };
}

fn MapAccess(comptime D: type, comptime Error: type) type {
    return struct {
        arena: ?std.heap.ArenaAllocator,
        d: D,

        /// Implements `getty.de.MapAccess`.
        pub usingnamespace getty.de.MapAccess(
            *@This(),
            Error,
            nextKeySeed,
            nextValueSeed,
        );

        fn nextKeySeed(self: *@This(), seed: anytype) !?@TypeOf(seed).Value {
            if (self.d.context.tokens.next() catch return Error.Input) |token| {
                return switch (token) {
                    .ObjectEnd => null,
                    .String => |str| str.slice(self.d.context.tokens.slice, self.d.context.tokens.i - 1),
                    else => Error.Input,
                };
            }

            return Error.Input;
        }

        fn nextValueSeed(self: *@This(), seed: anytype) !@TypeOf(seed).Value {
            return try seed.deserialize(if (self.arena) |*arena| &arena.allocator else null, self.d);
        }
    };
}
