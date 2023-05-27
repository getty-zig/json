const concepts = @import("concepts");
const getty = @import("getty");
const std = @import("std");

pub fn Deserializer(comptime user_dbt: anytype, comptime Reader: type) type {
    const JsonReader = std.json.Reader(1024 * 4, Reader);

    return struct {
        tokens: JsonReader,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, reader: Reader) Self {
            return Self{
                .tokens = JsonReader.init(allocator, reader),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.tokens.deinit();
            self.* = undefined;
        }

        /// Validates that the input data has been fully deserialized.
        ///
        /// This method should always be called after a value has been fully
        /// deserialized.
        pub fn end(self: *Self) Error!void {
            if (try self.tokens.next() != .end_of_document) {
                return error.SyntaxError;
            }
        }

        pub usingnamespace getty.Deserializer(
            *Self,
            Error,
            user_dbt,
            null,
            .{
                .deserializeAny = deserializeAny,
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
            std.json.Error ||
            JsonReader.AllocError ||
            std.fmt.ParseIntError ||
            std.fmt.ParseFloatError;

        const De = Self.@"getty.Deserializer";

        fn deserializeAny(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const Visitor = @TypeOf(visitor);
            const visitor_info = @typeInfo(Visitor);

            const token = try self.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.freeToken(token);

            switch (token) {
                .true, .false => {
                    return try visitor.visitBool(allocator, De, token == .true);
                },
                inline .number, .allocated_number => |slice| {
                    const is_integer = std.json.isNumberFormattedLikeAnInteger(slice);

                    // Enum
                    if (visitor_info == .Enum) {
                        if (is_integer) {
                            switch (slice[0]) {
                                '0'...'9' => return try visitor.visitInt(allocator, De, try parseInt(u128, slice, 10)),
                                else => return try visitor.visitInt(allocator, De, try parseInt(i128, slice, 10)),
                            }
                        }
                    }

                    // Float
                    if (!is_integer) {
                        const Float = switch (Visitor.Value) {
                            f16, f32, f64 => |T| T,
                            else => f128,
                        };

                        return try visitor.visitFloat(allocator, De, try std.fmt.parseFloat(Float, slice));
                    }

                    // Integer
                    if (visitor_info == .Int) {
                        const sign = visitor_info.Int.signedness;

                        if (sign == .unsigned and slice[0] == '-') {
                            return error.InvalidType;
                        }

                        return try visitor.visitInt(allocator, De, try parseInt(Visitor, slice, 10));
                    }

                    switch (slice[0]) {
                        '0'...'9' => return try visitor.visitInt(allocator, De, try parseInt(u128, slice, 10)),
                        else => return try visitor.visitInt(allocator, De, try parseInt(i128, slice, 10)),
                    }
                },
                .null => {
                    // Void
                    if (Visitor.Value == void) {
                        return try visitor.visitVoid(allocator, De);
                    }

                    // Optional
                    return try visitor.visitNull(allocator, De);
                },
                .object_begin => {
                    // Union
                    if (visitor_info == .Union) {
                        var u = Union(Self){ .d = self };
                        return try visitor.visitUnion(allocator, De, u.unionAccess(), u.variantAccess());
                    }

                    // Map
                    var map = MapAccess(Self){ .d = self };
                    return try visitor.visitMap(allocator, De, map.mapAccess());
                },
                .array_begin => {
                    var sa = SeqAccess(Self){ .d = self };
                    return try visitor.visitSeq(allocator, De, sa.seqAccess());
                },
                inline .string, .allocated_string => |t| {
                    // Union
                    if (visitor_info == .Union) {
                        var u = Union(Self){ .d = self };
                        return try visitor.visitUnion(allocator, De, u.unionAccess(), u.variantAccess());
                    }

                    const slice = t.slice(self.tokens.slice, self.tokens.i - 1);

                    // Enum, String
                    return try visitor.visitString(allocator, De, slice);
                },
                else => return error.InvalidType,
            }
        }

        fn deserializeBool(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const token = try self.tokens.next();
            if (token == .true or token == .false) {
                return try visitor.visitBool(allocator, De, token == .true);
            }

            return error.InvalidType;
        }

        fn deserializeEnum(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const token = try self.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.freeToken(token);

            switch (token) {
                inline .number, .allocated_number => |slice| {
                    switch (slice[0]) {
                        '0'...'9' => return try visitor.visitInt(
                            allocator,
                            De,
                            try parseInt(u128, slice, 10),
                        ),
                        else => return try visitor.visitInt(
                            allocator,
                            De,
                            try parseInt(i128, slice, 10),
                        ),
                    }
                },

                inline .string, .allocated_string => |slice| return visitor.visitString(
                    allocator,
                    De,
                    slice,
                ),

                else => return error.InvalidType,
            }
        }

        fn deserializeFloat(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const token = try self.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.freeToken(token);

            switch (token) {
                inline .number, .allocated_number => |slice| {

                    // std.fmt.parseFloat uses an optimized parsing algorithm
                    // for f16, f32, and f64.
                    const Float = switch (@TypeOf(visitor).Value) {
                        f16, f32, f64 => |T| T,
                        else => f128,
                    };

                    return try visitor.visitFloat(allocator, De, try std.fmt.parseFloat(Float, slice));
                },
                else => return error.InvalidType,
            }
        }

        fn deserializeIgnored(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            try self.skipToken();
            return try visitor.visitVoid(allocator, De);
        }

        fn deserializeInt(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const Value = @TypeOf(visitor).Value;
            const value_info = @typeInfo(Value);

            const token = try self.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.freeToken(token);

            switch (token) {
                inline .number, .allocated_number => |slice| {
                    // If we know that the visitor will produce an integer, we
                    // can pass that information along to std.fmt.ParseInt.
                    if (value_info == .Int) {
                        const sign = value_info.Int.signedness;

                        // Return an early error if the visitor's value type is
                        // unsigned but the parsed number is negative.
                        if (sign == .unsigned and slice[0] == '-') {
                            return error.InvalidType;
                        }

                        return try visitor.visitInt(allocator, De, try parseInt(Value, slice, 10));
                    }

                    // If the visitor is not producing an integer, default to
                    // deserializing a 128-bit integer.
                    switch (slice[0]) {
                        '0'...'9' => return try visitor.visitInt(
                            allocator,
                            De,
                            try parseInt(u128, slice, 10),
                        ),
                        else => return try visitor.visitInt(
                            allocator,
                            De,
                            try parseInt(i128, slice, 10),
                        ),
                    }
                },

                else => return error.InvalidType,
            }
        }

        fn deserializeMap(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next() == .object_begin) {
                var map = MapAccess(Self){ .d = self };
                return try visitor.visitMap(allocator, De, map.mapAccess());
            }

            return error.InvalidType;
        }

        fn deserializeOptional(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .null => {
                    try self.skipToken();
                    return try visitor.visitNull(allocator, De);
                },

                // TODO: If we're here, it's because there's no more tokens. So is
                // this the right error to return?
                .end_of_document => return error.InvalidType,

                else => return try visitor.visitSome(allocator, self.deserializer()),
            }
        }

        fn deserializeSeq(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const token = try self.tokens.next();
            if (token == .array_begin) {
                var sa = SeqAccess(Self){ .d = self };
                return try visitor.visitSeq(allocator, De, sa.seqAccess());
            }

            return error.InvalidType;
        }

        fn deserializeString(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const token = try self.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.freeToken(token);

            switch (token) {
                inline .string, .allocated_string => |slice| return try visitor.visitString(
                    allocator,
                    De,
                    slice,
                ),
                else => return error.InvalidType,
            }
        }

        fn deserializeStruct(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next() == .object_begin) {
                var s = StructAccess(Self){ .d = self };
                return try visitor.visitMap(allocator, De, s.mapAccess());
            }

            return error.InvalidType;
        }

        fn deserializeUnion(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .string => {},
                .object_begin => try self.skipToken(),
                else => return error.InvalidType,
            }

            var u = Union(Self){ .d = self };
            return try visitor.visitUnion(allocator, De, u.unionAccess(), u.variantAccess());
        }

        fn deserializeVoid(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next() != .null)
                return error.InvalidType;

            return try visitor.visitVoid(allocator, De);
        }

        /// Frees a Token if it is an allocated variant.
        fn freeToken(self: Self, tok: std.json.Token) void {
            switch (tok) {
                inline .allocated_number,
                .allocated_string,
                => |slice| self.allocator.free(slice),
                else => {},
            }
        }

        /// Eats up the next token.
        fn skipToken(self: *Self) !void {
            while (switch (try self.tokens.next()) {
                .partial_number,
                .partial_string,
                .partial_string_escaped_1,
                .partial_string_escaped_2,
                .partial_string_escaped_3,
                .partial_string_escaped_4,
                => true,

                else => false,
            }) {}
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
                .deserializeIgnored = deserializeIgnored,
                .deserializeInt = deserializeInt,
                .deserializeString = deserializeString,
            },
        );

        const Error = De.Error;

        fn deserializeIgnored(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            _ = self;
            return try visitor.visitVoid(allocator, De);
        }

        fn deserializeInt(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const int = try parseInt(@TypeOf(visitor).Value, self.key, 10);
            return try visitor.visitInt(allocator, De, int);
        }

        fn deserializeString(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            return try visitor.visitString(allocator, De, self.key);
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
            const token = try self.d.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.d.freeToken(token);
            switch (token) {
                .object_end => return null,
                inline .string, .allocated_string => |string| {
                    var mkd = MapKeyDeserializer(De){ .key = string };
                    return try seed.deserialize(allocator, mkd.deserializer());
                },
                else => return error.InvalidType,
            }
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
            if (try self.d.tokens.peekNextTokenType() == .array_end) {
                try self.d.skipToken();
                return null;
            }

            return try seed.deserialize(allocator, self.d.deserializer());
        }
    };
}

