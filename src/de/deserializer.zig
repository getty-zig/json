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
            if (try self.tokens.next()) |_| {
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

        fn deserializeBool(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .True or token == .False) {
                    return try visitor.visitBool(allocator, De, token == .True);
                }
            }

            return error.InvalidType;
        }

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

        fn deserializeIgnored(self: *Self, _: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            return try skip_value(&self.tokens);
        }

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

        fn deserializeMap(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var map = MapAccess(Self){ .d = self };
                    return try visitor.visitMap(allocator, De, map.mapAccess());
                }
            }

            return error.InvalidType;
        }

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

        fn deserializeSeq(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ArrayBegin) {
                    var sa = SeqAccess(Self){ .d = self };
                    return try visitor.visitSeq(allocator, De, sa.seqAccess());
                }
            }

            return error.InvalidType;
        }

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

        fn deserializeStruct(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var s = StructAccess(Self){ .d = self };
                    return try visitor.visitMap(allocator, De, s.mapAccess());
                }
            }

            return error.InvalidType;
        }

        fn deserializeUnion(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const backup = self.tokens;

            if (try self.tokens.next()) |token| {
                if (token == .String) {
                    self.tokens = backup;
                }

                if (token == .String or token == .ObjectBegin) {
                    var u = Union(Self){ .d = self };
                    return try visitor.visitUnion(allocator, De, u.unionAccess(), u.variantAccess());
                }
            }

            return error.InvalidType;
        }

        fn deserializeVoid(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Null) {
                    return try visitor.visitVoid(allocator, De);
                }
            }

            return error.InvalidType;
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

fn MapKeyDeserializer(comptime De: type) type {
    return struct {
        key: []const u8,

        const Self = @This();

        pub usingnamespace getty.Deserializer(
            *Self,
            Error,
            De.user_dt,
            De.deserializer_dt,
            .{
                .deserializeInt = deserializeInt,
                .deserializeString = deserializeString,
            },
        );

        const Error = De.Error;

        fn deserializeString(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            return try visitor.visitString(allocator, De, self.key);
        }

        fn deserializeInt(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const int = try std.fmt.parseInt(@TypeOf(visitor).Value, self.key, 10);
            return try visitor.visitInt(allocator, De, int);
        }
    };
}

fn MapAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            Error,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
            },
        );

        const De = D.@"getty.Deserializer";

        const Error = De.Error;

        fn nextKeySeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!?@TypeOf(seed).Value {
            if (try self.d.tokens.next()) |token| {
                if (token == .ObjectEnd) {
                    return null;
                }

                if (token == .String) {
                    const slice = token.String.slice(self.d.tokens.slice, self.d.tokens.i - 1);
                    const string = switch (token.String.escapes) {
                        .None => slice,
                        .Some => try unescapeString(allocator.?, token.String, slice),
                    };
                    defer if (token.String.escapes == .Some) {
                        allocator.?.free(string);
                    };

                    var mkd = MapKeyDeserializer(De){ .key = string };
                    var result = try seed.deserialize(allocator, mkd.deserializer());

                    return result;
                }
            }

            return error.InvalidType;
        }

        fn nextValueSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            return try seed.deserialize(allocator, self.d.deserializer());
        }
    };
}

fn SeqAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.SeqAccess(
            *Self,
            Error,
            .{ .nextElementSeed = nextElementSeed },
        );

        const De = D.@"getty.Deserializer";

        const Error = De.Error;

        fn nextElementSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!?@TypeOf(seed).Value {
            const element = seed.deserialize(allocator, self.d.deserializer()) catch |err| {
                // Slice for the current token instead of looking at the
                // `token` field since the token isn't set for some reason.
                if (self.d.tokens.i - 1 >= self.d.tokens.slice.len) {
                    return err;
                }

                return switch (self.d.tokens.slice[self.d.tokens.i - 1]) {
                    ']' => null,
                    else => err,
                };
            };

            return element;
        }
    };
}

fn StructAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            Error,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
            },
        );

        const De = D.@"getty.Deserializer";

        const Error = De.Error;

        fn nextKeySeed(self: *Self, _: ?std.mem.Allocator, seed: anytype) Error!?@TypeOf(seed).Value {
            comptime concepts.Concept("StringKey", "expected key type to be `[]const u8`")(.{
                concepts.traits.isSame(@TypeOf(seed).Value, []const u8),
            });

            if (try self.d.tokens.next()) |token| {
                if (token == .ObjectEnd) {
                    return null;
                }

                if (token == .String) {
                    return token.String.slice(self.d.tokens.slice, self.d.tokens.i - 1);
                }
            }

            return error.InvalidType;
        }

        fn nextValueSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            return try seed.deserialize(allocator, self.d.deserializer());
        }
    };
}

fn Union(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.UnionAccess(
            *Self,
            Error,
            .{ .variantSeed = variantSeed },
        );

        pub usingnamespace getty.de.VariantAccess(
            *Self,
            Error,
            .{ .payloadSeed = payloadSeed },
        );

        const De = D.@"getty.Deserializer";

        const Error = De.Error;

        fn variantSeed(self: *Self, _: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            comptime concepts.Concept("StringVariant", "expected variant type to be a string")(.{
                concepts.traits.isString(@TypeOf(seed).Value),
            });

            const token = (try self.d.tokens.next()) orelse return error.MissingVariant;

            if (token == .String) {
                return token.String.slice(self.d.tokens.slice, self.d.tokens.i - 1);
            }

            return error.InvalidType;
        }

        fn payloadSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            if (@TypeOf(seed).Value != void) {
                // Deserialize payload.
                const payload = try seed.deserialize(allocator, self.d.deserializer());
                errdefer getty.de.free(allocator.?, payload);

                // Eat trailing '}'.
                if (try self.d.tokens.next()) |t| {
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
