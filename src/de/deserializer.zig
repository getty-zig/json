const getty = @import("getty");
const std = @import("std");

pub const Deserializer = struct {
    allocator: ?*std.mem.Allocator = null,
    scratch: ?[]u8 = null,
    tokens: std.json.TokenStream,

    const Self = @This();
    const impl = @"impl Deserializer";

    pub fn init(slice: []const u8) Self {
        return Self{ .tokens = std.json.TokenStream.init(slice) };
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
            .scratch = reader.readAllAlloc(allocator, 10 * 1024 * 1024),
            .tokens = undefined,
        };

        d.tokens = std.json.TokenStream.init(d.scratch.?);

        return d;
    }

    pub fn deinit(self: Self) void {
        if (self.scratch) |scratch| {
            self.allocator.?.free(scratch);
        }
    }

    pub fn destroy(self: *Self) void {
        self.deinit();
        self.* = undefined;
    }

    /// Validates that the input data has been fully deserialized.
    ///
    /// This method should always be called after a value has been fully
    /// deserialized.
    pub fn end(self: *Self) !void {
        if (self.tokens.next() catch return impl.deserializer.Error.Input) |_| {
            return impl.deserializer.Error.Input;
        }
    }

    pub usingnamespace getty.Deserializer(
        *Self,
        impl.deserializer.Error,
        impl.deserializer.deserializeBool,
        impl.deserializer.deserializeEnum,
        impl.deserializer.deserializeFloat,
        impl.deserializer.deserializeInt,
        impl.deserializer.deserializeMap,
        impl.deserializer.deserializeOptional,
        impl.deserializer.deserializeSequence,
        impl.deserializer.deserializeString,
        impl.deserializer.deserializeStruct,
        impl.deserializer.deserializeVoid,
    );
};

