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
            de_with,
            deserializeBool,
            deserializeEnum,
            deserializeFloat,
            deserializeInt,
            deserializeMap,
            deserializeOptional,
            deserializeSeq,
            deserializeString,
            deserializeStruct,
            deserializeVoid,
        );

        const Error = getty.de.Error ||
            std.json.TokenStream.Error ||
            std.fmt.ParseIntError ||
            std.fmt.ParseFloatError;

        const de_with = .{struct_with};

        const struct_with = struct {
            pub fn is(comptime T: type) bool {
                return @typeInfo(T) == .Struct and !@typeInfo(T).Struct.is_tuple and !std.mem.startsWith(u8, @typeName(T), "std.");
            }

            pub fn visitor(allocator: ?std.mem.Allocator, comptime T: type) Visitor(T) {
                return .{ .allocator = allocator };
            }

            pub fn deserialize(comptime _: type, deserializer: anytype, v: anytype) !@TypeOf(v).Value {
                return try deserializer.deserializeStruct(v);
            }

            fn Visitor(comptime Struct: type) type {
                return struct {
                    allocator: ?std.mem.Allocator = null,

                    pub usingnamespace getty.de.Visitor(
                        @This(),
                        Value,
                        undefined,
                        undefined,
                        undefined,
                        undefined,
                        visitMap,
                        undefined,
                        undefined,
                        undefined,
                        undefined,
                        undefined,
                    );

                    const Value = Struct;

                    fn visitMap(self: @This(), comptime De: type, mapAccess: anytype) De.Error!Value {
                        const fields = std.meta.fields(Value);

                        var map: Value = undefined;
                        var seen = [_]bool{false} ** fields.len;

                        errdefer {
                            if (self.allocator) |allocator| {
                                inline for (fields) |field, i| {
                                    if (!field.is_comptime and seen[i]) {
                                        getty.de.free(allocator, @field(map, field.name));
                                    }
                                }
                            }
                        }

                        while (try mapAccess.nextKey([]const u8)) |key| {
                            var found = false;

                            inline for (fields) |field, i| {
                                if (std.mem.eql(u8, field.name, key)) {
                                    if (seen[i]) {
                                        return error.DuplicateField;
                                    }

                                    switch (field.is_comptime) {
                                        true => @compileError("TODO: deserialize comptime struct fields"),
                                        false => @field(map, field.name) = try mapAccess.nextValue(field.field_type),
                                    }

                                    seen[i] = true;
                                    found = true;
                                    break;
                                }
                            }

                            if (!found) {
                                return error.UnknownField;
                            }
                        }

                        inline for (fields) |field, i| {
                            if (!seen[i]) {
                                if (field.default_value) |default| {
                                    if (!field.is_comptime) {
                                        @field(map, field.name) = default;
                                    }
                                } else {
                                    return error.MissingField;
                                }
                            }
                        }

                        return map;
                    }
                };
            }
        };

        /// Hint that the type being deserialized into is expecting a `bool` value.
        fn deserializeBool(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .True => return try visitor.visitBool(Self.@"getty.Deserializer", true),
                    .False => return try visitor.visitBool(Self.@"getty.Deserializer", false),
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an `enum`
        /// value.
        fn deserializeEnum(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        if (num.is_integer) {
                            return try switch (slice[0]) {
                                '-' => visitor.visitInt(Self.@"getty.Deserializer", try parseSigned(slice)),
                                else => visitor.visitInt(Self.@"getty.Deserializer", try parseUnsigned(slice)),
                            };
                        }
                    },
                    .String => |str| {
                        const slice = str.slice(self.tokens.slice, self.tokens.i - 1);
                        return try visitor.visitString(Self.@"getty.Deserializer", try self.allocator.?.dupe(u8, slice));
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a
        /// floating-point value.
        fn deserializeFloat(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);
                        return try visitor.visitFloat(Self.@"getty.Deserializer", try std.fmt.parseFloat(f128, slice));
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an
        /// integer value.
        fn deserializeInt(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .Number => |num| {
                        const slice = num.slice(self.tokens.slice, self.tokens.i - 1);

                        switch (num.is_integer) {
                            true => return try switch (slice[0]) {
                                '-' => visitor.visitInt(Self.@"getty.Deserializer", try parseSigned(slice)),
                                else => visitor.visitInt(Self.@"getty.Deserializer", try parseUnsigned(slice)),
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
        fn deserializeMap(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var access = MapAccess(Self){ .allocator = self.allocator, .deserializer = self };
                    return try visitor.visitMap(getty.@"getty.Deserializer", access.mapAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting an optional
        /// value.
        fn deserializeOptional(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            const tokens = self.tokens;

            if (try self.tokens.next()) |token| {
                return try switch (token) {
                    .Null => visitor.visitNull(Self.@"getty.Deserializer"),
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
        fn deserializeSeq(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ArrayBegin) {
                    var access = SeqAccess(Self){ .allocator = self.allocator, .deserializer = self };
                    return try visitor.visitSeq(Self.@"getty.Deserializer", access.sequenceAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a string value.
        fn deserializeString(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                switch (token) {
                    .String => |str| {
                        const slice = str.slice(self.tokens.slice, self.tokens.i - 1);
                        return visitor.visitString(Self.@"getty.Deserializer", try self.allocator.?.dupe(u8, slice));
                    },
                    else => {},
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a struct value.
        fn deserializeStruct(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .ObjectBegin) {
                    var access = StructAccess(Self){ .allocator = self.allocator, .deserializer = self };
                    return try visitor.visitMap(Self.@"getty.Deserializer", access.mapAccess());
                }
            }

            return error.InvalidType;
        }

        /// Hint that the type being deserialized into is expecting a `void` value.
        fn deserializeVoid(self: *Self, visitor: anytype) Error!@TypeOf(visitor).Value {
            if (try self.tokens.next()) |token| {
                if (token == .Null) {
                    return try visitor.visitVoid(Self.@"getty.Deserializer");
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

fn StructAccess(comptime D: type) type {
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

        const Error = D.Error;

        fn nextKeySeed(self: *Self, seed: anytype) Error!?@TypeOf(seed).Value {
            comptime concepts.Concept("StringKey", "expected key type to be `[]const u8`")(.{
                concepts.traits.isSame(@TypeOf(seed).Value, []const u8),
            });

            if (try self.deserializer.tokens.next()) |token| {
                switch (token) {
                    .ObjectEnd => return null,
                    .String => |str| return str.slice(self.deserializer.tokens.slice, self.deserializer.tokens.i - 1),
                    else => {},
                }
            }

            return error.InvalidType;
        }

        fn nextValueSeed(self: *Self, seed: anytype) Error!@TypeOf(seed).Value {
            return try seed.deserialize(self.allocator, self.deserializer.deserializer());
        }
    };
}
