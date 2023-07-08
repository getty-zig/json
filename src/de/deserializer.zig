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
            // This includes all of std.json.Reader's errors, including
            // std.json.Error.
            JsonReader.AllocError ||
            std.fmt.ParseIntError || std.fmt.ParseFloatError;

        const De = Self.@"getty.Deserializer";

        fn deserializeAny(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.peekNextTokenType() == .end_of_document) {
                return error.UnexpectedEndOfInput;
            }

            const Visitor = @TypeOf(visitor);
            const visitor_info = @typeInfo(Visitor);

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            switch (token) {
                .true, .false => {
                    return try visitor.visitBool(allocator, De, token == .true);
                },
                inline .number, .allocated_number => |slice| {
                    // Integer (with hint)
                    if (visitor_info == .Int) {
                        const sign = visitor_info.Int.signedness;

                        if (sign == .unsigned and slice[0] == '-') {
                            return error.InvalidType;
                        }

                        return try visitor.visitInt(allocator, De, try parseInt(Visitor, slice, 10));
                    }

                    // Enum
                    if (visitor_info == .Enum) {
                        switch (slice[0]) {
                            '0'...'9' => return try visitor.visitInt(allocator, De, try parseInt(u128, slice, 10)),
                            else => return try visitor.visitInt(allocator, De, try parseInt(i128, slice, 10)),
                        }
                    }

                    // Float
                    if (!std.json.isNumberFormattedLikeAnInteger(slice)) {
                        const Float = switch (Visitor.Value) {
                            f16, f32, f64 => |T| T,
                            else => f128,
                        };

                        return try visitor.visitFloat(allocator, De, try std.fmt.parseFloat(Float, slice));
                    }

                    // Integer (without hint)
                    switch (slice[0]) {
                        '0'...'9' => return try visitor.visitInt(allocator, De, try parseInt(u128, slice, 10)),
                        else => return try visitor.visitInt(allocator, De, try parseInt(i128, slice, 10)),
                    }
                },
                inline .string, .allocated_string => |slice| {
                    // Union
                    if (visitor_info == .Union) {
                        var u = Union(Self){ .d = self };
                        return try visitor.visitUnion(allocator, De, u.unionAccess(), u.variantAccess());
                    }

                    // Enum, String
                    return try visitor.visitString(allocator, De, slice);
                },
                .null => {
                    // Void
                    if (Visitor.Value == void) {
                        return try visitor.visitVoid(allocator, De);
                    }

                    // Optional
                    return try visitor.visitNull(allocator, De);
                },
                .array_begin => {
                    var s = SeqAccess(Self){ .d = self };
                    const result = try visitor.visitSeq(allocator.?, De, s.seqAccess());
                    errdefer getty.de.free(allocator.?, De, result);

                    try self.endSeq();

                    return result;
                },
                .object_begin => {
                    // Union
                    if (visitor_info == .Union) {
                        var u = Union(Self){ .d = self };
                        const result = try visitor.visitUnion(allocator.?, De, u.unionAccess(), u.variantAccess());
                        errdefer getty.de.free(allocator.?, De, result);

                        try self.endMap();

                        return result;
                    }

                    // Map
                    var m = MapAccess(Self){ .d = self };
                    const result = try visitor.visitMap(allocator.?, De, m.mapAccess());
                    errdefer getty.de.free(allocator.?, De, result);

                    try self.endMap();

                    return result;
                },
                else => return error.InvalidType,
            }
        }

        fn deserializeBool(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .true, .false => {},
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            const value = switch (try self.tokens.next()) {
                .true => true,
                .false => false,

                // UNREACHABLE: The peek switch guarantees that only .true and
                // .false tokens reach here.
                else => unreachable,
            };

            return try visitor.visitBool(allocator, De, value);
        }

        fn deserializeEnum(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .string, .number => {},
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            return try switch (token) {
                inline .string, .allocated_string => |slice| visitor.visitString(allocator, De, slice),
                inline .number, .allocated_number => |slice| switch (slice[0]) {
                    '0'...'9' => visitor.visitInt(allocator, De, try parseInt(u128, slice, 10)),
                    else => visitor.visitInt(allocator, De, try parseInt(i128, slice, 10)),
                },

                // UNREACHABLE: The peek switch guarantees that only .number,
                // .string, .allocated_number, and .allocated_string tokens
                // reach here.
                else => unreachable,
            };
        }

        fn deserializeFloat(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .number => {},
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            // std.fmt.parseFloat uses an optimized parsing algorithm for f16,
            // f32, and f64. So, we try to use those if we can based on the
            // kind of value the visitor produces.
            const Float = switch (@TypeOf(visitor).Value) {
                f16, f32, f64 => |T| T,
                else => f128,
            };

            const token = try self.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            const value = switch (token) {
                inline .number, .allocated_number => |slice| try std.fmt.parseFloat(Float, slice),

                // UNREACHABLE: The peek switch guarantees that only .number
                // and .allocated_number tokens reach here.
                else => unreachable,
            };

            return try visitor.visitFloat(allocator, De, value);
        }

        fn deserializeIgnored(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            try self.tokens.skipValue();

            return try visitor.visitVoid(allocator, De);
        }

        fn deserializeInt(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .number => {},
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            const value = switch (token) {
                inline .number, .allocated_number => |slice| blk: {
                    const Value = @TypeOf(visitor).Value;
                    const value_info = @typeInfo(Value);

                    // If we know that the visitor will produce an integer, we
                    // can pass that information along to std.fmt.ParseInt.
                    if (value_info == .Int) {
                        const sign = value_info.Int.signedness;

                        // Return an early error if the visitor's value type is
                        // unsigned but the parsed number is negative.
                        if (sign == .unsigned and slice[0] == '-') {
                            return error.InvalidType;
                        }

                        break :blk try parseInt(Value, slice, 10);
                    }

                    // If the visitor is not producing an integer, default to
                    // deserializing a 128-bit integer.
                    break :blk try switch (slice[0]) {
                        '0'...'9' => parseInt(u128, slice, 10),
                        else => parseInt(i128, slice, 10),
                    };
                },

                // UNREACHABLE: The peek switch guarantees that only .number
                // and .allocated_number tokens reach here.
                else => unreachable,
            };

            return try visitor.visitInt(allocator, De, value);
        }

        fn deserializeMap(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .object_begin => try self.skipToken(), // Eat '{'.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            var m = MapAccess(Self){ .d = self };
            const result = try visitor.visitMap(allocator.?, De, m.mapAccess());
            errdefer getty.de.free(allocator.?, De, result);

            try self.endMap();

            return result;
        }

        fn deserializeOptional(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            return switch (try self.tokens.peekNextTokenType()) {
                .null => blk: {
                    try self.skipToken(); // Eat 'null'.
                    break :blk try visitor.visitNull(allocator, De);
                },
                .end_of_document => error.UnexpectedEndOfInput,
                else => try visitor.visitSome(allocator, self.deserializer()),
            };
        }

        fn deserializeSeq(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .array_begin => try self.skipToken(), // Eat '['.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            var s = SeqAccess(Self){ .d = self };
            const result = try visitor.visitSeq(allocator.?, De, s.seqAccess());
            errdefer getty.de.free(allocator.?, De, result);

            try self.endSeq();

            return result;
        }

        fn deserializeString(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .string => {},
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            return try switch (token) {
                inline .string, .allocated_string => |slice| visitor.visitString(allocator, De, slice),

                // UNREACHABLE: The peek switch guarantees that only .string
                // and .allocated_string tokens reach here.
                else => unreachable,
            };
        }

        fn deserializeStruct(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .object_begin => try self.skipToken(), // Eat '{'.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            var s = StructAccess(Self){ .d = self };
            const result = try visitor.visitMap(allocator.?, De, s.mapAccess());
            errdefer getty.de.free(allocator.?, De, result);

            try self.endMap();

            return result;
        }

        fn deserializeUnion(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            const peek = switch (try self.tokens.peekNextTokenType()) {
                .string => |v| v,
                .object_begin => |v| blk: {
                    try self.skipToken(); // Eat '{'.
                    break :blk v;
                },
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            };

            if (allocator == null) {
                return error.MissingAllocator;
            }

            var u = Union(Self){ .d = self };
            const result = try visitor.visitUnion(allocator.?, De, u.unionAccess(), u.variantAccess());
            errdefer getty.de.free(allocator.?, De, result);

            if (peek == .object_begin) {
                try self.endMap();
            }

            return result;
        }

        fn deserializeVoid(self: *Self, allocator: ?std.mem.Allocator, visitor: anytype) Error!@TypeOf(visitor).Value {
            switch (try self.tokens.peekNextTokenType()) {
                .null => try self.skipToken(), // Eat 'null'.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            return try visitor.visitVoid(allocator, De);
        }

        fn skipToken(self: *Self) !void {
            while (true) {
                const token = try self.tokens.next();

                switch (token) {
                    .partial_number,
                    .partial_string,
                    .partial_string_escaped_1,
                    .partial_string_escaped_2,
                    .partial_string_escaped_3,
                    .partial_string_escaped_4,
                    => {},
                    else => break,
                }
            }
        }

        fn endSeq(self: *Self) Error!void {
            switch (try self.tokens.peekNextTokenType()) {
                .array_end => try self.skipToken(), // Eat ']'.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.SyntaxError,
            }
        }

        fn endMap(self: *Self) Error!void {
            switch (try self.tokens.peekNextTokenType()) {
                .object_end => try self.skipToken(), // Eat '}'.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.SyntaxError,
            }
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
            switch (try self.d.tokens.peekNextTokenType()) {
                .object_end => return null,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => {},
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.d.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            const value = switch (token) {
                inline .string, .allocated_string => |slice| slice,
                else => return error.InvalidType,
            };

            var mkd = MapKeyDeserializer(De){ .key = value };
            return try seed.deserialize(allocator, mkd.deserializer());
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
            switch (try self.d.tokens.peekNextTokenType()) {
                .array_end => return null,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => {},
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

            switch (try self.d.tokens.peekNextTokenType()) {
                .string => {},
                .object_end => return null,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.d.tokens.nextAlloc(allocator.?, .alloc_if_needed);

            switch (token) {
                inline .string, .allocated_string => |slice| {
                    self.is_key_allocated = token == .allocated_string;
                    return slice;
                },

                // UNREACHABLE: The peek switch guarantees that only .string
                // and .allocated_string tokens reach here.
                else => unreachable,
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
        is_variant_allocated: bool = false,

        const Self = @This();

        pub usingnamespace getty.de.UnionAccess(
            *Self,
            Error,
            .{
                .variantSeed = variantSeed,
                .isVariantAllocated = isVariantAllocated,
            },
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

            switch (try self.d.tokens.peekNextTokenType()) {
                .string => {},
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }

            if (allocator == null) {
                return error.MissingAllocator;
            }

            const token = try self.d.tokens.nextAlloc(allocator.?, .alloc_if_needed);
            defer freeToken(allocator.?, token);

            switch (token) {
                inline .string, .allocated_string => |slice| {
                    self.is_variant_allocated = token == .allocated_string;
                    return slice;
                },

                // UNREACHABLE: The peek switch guarantees that only .string
                // and .allocated_string tokens reach here.
                else => unreachable,
            }
        }

        fn payloadSeed(self: *Self, allocator: ?std.mem.Allocator, seed: anytype) Error!@TypeOf(seed).Value {
            const payload = try seed.deserialize(allocator, self.d.deserializer());
            errdefer if (allocator) |ally| getty.de.free(ally, De, payload);

            return switch (try self.d.tokens.peekNextTokenType()) {
                .object_end => payload,
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.SyntaxError,
            };
        }

        fn isVariantAllocated(self: *Self, comptime _: type) bool {
            return self.is_variant_allocated;
        }
    };
}

inline fn parseInt(comptime T: type, slice: []const u8, radix: u8) !T {
    return std.fmt.parseInt(T, slice, radix) catch |err| switch (err) {
        error.InvalidCharacter => error.InvalidType,
        error.Overflow => err,
    };
}

inline fn freeToken(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        inline .allocated_number, .allocated_string => |slice| allocator.free(slice),
        else => {},
    }
}
