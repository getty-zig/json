const getty = @import("getty");
const std = @import("std");

const Allocator = std.mem.Allocator;

/// A JSON Deserializer.
pub fn Deserializer(comptime dbt: anytype, comptime Reader: type) type {
    const Parser = std.json.Reader(std.json.default_buffer_size, Reader);

    return struct {
        parser: Parser,
        scratch: std.heap.ArenaAllocator,

        const Self = @This();

        pub fn init(ally: Allocator, r: Reader) Self {
            return Self{
                .parser = std.json.reader(ally, r),
                .scratch = std.heap.ArenaAllocator.init(ally),
            };
        }

        pub fn deinit(self: *Self) void {
            self.parser.deinit();
            self.scratch.deinit();
            self.* = undefined;
        }

        /// Validates that the input data has been fully deserialized.
        ///
        /// This method should always be called after a value has been fully
        /// deserialized.
        pub fn end(self: *Self) Err!void {
            if (try self.parser.next() != .end_of_document) {
                return error.SyntaxError;
            }
        }

        pub usingnamespace getty.Deserializer(
            *Self,
            Err,
            dbt,
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

        const De = Self.@"getty.Deserializer";
        const Err = getty.de.Error ||
            // This includes all of std.json.Reader's errors, including
            // std.json.Error.
            Parser.AllocError ||
            std.fmt.ParseIntError || std.fmt.ParseFloatError;

        fn deserializeBool(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            return switch (try self.parser.next()) {
                .true => try visitor.visitBool(arena, De, true),
                .false => try visitor.visitBool(arena, De, false),
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            };
        }

        fn deserializeEnum(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            return switch (try self.parser.nextAlloc(self.scratch.allocator(), .alloc_if_needed)) {
                .string, .allocated_string => |slice| (try visitor.visitString(arena, De, slice, .managed)).value,
                .number, .allocated_number => |slice| try visitInt(visitor, arena, De, slice),
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.InvalidType,
            };
        }

        fn deserializeFloat(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            // By default, JSON numbers are deserialized into f128 Getty
            // Floats. However, std.fmt.parseFloat uses an optimized parsing
            // algorithm for f16, f32, and f64 values, so we try to use those
            // wherever we can.
            const Float = switch (@TypeOf(visitor).Value) {
                f16, f32, f64 => |T| T,
                else => f128,
            };

            return switch (try self.parser.nextAlloc(self.scratch.allocator(), .alloc_if_needed)) {
                .number, .allocated_number => |slice| try visitor.visitFloat(arena, De, try std.fmt.parseFloat(Float, slice)),
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.InvalidType,
            };
        }

        fn deserializeIgnored(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            try self.parser.skipValue();
            return try visitor.visitVoid(arena, De);
        }

        fn deserializeInt(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            return switch (try self.parser.nextAlloc(self.scratch.allocator(), .alloc_if_needed)) {
                .number, .allocated_number => |slice| try visitInt(visitor, arena, De, slice),
                .string, .allocated_string => |slice| (try visitor.visitString(arena, De, slice, .managed)).value,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            };
        }

        fn deserializeMap(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            switch (try self.parser.next()) {
                .object_begin => {
                    var m = MapAccess(Self){ .d = self };
                    return try visitor.visitMap(arena, De, m.mapAccess());
                },
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }
        }

        fn deserializeOptional(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            switch (try self.parser.peekNextTokenType()) {
                .null => {
                    try self.skipToken(); // Eat 'null'.
                    return try visitor.visitNull(arena, De);
                },
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return try visitor.visitSome(arena, self.deserializer()),
            }
        }

        fn deserializeSeq(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            switch (try self.parser.next()) {
                .array_begin => {
                    var s = SeqAccess(Self){ .d = self };
                    const ret = try visitor.visitSeq(arena, De, s.seqAccess());
                    try self.endSeq(); // Eat ']'.
                    return ret;
                },
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }
        }

        fn deserializeString(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            return switch (try self.parser.nextAlloc(arena, .alloc_always)) {
                .allocated_string => |slice| (try visitor.visitString(arena, De, slice, .heap)).value,
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.InvalidType,
            };
        }

        fn deserializeStruct(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            switch (try self.parser.next()) {
                .object_begin => {
                    var s = StructAccess(Self){ .d = self };
                    return try visitor.visitMap(arena, De, s.mapAccess());
                },
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }
        }

        fn deserializeUnion(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            const peek = switch (try self.parser.peekNextTokenType()) {
                .object_begin => |tok| peek: {
                    try self.skipToken(); // Eat '{'.
                    break :peek tok;
                },
                .string => |tok| tok,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            };

            var u = UnionAccess(Self){ .d = self };
            const ret = try visitor.visitUnion(arena, De, u.unionAccess(), u.variantAccess());

            if (peek == .object_begin) {
                try self.endUnion();
            }

            return ret;
        }

        fn deserializeVoid(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            return switch (try self.parser.next()) {
                .null => try visitor.visitVoid(arena, De),
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.InvalidType,
            };
        }

        fn deserializeAny(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            const Visitor = @TypeOf(visitor);
            const visitor_info = @typeInfo(Visitor);

            const token = try self.parser.nextAlloc(arena, .alloc_if_needed);

            switch (token) {
                .true, .false => return try visitor.visitBool(arena, De, token == .true),
                .number, .allocated_number => |slice| {
                    if (visitor_info == .Int) {
                        return try visitIntHint(visitor, arena, De, slice);
                    }

                    if (!std.json.isNumberFormattedLikeAnInteger(slice)) {
                        const Float = switch (Visitor.Value) {
                            f16, f32, f64 => |T| T,
                            else => f128,
                        };

                        return try visitor.visitFloat(arena, De, try std.fmt.parseFloat(Float, slice));
                    }

                    return try visitIntBase(visitor, arena, De, slice);
                },
                inline .string, .allocated_string => |slice| {
                    // Union
                    if (visitor_info == .Union) {
                        var u = UnionAccess(Self){ .d = self };
                        return try visitor.visitUnion(arena, De, u.unionAccess(), u.variantAccess());
                    }

                    // Enum, String
                    switch (token) {
                        .string => {
                            const ret = try visitor.visitString(arena, De, slice, .stack);
                            std.debug.assert(!ret.used);
                            return ret.value;
                        },
                        .allocated_string => {
                            const ret = try visitor.visitString(arena, De, slice, .heap);
                            if (!ret.used) arena.free(slice);
                            return ret.value;
                        },
                        // UNREACHABLE: The outer switch guarantees that only
                        // .string and .allocated_string tokens will reach this
                        // inner switch.
                        else => unreachable,
                    }
                },
                .null => {
                    // Void
                    if (Visitor.Value == void) {
                        return try visitor.visitVoid(arena, De);
                    }

                    // Optional
                    return try visitor.visitNull(arena, De);
                },
                .array_begin => {
                    var s = SeqAccess(Self){ .d = self };
                    const result = try visitor.visitSeq(arena, De, s.seqAccess());

                    try self.endSeq();

                    return result;
                },
                .object_begin => {
                    // Union
                    if (visitor_info == .Union) {
                        var u = UnionAccess(Self){ .d = self };
                        const result = try visitor.visitUnion(arena, De, u.unionAccess(), u.variantAccess());

                        try self.endUnion();

                        return result;
                    }

                    // Map
                    var m = MapAccess(Self){ .d = self };
                    return try visitor.visitMap(arena, De, m.mapAccess());
                },
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }
        }

        fn skipToken(self: *Self) !void {
            while (true) {
                const token = try self.parser.next();

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

        fn endSeq(self: *Self) Err!void {
            switch (try self.parser.peekNextTokenType()) {
                .array_end => try self.skipToken(), // Eat ']'.
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.SyntaxError,
            }
        }

        fn endUnion(self: *Self) Err!void {
            switch (try self.parser.peekNextTokenType()) {
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
        allocated: bool,

        const Self = @This();

        pub usingnamespace getty.Deserializer(
            *Self,
            Err,
            De.user_dt,
            De.deserializer_dt,
            .{
                .deserializeAny = deserializeAny,
                .deserializeIgnored = deserializeIgnored,
                .deserializeInt = deserializeInt,
                .deserializeString = deserializeString,
            },
        );

        const Err = De.Err;

        fn deserializeAny(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            const Value = @TypeOf(visitor).Value;

            if (@typeInfo(Value) == .Int) {
                return try self.deserializeInt(arena, visitor);
            }

            if (comptime isString(Value)) {
                return try self.deserializeString(arena, visitor);
            }

            return error.InvalidType;
        }

        fn deserializeIgnored(_: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            return try visitor.visitVoid(arena, De);
        }

        fn deserializeInt(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            if (self.key.len == 0) {
                return error.InvalidValue;
            }

            return try visitInt(visitor, arena, De, self.key);
        }

        fn deserializeString(self: *Self, arena: Allocator, visitor: anytype) Err!@TypeOf(visitor).Value {
            if (self.allocated) {
                const ret = try visitor.visitString(arena, De, self.key, .heap);
                if (!ret.used) arena.free(self.key);
                return ret.value;
            }

            const ret = try visitor.visitString(arena, De, self.key, .stack);
            std.debug.assert(!ret.used);
            return ret.value;
        }
    };
}

fn MapAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            Err,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
            },
        );

        const De = D.@"getty.Deserializer";
        const Err = De.Err;

        fn nextKeySeed(self: *Self, arena: Allocator, seed: anytype) Err!?@TypeOf(seed).Value {
            const token = try self.d.parser.nextAlloc(arena, .alloc_if_needed);
            return switch (token) {
                .string, .allocated_string => |slice| {
                    const allocated = token == .allocated_string;
                    var mkd = MapKeyDeserializer(De){ .key = slice, .allocated = allocated };
                    return try seed.deserialize(arena, mkd.deserializer());
                },
                .object_end => null,
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.InvalidType,
            };
        }

        fn nextValueSeed(self: *Self, arena: Allocator, seed: anytype) Err!@TypeOf(seed).Value {
            return try seed.deserialize(arena, self.d.deserializer());
        }
    };
}

fn SeqAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.SeqAccess(
            *Self,
            Err,
            .{ .nextElementSeed = nextElementSeed },
        );

        const De = D.@"getty.Deserializer";
        const Err = De.Err;

        fn nextElementSeed(self: *Self, arena: Allocator, seed: anytype) Err!?@TypeOf(seed).Value {
            switch (try self.d.parser.peekNextTokenType()) {
                .array_end => return null,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => {},
            }

            return try seed.deserialize(arena, self.d.deserializer());
        }
    };
}