fn StructAccess(comptime D: type) type {
    return struct {
        d: *D,
        is_key_allocated: bool = false,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            Error,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
                .isKeyAllocated = isKeyAllocated,
            },
        );

        const De = D.@"getty.Deserializer";

        const Error = De.Error;

        fn nextKeySeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!?@TypeOf(seed).Value {
            comptime concepts.Concept("StringKey", "expected key type to be `[]const u8`")(.{
                concepts.traits.isSame(@TypeOf(seed).Value, []const u8),
            });

            // We use the allocator passed here rather than the allocator in the
            // deserializer since we may need to return allocated strings.
            const token = try self.d.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer switch (token) {
                // On the incredibly tiny chance that we got a number here which is
                // on a buffer boundary, still free that =D
                .allocated_number => |n| allocator.?.free(n),
                else => {},
            };

            switch (token) {
                .object_end => return null,
                inline .string, .allocated_string => |slice| {
                    self.is_key_allocated = token == .allocated_string;

                    return slice;
                },
                else => return error.InvalidType,
            }
        }

        fn nextValueSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            return try seed.deserialize(allocator, self.d.deserializer());
        }

        fn isKeyAllocated(self: *Self, comptime _: type) bool {
            return self.is_key_allocated;
        }
    };
}

fn Union(comptime D: type) type {
    return struct {
        d: *D,

        // TODO: allow returning allocated variants from variantSeed
        /// A place to temporarily store heap-allocated variants.
        variant_buf: [512]u8 = undefined,

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

        fn variantSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            comptime concepts.Concept("StringVariant", "expected variant type to be a string")(.{
                concepts.traits.isString(@TypeOf(seed).Value),
            });

            const token = try self.d.tokens.nextAlloc(allocator orelse return error.MissingAllocator, .alloc_if_needed);
            defer self.d.freeToken(token);

            switch (token) {
                .end_of_document => return error.MissingVariant,
                .string => |s| return s,
                .allocated_string => |s| {
                    if (s.len > self.variant_buf.len)
                        return error.OutOfMemory;
                    @memcpy(&self.variant_buf, s);
                    return self.variant_buf[0..s.len];
                },

                else => return error.InvalidType,
            }
        }

        fn payloadSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            if (comptime @TypeOf(seed).Value != void) {
                // Deserialize payload.
                const payload = try seed.deserialize(allocator, self.d.deserializer());
                errdefer getty.de.free(allocator.?, De, payload);

                switch (try self.d.tokens.next()) {
                    .object_end => {},
                    else => return error.SyntaxError,
                }

                return payload;
            }
        }
    };
}

/// Like std.fmt.parseInt, but does some error conversions to better fit getty's API
fn parseInt(comptime T: type, slice: []const u8, radix: u8) !T {
    return std.fmt.parseInt(T, slice, radix) catch |e| switch (e) {
        error.InvalidCharacter => error.InvalidType,
        error.Overflow => error.Overflow,
    };
}
