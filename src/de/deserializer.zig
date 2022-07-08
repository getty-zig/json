const concepts = @import("concepts");
const getty = @import("getty");
const std = @import("std");

pub fn Deserializer(comptime user_dbt: anytype) type {
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
            user_dbt,
            getty.default_dt,
            deserializeBool,
            deserializeEnum,
            deserializeFloat,
            deserializeInt,
            deserializeMap,
            deserializeOptional,
            deserializeSeq,
            deserializeString,
            deserializeStruct,
            deserializeUnion,
            deserializeVoid,
        );

        const Error = getty.de.Error ||
            std.json.TokenStream.Error ||
            std.fmt.ParseIntError ||
            std.fmt.ParseFloatError;

        const De = Self.@"getty.Deserializer";

        /// Hint that the type being deserialized into is expecting a `bool` value.
        fn deserializeBool(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .True or token == .False) {
                    return try visitor.visitBool(allocator, De, token == .True);
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an `enum`
        /// value.
        fn deserializeEnum(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Number and token.Number.is_integer) {
                    return try self._deserializeInt(allocator, token, visitor);
                }

                if (token == .String) {
                    const slice = token.String.slice(self.tokens.slice, self.tokens.i - 1);
                    return try visitor.visitString(allocator, De, slice);
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a
        /// floating-point value.
        fn deserializeFloat(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Number) {
                    const slice = token.Number.slice(self.tokens.slice, self.tokens.i - 1);
                    return try visitor.visitFloat(allocator, De, try std.fmt.parseFloat(f128, slice));
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an
        /// integer value.
        fn deserializeInt(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Number and token.Number.is_integer) {
                    return try self._deserializeInt(allocator, token, visitor);
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a map of
        /// key-value pairs.
        fn deserializeMap(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var map = Map(Self){ .de = self };
                    return try visitor.visitMap(allocator, De, map.map());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an optional
        /// value.
        fn deserializeOptional(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const tokens = self.tokens;

            if (try self.tokens.next()) |token| {
                if (token == .Null) {
                    return try visitor.visitNull(allocator, De);
                }

                // Get back the token we just ate if it was an actual
                // value so that whenever the next deserialize method
                // is called by visitSome, it'll eat the token we just
                // saw instead of whatever comes after it.
                self.tokens = tokens;
                return try visitor.visitSome(allocator, self.deserializer());
            }

            // TODO: If we're here, it's because there's no more tokens. So is
            // this the right error to return?
            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a sequence of
        /// values.
        fn deserializeSeq(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ArrayBegin) {
                    var sa = SeqAccess(Self){ .de = self };
                    return try visitor.visitSeq(allocator, De, sa.seqAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a string value.
        fn deserializeString(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .String) {
                    const slice = token.String.slice(self.tokens.slice, self.tokens.i - 1);
                    return visitor.visitString(allocator, De, try self.allocator.?.dupe(u8, slice));
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a struct value.
        fn deserializeStruct(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var s = Struct(Self){ .de = self };
                    return try visitor.visitMap(allocator, De, s.map());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a union value.
        fn deserializeUnion(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const backup = self.tokens;

            if (try self.tokens.next()) |token| {
                if (token == .String) {
                    self.tokens = backup;
                }

                if (token == .String or token == .ObjectBegin) {
                    var u = Union(Self){ .de = self };
                    return try visitor.visitUnion(allocator, De, u.unionAccess(), u.variantAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a `void` value.
        fn deserializeVoid(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Null) {
                    return try visitor.visitVoid(allocator, De);
                }
            }

            return error.InvalidType;
        }

        fn _deserializeInt(self: Self, allocator: ?std.mem.Allocator, token: std.json.Token, visitor: anytype) Error!@TypeOf(visitor).Value {
            std.debug.assert(std.meta.activeTag(token) == std.json.Token.Number);
            std.debug.assert(token.Number.is_integer);

            const slice = token.Number.slice(self.tokens.slice, self.tokens.i - 1);

            return try switch (slice[0]) {
                '-' => visitor.visitInt(allocator, De, try parseInt(i128, slice)),
                else => visitor.visitInt(allocator, De, try parseInt(u128, slice)),
            };
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
                    int = try std.math.mul(T, int, std.math.cast(T, radix) orelse return error.Overflow);
                }

                int = switch (sign) {
                    .pos => try std.math.add(T, int, std.math.cast(T, digit) orelse return error.Overflow),
                    .neg => try std.math.sub(T, int, std.math.cast(T, digit) orelse return error.Overflow),
                };
            }

            return int;
        }
    };
}

fn Map(comptime De: type) type {
    return struct {
        de: *De,

        const Self = @This();

        pub usingnamespace getty.de.Map(
            *Self,
            De.Error,
            nextKeySeed,
            nextValueSeed,
        );

        fn nextKeySeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) De.Error!?@TypeOf(seed).Value {
            comptime concepts.Concept("StringKey", "expected key type to be `[]const u8`")(.{
                concepts.traits.isSame(@TypeOf(seed).Value, []const u8),
            });

            if (try self.de.tokens.next()) |token| {
                if (token == .ObjectEnd) {
                    return null;
                }

                if (token == .String) {
                    const slice = token.String.slice(self.de.tokens.slice, self.de.tokens.i - 1);
                    return try allocator.?.dupe(u8, slice);
                }
            }

            return error.InvalidType;
        }

        fn nextValueSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) De.Error!@TypeOf(seed).Value {
            return try seed.deserialize(allocator, self.de.deserializer());
        }
    };
}

fn SeqAccess(comptime De: type) type {
    return struct {
        de: *De,

        const Self = @This();

        pub usingnamespace getty.de.SeqAccess(
            *Self,
            De.Error,
            nextElementSeed,
        );

        fn nextElementSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) De.Error!?@TypeOf(seed).Value {
            const element = seed.deserialize(allocator, self.de.deserializer()) catch |err| {
                // Slice for the current token instead of looking at the
                // `token` field since the token isn't set for some reason.
                if (self.de.tokens.i - 1 >= self.de.tokens.slice.len) {
                    return err;
                }

                return switch (self.de.tokens.slice[self.de.tokens.i - 1]) {
                    ']' => null,
                    else => err,
                };
            };

            return element;
        }
    };
}

fn Struct(comptime De: type) type {
    return struct {
        de: *De,

        const Self = @This();

        pub usingnamespace getty.de.Map(
            *Self,
            De.Error,
            nextKeySeed,
            nextValueSeed,
        );

        fn nextKeySeed(self: *Self, _: ?std.mem.Allocator, seed: anytype) De.Error!?@TypeOf(seed).Value {
            comptime concepts.Concept("StringKey", "expected key type to be `[]const u8`")(.{
                concepts.traits.isSame(@TypeOf(seed).Value, []const u8),
            });

            if (try self.de.tokens.next()) |token| {
                if (token == .ObjectEnd) {
                    return null;
                }

                if (token == .String) {
                    return token.String.slice(self.de.tokens.slice, self.de.tokens.i - 1);
                }
            }

            return error.InvalidType;
        }

        fn nextValueSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) De.Error!@TypeOf(seed).Value {
            return try seed.deserialize(allocator, self.de.deserializer());
        }
    };
}

fn Union(comptime De: type) type {
    return struct {
        de: *De,

        const Self = @This();

        pub usingnamespace getty.de.UnionAccess(
            *Self,
            De.Error,
            variantSeed,
        );

        pub usingnamespace getty.de.VariantAccess(
            *Self,
            De.Error,
            payloadSeed,
        );

        fn variantSeed(self: *Self, _: ?std.mem.Allocator, seed: anytype) De.Error!@TypeOf(seed).Value {
            comptime concepts.Concept("StringVariant", "expected variant type to be a string")(.{
                concepts.traits.isString(@TypeOf(seed).Value),
            });

            const token = (try self.de.tokens.next()) orelse return error.MissingVariant;

            if (token == .String) {
                return token.String.slice(self.de.tokens.slice, self.de.tokens.i - 1);
            }

            return error.InvalidType;
        }

        fn payloadSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) De.Error!@TypeOf(seed).Value {
            if (@TypeOf(seed).Value != void) {
                // Deserialize payload.
                const payload = try seed.deserialize(allocator, self.de.deserializer());
                errdefer getty.de.free(allocator.?, payload);

                // Eat trailing '}'.
                if (try self.de.tokens.next()) |t| {
                    if (t != .ObjectEnd) {
                        return error.InvalidTopLevelTrailing;
                    }
                } else {
                    return error.UnbalancedBraces;
                }

                return payload;
            }
        }
    };
}