const @"impl Deserializer" = struct {
    const deserializer = struct {
        const Error = getty.de.Error || error{Input};

        /// Hint that the type being deserialized into is expecting a `bool` value.
        fn deserializeBool(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .True => return try visitor.visitBool(Error, true),
                    .False => return try visitor.visitBool(Error, false),
                    else => {},
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting an `enum`
        /// value.
        fn deserializeEnum(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        if (num.is_integer) {
                            return try switch (slice[0]) {
                                '-' => visitor.visitInt(Error, parseSigned(slice) catch return Error.Input),
                                else => visitor.visitInt(Error, parseUnsigned(slice) catch return Error.Input),
                            };
                        }
                    },
                    .String => |str| return try visitor.visitString(
                        Error,
                        str.slice(self.tokens.slice, self.tokens.i - 1),
                    ),
                    else => {},
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting a
        /// floating-point value.
        fn deserializeFloat(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        return try visitor.visitFloat(
                            Error,
                            std.fmt.parseFloat(f128, slice) catch return Error.Input,
                        );
                    },
                    else => {},
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting an
        /// integer value.
        fn deserializeInt(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        switch (num.is_integer) {
                            true => return try switch (slice[0]) {
                                '-' => visitor.visitInt(Error, parseSigned(slice) catch return Error.Input),
                                else => visitor.visitInt(Error, parseUnsigned(slice) catch return Error.Input),
                            },
                            false => {},
                        }
                    },
                    else => {},
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting a map of
        /// key-value pairs.
        fn deserializeMap(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                if (token == .ObjectBegin) {
                    var access = Access{
                        .allocator = self.allocator,
                        .deserializer = self,
                    };

                    return try visitor.visitMap(access.mapAccess());
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting an optional
        /// value.
        fn deserializeOptional(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            const tokens = self.tokens;

            if (self.tokens.next() catch return Error.Input) |token| {
                return try switch (token) {
                    .Null => visitor.visitNull(Error),
                    else => blk: {
                        // Get back the token we just ate if it was an actual
                        // value so that whenever the next deserialize method
                        // is called by visitSome, it'll eat the token we just
                        // saw instead of whatever comes after it.
                        self.tokens = tokens;
                        break :blk visitor.visitSome(self.deserializer());
                    },
                };
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting a sequence of
        /// values.
        fn deserializeSequence(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                if (token == .ArrayBegin) {
                    var access = Access{
                        .allocator = self.allocator,
                        .deserializer = self,
                    };

                    return try visitor.visitSequence(access.sequenceAccess());
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting a string value.
        fn deserializeString(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                switch (token) {
                    .String => |str| return try visitor.visitString(
                        Error,
                        str.slice(self.tokens.slice, self.tokens.i - 1),
                    ),
                    else => {},
                }
            }

            return Error.Input;
        }

        /// Hint that the type being deserialized into is expecting a struct value.
        fn deserializeStruct(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            return try deserializeMap(self, visitor);
        }

        /// Hint that the type being deserialized into is expecting a `void` value.
        fn deserializeVoid(self: *Deserializer, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (self.tokens.next() catch return Error.Input) |token| {
                if (token == .Null) {
                    return try visitor.visitVoid(Error);
                }
            }

            return Error.Input;
        }
    };
};

const Access = struct {
    allocator: ?*std.mem.Allocator,
    deserializer: *Deserializer,

    const Self = @This();
    const impl = @"impl Access";

    const Error = @"impl Deserializer".deserializer.Error;

    pub usingnamespace getty.de.SequenceAccess(
        *Self,
        Error,
        impl.sequenceAccess.nextElementSeed,
    );

    pub usingnamespace getty.de.MapAccess(
        *Self,
        Error,
        impl.mapAccess.nextKeySeed,
        impl.mapAccess.nextValueSeed,
    );
};

const @"impl Access" = struct {
    const sequenceAccess = struct {
        fn nextElementSeed(self: *Access, seed: anytype) Access.Error!?@TypeOf(seed).Value {
            const tokens = self.deserializer.tokens;

            if (self.deserializer.tokens.next() catch return error.Input) |token| {
                if (token == .ArrayEnd) {
                    return null;
                }
            } else {
                return error.Input;
            }

            self.deserializer.tokens = tokens;
            return try seed.deserialize(self.allocator, self.deserializer.deserializer());
        }
    };

    const mapAccess = struct {
        fn nextKeySeed(self: *Access, seed: anytype) Access.Error!?@TypeOf(seed).Value {
            if (self.deserializer.tokens.next() catch return error.Input) |token| {
                return switch (token) {
                    .ObjectEnd => null,
                    .String => |str| str.slice(self.deserializer.tokens.slice, self.deserializer.tokens.i - 1),
                    else => error.Input,
                };
            }

            return error.Input;
        }

        fn nextValueSeed(self: *Access, seed: anytype) Access.Error!@TypeOf(seed).Value {
            return try seed.deserialize(self.allocator, self.deserializer.deserializer());
        }
    };
};

fn parseInt(comptime T: type, buf: []const u8) std.fmt.ParseIntError!T {
    comptime std.debug.assert(T == u64 or T == i64);

    if (buf.len == 0) return error.InvalidCharacter;

    var start = buf;
    var sign: enum { pos, neg } = .pos;

    switch (buf[0]) {
        '0'...'9' => {},
        '+' => start = buf[1..],
        '-' => {
            sign = .neg;
            start = buf[1..];
        },
        else => return error.InvalidCharacter,
    }

    if (start[0] == '_' or start[start.len - 1] == '_') {
        return error.InvalidCharacter;
    }

    const radix: T = 10;
    var int: T = 0;

    for (start) |c| {
        if (c == '_') {
            continue;
        }

        const digit = try std.fmt.charToDigit(c, radix);

        if (int != 0) {
            // TODO: Does math.cast not accept comptime_int?
            int = try std.math.mul(T, int, try std.math.cast(T, radix));
        }

        int = switch (sign) {
            .pos => try std.math.add(T, int, try std.math.cast(T, digit)),
            .neg => try std.math.sub(T, int, try std.math.cast(T, digit)),
        };
    }

    return int;
}

fn parseSigned(buf: []const u8) std.fmt.ParseIntError!i64 {
    return try parseInt(i64, buf);
}

fn parseUnsigned(buf: []const u8) std.fmt.ParseIntError!u64 {
    return try parseInt(u64, buf);
}