fn StructAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.MapAccess(
            *Self,
            Err,
            .{
                .nextKeySeed = nextKeySeed,
                .nextValueSeed = nextValueSeed,
            },
        );

        const De = D.@"getty.Deserializer";
        const Err = De.Err;

        fn nextKeySeed(self: *Self, _: Allocator, seed: anytype) Err!?@TypeOf(seed).Value {
            if (@TypeOf(seed).Value != []const u8) {
                @compileError("expected key type to be `[]const u8`");
            }

            const token = try self.d.parser.nextAlloc(self.d.scratch.allocator(), .alloc_if_needed);

            switch (token) {
                inline .string, .allocated_string => |slice| return slice,
                .object_end => return null,
                .end_of_document => return error.UnexpectedEndOfInput,
                else => return error.InvalidType,
            }
        }

        fn nextValueSeed(self: *Self, arena: Allocator, seed: anytype) Err!@TypeOf(seed).Value {
            return try seed.deserialize(arena, self.d.deserializer());
        }
    };
}

fn UnionAccess(comptime D: type) type {
    return struct {
        d: *D,

        const Self = @This();

        pub usingnamespace getty.de.UnionAccess(
            *Self,
            Err,
            .{
                .variantSeed = variantSeed,
            },
        );

        pub usingnamespace getty.de.VariantAccess(
            *Self,
            Err,
            .{
                .payloadSeed = payloadSeed,
            },
        );

        const De = D.@"getty.Deserializer";
        const Err = De.Err;

        fn variantSeed(self: *Self, arena: Allocator, seed: anytype) Err!@TypeOf(seed).Value {
            return switch (try self.d.parser.peekNextTokenType()) {
                .string => try seed.deserialize(arena, self.d.deserializer()),
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.InvalidType,
            };
        }

        fn payloadSeed(self: *Self, arena: Allocator, seed: anytype) Err!@TypeOf(seed).Value {
            const payload = try seed.deserialize(arena, self.d.deserializer());

            return switch (try self.d.parser.peekNextTokenType()) {
                .object_end => payload,
                .end_of_document => error.UnexpectedEndOfInput,
                else => error.SyntaxError,
            };
        }
    };
}

