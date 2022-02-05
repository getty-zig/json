const concepts = @import("concepts");
const getty = @import("getty");
const std = @import("std");

pub fn Deserializer(comptime with: anytype) type {
    return struct {
        allocator: ?std.mem.Allocator = null,
        tokens: std.json.TokenStream,

        const Self = @This();

        pub fn init(slice: []const u8) Self {
            return Self{
                .tokens = std.json.TokenStream.init(slice),
            };
        }

        pub fn withAllocator(allocator: std.mem.Allocator, slice: []const u8) Self {
            return Self{
                .allocator = allocator,
                .tokens = std.json.TokenStream.init(slice),
            };
        }

        /// Validates that the input data has been fully deserialized.
        ///
        /// This method should always be called after a value has been fully
        /// deserialized.
        pub fn end(self: *Self) Error!void {
            if (self.tokens.i < self.tokens.slice.len or !self.tokens.parser.complete) {
                return error.InvalidTopLevelTrailing;
            }
        }

        pub usingnamespace getty.Deserializer(
            *Self,
            Error,
            with,
            getty.de.default_with,
            deserializeBool,
            deserializeEnum,
            deserializeFloat,
            deserializeInt,
            deserializeMap,
            deserializeOptional,
            deserializeSequence,
            deserializeString,
            deserializeStruct,
            deserializeVoid,
        );

        pub const Error = getty.de.Error ||
            std.json.TokenStream.Error ||
            std.fmt.ParseIntError ||
            std.fmt.ParseFloatError;

        /// Hint that the type being deserialized into is expecting a `bool` value.
        pub fn deserializeBool(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .True => return try visitor.visitBool(Error, true),
                    .False => return try visitor.visitBool(Error, false),
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an `enum`
        /// value.
        pub fn deserializeEnum(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        if (num.is_integer) {
                            return try switch (slice[0]) {
                                '-' => visitor.visitInt(Error, try parseSigned(slice)),
                                else => visitor.visitInt(Error, try parseUnsigned(slice)),
                            };
                        }
                    },
                    .String => |str| {
                        const slice = str.slice(self.tokens.slice, self.tokens.i - 1);
                        return try visitor.visitString(Error, try self.allocator.?.dupe(u8, slice));
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a
        /// floating-point value.
        pub fn deserializeFloat(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);
                        return try visitor.visitFloat(Error, try std.fmt.parseFloat(f128, slice));
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an
        /// integer value.
        pub fn deserializeInt(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        switch (num.is_integer) {
                            true => return try switch (slice[0]) {
                                '-' => visitor.visitInt(Error, try parseSigned(slice)),
                                else => visitor.visitInt(Error, try parseUnsigned(slice)),
                            },
                            false => {},
                        }
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a map of
        /// key-value pairs.
        pub fn deserializeMap(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var access = MapAccess(Self){ .allocator = self.allocator, .deserializer = self };
                    return try visitor.visitMap(access.mapAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an optional
        /// value.
        pub fn deserializeOptional(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            const tokens = self.tokens;

            if (try self.tokens.next()) |token| {
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

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a sequence of
        /// values.
        pub fn deserializeSequence(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ArrayBegin) {
                    var access = SeqAccess(Self){ .allocator = self.allocator, .deserializer = self };
                    return try visitor.visitSequence(access.sequenceAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a string value.
        pub fn deserializeString(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .String => |str| {
                        const slice = str.slice(self.tokens.slice, self.tokens.i - 1);
                        return visitor.visitString(Error, try self.allocator.?.dupe(u8, slice));
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a struct value.
        pub fn deserializeStruct(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            return try deserializeMap(self, visitor);
        }

        /// Hint that the type being deserialized into is expecting a `void` value.
        pub fn deserializeVoid(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Null) {
                    return try visitor.visitVoid(Error);
                }
            }

            return error.InvalidType;
        }

        fn parseInt(comptime T: type, buf: []const u8) std.fmt.ParseIntError!T {
            comptime std.debug.assert(T == u128 or T == i128);

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

        fn parseSigned(buf: []const u8) Error!i128 {
            return try parseInt(i128, buf);
        }

        fn parseUnsigned(buf: []const u8) Error!u128 {
            return try parseInt(u128, buf);
        }
    };
}

fn SeqAccess(comptime D: type) type {
    return struct {
        allocator: ?std.mem.Allocator,
        deserializer: *D,

        const Self = @This();

        pub usingnamespace getty.de.SequenceAccess(
            *Self,
            Error,
            nextElementSeed,
        );

        const Error = D.Error;

        pub fn nextElementSeed(self: *Self, seed: anytype) Error!?@TypeOf(seed).Value {
            const element = seed.deserialize(self.allocator, self.deserializer.deserializer()) catch |err| {
                // Slice for the current token instead of looking at the
                // `token` field since the token isn't set for some reason.
                if (self.deserializer.tokens.i - 1 >= self.deserializer.tokens.slice.len) {
                    return err;
                }

                return switch (self.deserializer.tokens.slice[self.deserializer.tokens.i - 1]) {
                    ']' => null,
                    else => err,
                };
            };

            return element;
        }
    };
}

fn MapAccess(comptime D: type) type {
    return struct {
        allocator: ?std.mem.Allocator,
        deserializer: *D,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            Error,
            nextKeySeed,
            nextValueSeed,
        );

        pub const Error = D.Error;

        pub fn nextKeySeed(self: *Self, seed: anytype) Error!?@TypeOf(seed).Value {
            comptime concepts.Concept("StringKey", "expected key type to be `[]const u8`")(.{
                concepts.traits.isSame(@TypeOf(seed).Value, []const u8),
            });

            if (try self.deserializer.tokens.next()) |token| {
                switch (token) {
                    .ObjectEnd => return null,
                    .String => |str| {
                        const slice = str.slice(self.deserializer.tokens.slice, self.deserializer.tokens.i - 1);
                        return try self.allocator.?.dupe(u8, slice);
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        pub fn nextValueSeed(self: *Self, seed: anytype) Error!@TypeOf(seed).Value {
            return try seed.deserialize(self.allocator, self.deserializer.deserializer());
        }
    };
}
