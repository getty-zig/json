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
            null,
            .{
                .deserializeBool = deserializeBool,
                .deserializeEnum = deserializeEnum,
                .deserializeFloat = deserializeFloat,
                .deserializeIgnored = deserializeIgnored,
                .deserializeInt = deserializeInt,
                .deserializeMap = deserializeMap,
                .deserializeOptional = deserializeOptional,
                .deserializeSeq = deserializeSeq,
                .deserializeString = deserializeString,
                .deserializeStruct = deserializeStruct,
                .deserializeUnion = deserializeUnion,
                .deserializeVoid = deserializeVoid,
            },
        );

        const Error = getty.de.Error ||
            std.json.TokenStream.Error ||
            error{UnexpectedJsonDepth} || // may be returned while skipping values
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
                    const slice = token.Number.slice(self.tokens.slice, self.tokens.i - 1);

                    switch (slice[0]) {
                        '0'...'9' => return try visitor.visitInt(allocator, De, try std.fmt.parseInt(u128, slice, 10)),
                        else => return try visitor.visitInt(allocator, De, try std.fmt.parseInt(i128, slice, 10)),
                    }
                }

                if (token == .String) {
                    const slice = token.String.slice(self.tokens.slice, self.tokens.i - 1);

                    switch (token.String.escapes) {
                        .None => return try visitor.visitString(allocator, De, slice),
                        .Some => {
                            const str = try unescapeString(allocator.?, token.String, slice);
                            defer allocator.?.free(str);
                            return try visitor.visitString(allocator, De, str);
                        },
                    }
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

                    // std.fmt.parseFloat uses an optimized parsing algorithm
                    // for f16, f32, and f64.
                    const Float = switch (@TypeOf(visitor).Value) {
                        f16, f32, f64 => |T| T,
                        else => f128,
                    };

                    return try visitor.visitFloat(allocator, De, try std.fmt.parseFloat(Float, slice));
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting to
        /// deserialize a value whose type does not matter because it is
        /// ignored.
        fn deserializeIgnored(self: *Self, _: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            return try skip_value(&self.tokens);
        }

        /// Hint that the type being deserialized into is expecting an
        /// integer value.
        fn deserializeInt(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const Visitor = @TypeOf(visitor);
            const visitor_info = @typeInfo(Visitor);

            if (try self.tokens.next()) |token| {
                if (token == .Number and token.Number.is_integer) {
                    const slice = token.Number.slice(self.tokens.slice, self.tokens.i - 1);

                    // We know what type the visitor will produce, so we can
                    // pass it along to std.fmt.ParseInt.
                    if (visitor_info == .Int) {
                        const sign = visitor_info.Int.signedness;

                        // Return an error if the parsed number is negative,
                        // but the visitor's value type is unsigned.
                        if (sign == .unsigned and slice[0] == '-') {
                            return error.InvalidType;
                        }

                        return try visitor.visitInt(allocator, De, try std.fmt.parseInt(Visitor, slice, 10));
                    }

                    // We don't know what type the visitor will produce, so we
                    // default to deserializing a 128-bit integer.
                    switch (slice[0]) {
                        '0'...'9' => return try visitor.visitInt(allocator, De, try std.fmt.parseInt(u128, slice, 10)),
                        else => return try visitor.visitInt(allocator, De, try std.fmt.parseInt(i128, slice, 10)),
                    }
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a map of
        /// key-value pairs.
        fn deserializeMap(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var map = MapAccess(Self){ .de = self };
                    return try visitor.visitMap(allocator, De, map.mapAccess());
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

                    return switch (token.String.escapes) {
                        .None => try visitor.visitString(allocator, De, slice),
                        .Some => blk: {
                            const s = try unescapeString(allocator.?, token.String, slice);
                            defer allocator.?.free(s);

                            break :blk try visitor.visitString(allocator, De, s);
                        },
                    };
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a struct value.
        fn deserializeStruct(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var s = StructAccess(Self){ .de = self };
                    return try visitor.visitMap(allocator, De, s.mapAccess());
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

        /// Unescapes an escaped JSON string token.
        ///
        /// The passed-in string must be an escaped string.
        fn unescapeString(
            allocator: std.mem.Allocator,
            str_token: std.meta.TagPayload(std.json.Token, std.json.Token.String),
            slice: []const u8,
        ) ![]u8 {
            std.debug.assert(str_token.escapes == .Some);

            const escaped = try allocator.alloc(u8, str_token.decodedLength());
            errdefer allocator.free(escaped);

            try std.json.unescapeValidString(escaped, slice);
            return escaped;
        }

        fn skip_value(tokens: *std.json.TokenStream) Error!void {
            const original_depth = stack_used(tokens);

            // Return an error if no value is found
            _ = try tokens.next();
            if (stack_used(tokens) < original_depth) return error.UnexpectedJsonDepth;
            if (stack_used(tokens) == original_depth) return;

            while (try tokens.next()) |_| {
                if (stack_used(tokens) == original_depth) return;
            }
        }

        fn stack_used(tokens: *std.json.TokenStream) usize {
            return tokens.parser.stack.len + if (tokens.token != null) @as(usize, 1) else 0;
        }
    };
}

fn MapAccess(comptime De: type) type {
    return struct {
        de: *De,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            De.Error,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
            },
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
            .{ .nextElementSeed = nextElementSeed },
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

fn StructAccess(comptime De: type) type {
    return struct {
        de: *De,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            De.Error,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
            },
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
            .{ .variantSeed = variantSeed },
        );

        pub usingnamespace getty.de.VariantAccess(
            *Self,
            De.Error,
            .{ .payloadSeed = payloadSeed },
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
