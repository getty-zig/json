const getty = @import("getty");
const std = @import("std");

pub const Deserializer = struct {
    buffer: std.ArrayList(u8),
    tokens: std.json.TokenStream,

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, reader: anytype) Self {
        var d = Self{
            .buffer = std.ArrayList(u8).init(allocator),
            .tokens = undefined,
        };
        reader.readAllArrayList(&d.buffer, 10 * 1024 * 1024) catch unreachable;
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
        var access = struct {
            allocator: ?*std.mem.Allocator,
            d: @typeInfo(@TypeOf(Self.deserializer)).Fn.return_type.?,

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
                //const tokens = a.d.context.tokens;

                //if (a.d.context.tokens.next() catch return Error.Input) |token| {
                //if (token == .ObjectEnd) {
                //return null;
                //}
                //} else {
                //return Error.Input;
                //}

                //a.d.context.tokens = tokens;
                return try seed.deserialize(a.allocator, a.d);
            }
        }{
            .allocator = allocator,
            .d = self.deserializer(),
        };

        if (self.tokens.next() catch return Error.Input) |token| {
            if (token == .ObjectBegin) {
                const value = try visitor.visitMap(allocator, access.mapAccess());

                if (self.tokens.next() catch return Error.Input) |tok| {
                    if (tok == .ObjectEnd) {
                        return value;
                    }
                }
            }
        }

        return Error.Input;
    }

    fn deserializeSequence(self: *Self, allocator: ?*std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
        _ = allocator;

        var access = struct {
            allocator: ?*std.mem.Allocator,
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
                return try seed.deserialize(a.allocator, a.d);
            }
        }{
            .allocator = allocator,
            .d = self.deserializer(),
        };

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

    fn deserializeSlice(self: *Self, allocator: *std.mem.Allocator, visitor: anytype) !@TypeOf(visitor).Value {
        if (self.tokens.next() catch return Error.Input) |token| {
            switch (token) {
                .String => |str| return visitor.visitSlice(allocator, Error, str.slice(self.tokens.slice, self.tokens.i - 1)) catch Error.Input,
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