inline fn parseInt(comptime T: type, slice: []const u8) !T {
    return std.fmt.parseInt(T, slice, 10) catch |err| switch (err) {
        error.InvalidCharacter => return error.InvalidType,
        error.Overflow => return err,
    };
}

inline fn visitInt(
    visitor: anytype,
    arena: Allocator,
    comptime De: type,
    slice: []const u8,
) !@TypeOf(visitor).Value {
    if (@typeInfo(@TypeOf(visitor).Value) == .Int) {
        return try visitIntHint(visitor, arena, De, slice);
    }

    return try visitIntBase(visitor, arena, De, slice);
}

inline fn visitIntBase(
    visitor: anytype,
    arena: Allocator,
    comptime De: type,
    slice: []const u8,
) !@TypeOf(visitor).Value {
    return try switch (slice[0]) {
        '0'...'9' => visitor.visitInt(arena, De, try parseInt(u128, slice)),
        else => visitor.visitInt(arena, De, try parseInt(i128, slice)),
    };
}

inline fn visitIntHint(
    visitor: anytype,
    arena: Allocator,
    comptime De: type,
    slice: []const u8,
) !@TypeOf(visitor).Value {
    const Value = @TypeOf(visitor).Value;
    const value_info = @typeInfo(Value);

    if (value_info.Int.signedness == .unsigned and slice[0] == '-') {
        return error.Overflow;
    }

    return try visitor.visitInt(arena, De, try parseInt(Value, slice));
}

fn isString(comptime T: type) bool {
    comptime {
        // Only pointer types can be strings, no optionals
        const info = @typeInfo(T);
        if (info != .Pointer) return false;
        const ptr = &info.Pointer;

        // Check for CV qualifiers that would prevent coerction to []const u8
        if (ptr.is_volatile or ptr.is_allowzero) return false;

        // If it's already a slice, simple check.
        if (ptr.size == .Slice) {
            return ptr.child == u8;
        }

        // Otherwise check if it's an array type that coerces to slice.
        if (ptr.size == .One) {
            const child = @typeInfo(ptr.child);
            if (child == .Array) {
                const arr = &child.Array;
                return arr.child == u8;
            }
        }

        return false;
    }
}
