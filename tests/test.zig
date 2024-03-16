const getty = @import("getty");
const json = @import("json");
const require = @import("protest").require;
const std = @import("std");

const test_ally = std.testing.allocator;

test "encode - array" {
    try testEncodeEqual([0]bool, &.{
        .{ "[]", .{} },
    });
    try testEncodeEqual([1]bool, &.{
        .{ "[true]", .{true} },
    });
    try testEncodeEqual([2]bool, &.{
        .{ "[true,false]", .{ true, false } },
    });
    try testEncodeEqual([2][3]i32, &.{
        .{ "[[1,2,3],[4,5,6]]", .{ .{ 1, 2, 3 }, .{ 4, 5, 6 } } },
    });
    try testEncodeEqual([2][1][3]i32, &.{
        .{ "[[[1,2,3]],[[4,5,6]]]", .{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} } },
    });

    try testPrettyEncodeEqual([0]bool, &.{
        .{ "[]", .{} },
    });
    try testPrettyEncodeEqual([1]bool, &.{
        .{
            \\[
            \\  true
            \\]
            ,
            .{true},
        },
    });
    try testPrettyEncodeEqual([2][3]i32, &.{
        .{
            \\[
            \\  [
            \\    1,
            \\    2,
            \\    3
            \\  ],
            \\  [
            \\    4,
            \\    5,
            \\    6
            \\  ]
            \\]
            ,
            .{ .{ 1, 2, 3 }, .{ 4, 5, 6 } },
        },
    });
    try testPrettyEncodeEqual([2][1][3]i32, &.{
        .{
            \\[
            \\  [
            \\    [
            \\      1,
            \\      2,
            \\      3
            \\    ]
            \\  ],
            \\  [
            \\    [
            \\      4,
            \\      5,
            \\      6
            \\    ]
            \\  ]
            \\]
            ,
            .{ .{.{ 1, 2, 3 }}, .{.{ 4, 5, 6 }} },
        },
    });
}

test "encode - bool" {
    const T = bool;
    const tests: EncodeTest(T) = &.{
        .{ "true", true },
        .{ "false", false },
    };

    try testEncodeEqual(T, tests);
    try testPrettyEncodeEqual(T, tests);
}

test "encode - int" {
    // Signed.
    {
        const T = i64;
        const tests: EncodeTest(T) = &.{
            .{ "3", 3 },
            .{ "-2", -2 },
            .{ "-1234", -1234 },
            .{ "-9223372036854775808", std.math.minInt(T) },
        };

        try testEncodeEqual(T, tests);
        try testPrettyEncodeEqual(T, tests);
    }

    // Unsigned.
    {
        const T = u64;
        const tests: EncodeTest(T) = &.{
            .{ "3", 3 },
            .{ "18446744073709551615", std.math.maxInt(T) },
        };

        try testEncodeEqual(T, tests);
        try testPrettyEncodeEqual(T, tests);
    }
}

test "encode - enum" {
    const T = enum { foo, bar };
    const tests: EncodeTest(T) = &.{
        .{ "\"foo\"", T.foo },
        .{ "\"bar\"", T.bar },
        .{ "\"foo\"", .foo },
        .{ "\"bar\"", .bar },
    };

    try testEncodeEqual(T, tests);
    try testPrettyEncodeEqual(T, tests);
}

test "encode - error" {
    const T = error{ foo, bar };
    const tests: EncodeTest(T) = &.{
        .{ "\"foo\"", T.foo },
        .{ "\"bar\"", T.bar },
        .{ "\"foo\"", error.foo },
        .{ "\"bar\"", error.bar },
    };

    try testEncodeEqual(T, tests);
    try testPrettyEncodeEqual(T, tests);
}

test "encode - float" {
    const T = f64;
    const tests: EncodeTest(T) = &.{
        .{ "3e0", 3.0 },
        .{ "3.1e0", 3.1 },
        .{ "-1.5e0", -1.5 },
        .{ "2.2250738585072014e-308", std.math.floatMin(f64) },
        .{ "1.7976931348623157e308", std.math.floatMax(f64) },
        .{ "2.220446049250313e-16", std.math.floatEps(f64) },
        .{ "null", std.math.nan(f64) },
        .{ "null", std.math.inf(f64) },
    };

    try testEncodeEqual(T, tests);
    try testPrettyEncodeEqual(T, tests);
}

test "encode - list (std.ArrayList)" {
    {
        const T = std.ArrayList(u8);

        var want = T.init(test_ally);
        defer want.deinit();
        try want.appendSlice(&.{ 1, 2, 3, 4 });

        try testEncodeEqual(T, &.{
            .{ "[1,2,3,4]", want },
        });
    }

    {
        const T = std.ArrayList(std.ArrayList(u8));

        var want = T.init(test_ally);
        var one = std.ArrayList(u8).init(test_ally);
        var two = std.ArrayList(u8).init(test_ally);
        defer {
            one.deinit();
            two.deinit();
            want.deinit();
        }
        try one.appendSlice(&.{ 1, 2 });
        try two.appendSlice(&.{ 3, 4 });
        try want.appendSlice(&.{ one, two });

        try testEncodeEqual(T, &.{
            .{ "[[1,2],[3,4]]", want },
        });
    }
}

test "encode - object (std.AutoHashMap)" {
    {
        const T = std.AutoHashMap(i32, []const u8);

        var value = T.init(test_ally);
        defer value.deinit();
        try value.put(1, "foo");
        try value.put(2, "bar");

        try testEncodeEqual(T, &.{
            .{ "{\"1\":\"foo\",\"2\":\"bar\"}", value },
        });
        try testPrettyEncodeEqual(T, &.{
            .{
                \\{
                \\  "1": "foo",
                \\  "2": "bar"
                \\}
                ,
                value,
            },
        });
    }

    {
        const Child = std.AutoHashMap(i32, []const u8);
        const T = std.AutoHashMap(i32, Child);

        var value = T.init(test_ally);
        var a = Child.init(test_ally);
        var b = Child.init(test_ally);
        defer {
            a.deinit();
            b.deinit();
            value.deinit();
        }

        try a.put(3, "foo");
        try b.put(4, "bar");
        try value.put(1, a);
        try value.put(2, b);

        try testEncodeEqual(T, &.{
            .{
                "{\"1\":{\"3\":\"foo\"},\"2\":{\"4\":\"bar\"}}",
                value,
            },
        });
        try testPrettyEncodeEqual(T, &.{
            .{
                \\{
                \\  "1": {
                \\    "3": "foo"
                \\  },
                \\  "2": {
                \\    "4": "bar"
                \\  }
                \\}
                ,
                value,
            },
        });
    }
}

test "encode - object (std.StringArrayHashMap)" {
    {
        const T = std.StringArrayHashMap(i32);

        var value = T.init(test_ally);
        defer value.deinit();
        try value.put("foo", 1);
        try value.put("bar", 2);

        try testEncodeEqual(T, &.{
            .{ "{\"foo\":1,\"bar\":2}", value },
        });
        try testPrettyEncodeEqual(T, &.{
            .{
                \\{
                \\  "foo": 1,
                \\  "bar": 2
                \\}
                ,
                value,
            },
        });
    }

    {
        const Child = std.StringArrayHashMap(i32);
        const T = std.StringArrayHashMap(Child);

        var value = T.init(test_ally);
        var a = Child.init(test_ally);
        var b = Child.init(test_ally);
        defer {
            a.deinit();
            b.deinit();
            value.deinit();
        }

        try a.put("foo", 1);
        try b.put("bar", 2);
        try value.put("foo", a);
        try value.put("bar", b);

        try testEncodeEqual(T, &.{
            .{
                "{\"foo\":{\"foo\":1},\"bar\":{\"bar\":2}}",
                value,
            },
        });
        try testPrettyEncodeEqual(T, &.{
            .{
                \\{
                \\  "foo": {
                \\    "foo": 1
                \\  },
                \\  "bar": {
                \\    "bar": 2
                \\  }
                \\}
                ,
                value,
            },
        });
    }
}

test "encode - optional" {
    const T = ?bool;
    const tests: EncodeTest(T) = &.{
        .{ "null", null },
        .{ "true", true },
    };

    try testEncodeEqual(T, tests);
    try testPrettyEncodeEqual(T, tests);
}

test "encode - string" {
    const Strings = .{
        []const u8,
        [:0]const u8,
    };

    inline for (Strings) |T| {
        const tests: EncodeTest(T) = &.{
            // Basic
            .{ "\"\"", "" },
            .{ "\"foo\"", "foo" },

            // Control characters
            .{ "\"\\\"\"", "\"" },
            .{ "\"\\\\\"", "\\" },
            .{ "\"\\b\"", "\x08" },
            .{ "\"\\t\"", "\t" },
            .{ "\"\\n\"", "\n" },
            .{ "\"\\f\"", "\x0C" },
            .{ "\"\\r\"", "\r" },
            //.{ "\"\\u0000\"", "\u{0}" }, // TODO: This case fails when T is sentinel-terminated.
            .{ "\"\\u001f\"", "\u{1F}" },
            .{ "\"\\u007f\"", "\u{7F}" },
            .{ "\"\\u2028\"", "\u{2028}" },
            .{ "\"\\u2029\"", "\u{2029}" },

            // Basic Multilingual Plane
            .{ "\"\u{FF}\"", "\u{FF}" },
            .{ "\"\u{100}\"", "\u{100}" },
            .{ "\"\u{800}\"", "\u{800}" },
            .{ "\"\u{8000}\"", "\u{8000}" },
            .{ "\"\u{D799}\"", "\u{D799}" },

            // Non-Basic Multilingual Plane
            .{ "\"\\ud800\\udc00\"", "\u{10000}" },
            .{ "\"\\udbff\\udfff\"", "\u{10FFFF}" },
            .{ "\"\\ud83d\\ude01\"", "😁" },
            .{ "\"\\ud83d\\ude02\"", "😂" },

            .{ "\"hello\\ud83d\\ude01\"", "hello😁" },
            .{ "\"hello\\ud83d\\ude01world\\ud83d\\ude02\"", "hello😁world😂" },
        };

        try testEncodeEqual(T, tests);
        try testPrettyEncodeEqual(T, tests);
    }
}

test "encode - struct" {
    try testEncodeEqual(struct {}, &.{
        .{ "{}", .{} },
    });
    try testEncodeEqual(struct { x: void }, &.{
        .{ "{\"x\":null}", .{ .x = {} } },
    });

    const Inner = struct {
        a: void,
        b: usize,
        c: []const []const u8,
    };
    const Outer = struct {
        inner: []const Inner,
    };
    try testEncodeEqual(Outer, &.{
        .{
            "{\"inner\":[]}",
            .{ .inner = &.{} },
        },
        .{
            "{\"inner\":[{\"a\":null,\"b\":1,\"c\":[\"abc\",\"xyz\"]}]}",
            .{
                .inner = &.{
                    .{ .a = {}, .b = 1, .c = &.{ "abc", "xyz" } },
                },
            },
        },
        .{
            "{\"inner\":[{\"a\":null,\"b\":1,\"c\":[\"abc\",\"xyz\"]},{\"a\":null,\"b\":2,\"c\":[\"abc\",\"def\",\"xyz\"]}]}",
            .{
                .inner = &.{
                    .{ .a = {}, .b = 1, .c = &.{ "abc", "xyz" } },
                    .{ .a = {}, .b = 2, .c = &.{ "abc", "def", "xyz" } },
                },
            },
        },
    });
    try testPrettyEncodeEqual(Outer, &.{
        .{
            \\{
            \\  "inner": []
            \\}
            ,
            .{ .inner = &.{} },
        },
        .{
            \\{
            \\  "inner": [
            \\    {
            \\      "a": null,
            \\      "b": 1,
            \\      "c": [
            \\        "abc",
            \\        "xyz"
            \\      ]
            \\    }
            \\  ]
            \\}
            ,
            .{
                .inner = &.{
                    .{ .a = {}, .b = 1, .c = &.{ "abc", "xyz" } },
                },
            },
        },
        .{
            \\{
            \\  "inner": [
            \\    {
            \\      "a": null,
            \\      "b": 1,
            \\      "c": [
            \\        "abc",
            \\        "xyz"
            \\      ]
            \\    },
            \\    {
            \\      "a": null,
            \\      "b": 2,
            \\      "c": [
            \\        "abc",
            \\        "def",
            \\        "xyz"
            \\      ]
            \\    }
            \\  ]
            \\}
            ,
            .{
                .inner = &.{
                    .{ .a = {}, .b = 1, .c = &.{ "abc", "xyz" } },
                    .{ .a = {}, .b = 2, .c = &.{ "abc", "def", "xyz" } },
                },
            },
        },
    });
}

test "encode - tuple" {
    const T = std.meta.Tuple(&.{ i32, bool, []const u8 });

    try testEncodeEqual(T, &.{
        .{ "[1,true,\"ring\"]", .{ 1, true, "ring" } },
    });
    try testPrettyEncodeEqual(T, &.{
        .{
            \\[
            \\  1,
            \\  true,
            \\  "ring"
            \\]
            ,
            .{ 1, true, "ring" },
        },
    });
}

test "encode - union" {
    const T = union(enum) { Foo: i32, Bar: bool, Baz: void };

    try testEncodeEqual(T, &.{
        .{ "{\"Foo\":123}", .{ .Foo = 123 } },
        .{ "{\"Bar\":true}", .{ .Bar = true } },
        .{ "{\"Baz\":null}", .{ .Baz = {} } },
    });
}

test "encode - vector" {
    const T = @Vector(2, i32);

    try testEncodeEqual(T, &.{
        .{ "[0,0]", @as(T, @splat(@as(u32, 0))) },
        .{ "[1,1]", @as(T, @splat(@as(u32, 1))) },
    });
    try testPrettyEncodeEqual(T, &.{
        .{
            \\[
            \\  0,
            \\  0
            \\]
            ,
            @as(T, @splat(@as(u32, 0))),
        },
        .{
            \\[
            \\  1,
            \\  1
            \\]
            ,
            @as(T, @splat(@as(u32, 1))),
        },
    });
}

test "encode - void" {
    const T = void;
    const tests: EncodeTest(T) = &.{.{ "null", {} }};

    try testEncodeEqual(T, tests);
    try testPrettyEncodeEqual(T, tests);
}

test "parse - array" {
    try testParseEqual([0]bool, &.{
        .{ .{}, "[]" },
        .{ .{}, "[ ]" },
    });

    try testParseEqual([1]bool, &.{
        .{ .{true}, "[true]" },
        .{ .{false}, "[ false ]" },
    });

    try testParseEqual([2]bool, &.{
        .{ .{ true, false }, "[true,false]" },
        .{ .{ true, false }, "[ true , false ]" },
    });

    try testParseEqual([4]u64, &.{
        .{ .{ 1, 2, 3, 4 }, "[1,2,3,4]" },
        .{ .{ 1, 2, 3, 4 }, "[ 1 , 2 , 3 , 4 ]" },
    });

    try testParseEqual([2][2]u64, &.{
        .{ .{ .{ 1, 2 }, .{ 3, 4 } }, "[[1,2],[3,4]]" },
        .{ .{ .{ 1, 2 }, .{ 3, 4 } }, "[ [ 1 , 2 ] , [ 3 , 4 ] ]" },
    });

    try testParseEqual([2][1][2]u64, &.{
        .{ .{ .{.{ 1, 2 }}, .{.{ 3, 4 }} }, "[[[1,2]],[[3,4]]]" },
        .{ .{ .{.{ 1, 2 }}, .{.{ 3, 4 }} }, "[ [ [ 1 , 2 ] ] , [ [ 3 , 4 ] ] ]" },
    });
}

test "parse - bool" {
    try testParseEqual(bool, &.{
        .{ true, "true" },
        .{ true, " true " },
        .{ false, "false" },
        .{ false, " false " },
    });
}

test "parse - enum" {
    const Enum = enum { foo, @"bar\n" };

    try testParseEqual(Enum, &.{
        .{ .foo, "0" },
        .{ .foo, "\"foo\"" },
        .{ .@"bar\n", "1" },
        .{ .@"bar\n", "\"bar\\n\"" },
    });
}

test "parse - float" {
    try testParseEqual(f64, &.{
        .{ 0.0, "0.0" },
        .{ 3.0, "3.0" },
        .{ 3.1, "3.1" },
        .{ -1.2, "-1.2" },
        .{ 0.4, "0.4" },

        .{ 3.0, "3.00" },
        .{ 0.4e5, "0.4e5" },
        .{ 0.4e5, "0.4e+5" },
        .{ 0.4e15, "0.4e15" },
        .{ 0.4e15, "0.4e+15" },
        .{ 0.4e-1, "0.4e-01" },
        .{ 0.4e-1, " 0.4e-01 " },
        .{ 0.4e-1, "0.4e-001" },
        .{ 0.4e0, "0.4e-0" },
        .{ 0.0, "0.00e00" },
        .{ 0.0, "0.00e+00" },
        .{ 0.0, "0.00e-00" },
        .{ 0.0, "3.5E-2147483647" },
        .{ 0.0, "0e1000000000000000000000000000000000000000000000" },
        .{ 0.0, "100e-777777777777777777777777777" },
        .{ 0.01, "0.0100000000000000000001" },
        .{ 1.23, "0.0000000000000000000000000000000000000000000000000123e50" },
        .{ 10101010101010101010e20, "1010101010101010101010101010101010101010" },
        .{ 0.1010101010101010101, "0.1010101010101010101010101010101010101010" },
        .{
            1e308, "1000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "00000000",
        },
        .{
            1e308, "1000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                ".0e8",
        },
        .{
            1e308, "1000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "e8",
        },
        .{
            1e308, "1000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000000000000000000000000000000000000000000000" ++
                "000000000000000000e-10",
        },

        .{ std.math.floatMin(f64), "2.2250738585072014e-308" },
        .{ std.math.floatMax(f64), "1.79769313486231570815e+308" },
        .{ std.math.floatEps(f64), "2.22044604925031308085e-16" },
        .{ @as(f64, std.math.minInt(i64)) - 1.0, "-9223372036854775807" },
        .{ @as(f64, std.math.maxInt(i64)) + 1.0, "9223372036854775808" },
    });
}

test "parse - int" {
    // From integer
    try testParseEqual(i64, &.{
        .{ 0, "-0" },
        .{ -1, "-1" },
        .{ -1234, "-1234" },
        .{ -1234, " -1234 " },
        .{ std.math.minInt(i64), "-9223372036854775808" },
        .{ std.math.maxInt(i64), "9223372036854775807" },
    });
    try testParseEqual(u64, &.{
        .{ 0, "0" },
        .{ 1, "1" },
        .{ 1234, "1234" },
        .{ 1234, " 1234 " },
        .{ std.math.maxInt(u64), "18446744073709551615" },
    });

    // From string
    try testParseEqual(i64, &.{
        .{ 0, "\"-0\"" },
        .{ -1, "\"-1\"" },
        .{ -1234, "\"-1234\"" },
        .{ -1234, " \"-1234\" " },
        .{ std.math.minInt(i64), "\"-9223372036854775808\"" },
        .{ std.math.maxInt(i64), "\"9223372036854775807\"" },
    });
    try testParseEqual(u64, &.{
        .{ 0, "\"0\"" },
        .{ 1, "\"1\"" },
        .{ 1234, "\"1234\"" },
        .{ 1234, " \"1234\" " },
        .{ std.math.maxInt(u64), "\"18446744073709551615\"" },
    });
}

test "parse - int (string)" {}

test "parse - int (custom type)" {
    const Foo = struct {
        int: i32,

        pub const @"getty.db" = struct {
            pub fn deserialize(
                ally: std.mem.Allocator,
                comptime _: type,
                deserializer: anytype,
                visitor: anytype,
            ) @TypeOf(deserializer).Err!@TypeOf(visitor).Value {
                return try deserializer.deserializeInt(ally, visitor);
            }

            pub fn Visitor(comptime Value: type) type {
                return struct {
                    pub usingnamespace getty.de.Visitor(
                        @This(),
                        Value,
                        .{ .visitInt = visitInt },
                    );

                    pub fn visitInt(
                        _: @This(),
                        _: std.mem.Allocator,
                        comptime De: type,
                        input: anytype,
                    ) De.Err!Value {
                        return .{ .int = std.math.cast(i32, input) orelse return error.Overflow };
                    }
                };
            }
        };
    };

    try testParseEqual(Foo, &.{
        .{ .{ .int = 0 }, "0" },
        .{ .{ .int = 1 }, "  1 " },
        .{ .{ .int = 12345 }, "12345" },
        .{ .{ .int = -1 }, "-1 " },
        .{ .{ .int = -12345 }, " -12345  " },
    });
}

test "parse - list (std.ArrayList)" {
    {
        const input = "[1,2,3,4]";

        var want = std.ArrayList(u8).init(test_ally);
        defer want.deinit();
        try want.appendSlice(&.{ 1, 2, 3, 4 });

        var result = try json.fromSlice(test_ally, @TypeOf(want), input);
        defer result.deinit();
        const got = result.value;

        try require.equal(want.items, got.items);
    }

    {
        const input = "[[1, 2],[3,4]]";

        var want = std.ArrayList(std.ArrayList(u8)).init(test_ally);
        var one = std.ArrayList(u8).init(test_ally);
        var two = std.ArrayList(u8).init(test_ally);
        defer {
            one.deinit();
            two.deinit();
            want.deinit();
        }
        try one.appendSlice(&.{ 1, 2 });
        try two.appendSlice(&.{ 3, 4 });
        try want.appendSlice(&.{ one, two });

        var result = try json.fromSlice(test_ally, @TypeOf(want), input);
        defer result.deinit();
        const got = result.value;

        try require.equalType(@TypeOf(want), got);
        try require.len(got.items, want.items.len);
        for (want.items, 0..) |w, i| {
            try require.equal(w.items, got.items[i].items);
        }
    }
}

test "parse - object (std.AutoHashMap)" {
    {
        var result = try json.fromSlice(test_ally, std.AutoHashMap(i32, []const u8),
            \\{
            \\  "1": "foo",
            \\  "2": "bar",
            \\  "3": "baz"
            \\}
        );
        defer result.deinit();

        const got = result.value;

        try require.equalType(std.AutoHashMap(i32, []const u8), got);
        try require.equal(@as(u32, 3), got.count());
        try require.equal("foo", got.get(1).?);
        try require.equal("bar", got.get(2).?);
        try require.equal("baz", got.get(3).?);
    }

    {
        var result = try json.fromSlice(test_ally, std.AutoHashMap(i32, std.AutoHashMap(i32, []const u8)),
            \\{
            \\  "1": { "4": "foo" },
            \\  "2": { "5": "bar" },
            \\  "3": { "6": "baz" }
            \\}
        );
        defer result.deinit();

        const got = result.value;

        var a = std.AutoHashMap(i32, []const u8).init(test_ally);
        var b = std.AutoHashMap(i32, []const u8).init(test_ally);
        var c = std.AutoHashMap(i32, []const u8).init(test_ally);
        defer {
            a.deinit();
            b.deinit();
            c.deinit();
        }

        try a.put(4, "foo");
        try b.put(5, "bar");
        try c.put(6, "baz");

        try require.equalType(std.AutoHashMap(i32, std.AutoHashMap(i32, []const u8)), got);
        try require.equal(@as(u32, 3), got.count());
        try require.equalType(@TypeOf(a), got.get(1).?);
        try require.equalType(@TypeOf(b), got.get(2).?);
        try require.equalType(@TypeOf(c), got.get(3).?);
        try require.equal(a.get(4).?, got.get(1).?.get(4).?);
        try require.equal(b.get(5).?, got.get(2).?.get(5).?);
        try require.equal(c.get(6).?, got.get(3).?.get(6).?);
    }
}

test "parse - object (std.StringHashMap)" {
    {
        var result = try json.fromSlice(test_ally, std.StringHashMap(u8),
            \\{
            \\  "\"a": 1,
            \\  "b": 2,
            \\  "c": 3
            \\}
        );
        defer result.deinit();

        const got = result.value;

        try require.equalType(std.StringHashMap(u8), got);
        try require.equal(@as(u32, 3), got.count());
        try require.equal(@as(u8, 1), got.get("\"a").?);
        try require.equal(@as(u8, 2), got.get("b").?);
        try require.equal(@as(u8, 3), got.get("c").?);
    }

    {
        var result = try json.fromSlice(test_ally, std.StringHashMap([]const u8),
            \\{
            \\  "\"a": "foo",
            \\  "b": "bar",
            \\  "c": "baz"
            \\}
        );
        defer result.deinit();

        const got = result.value;

        try require.equalType(std.StringHashMap([]const u8), got);
        try require.equal(@as(u32, 3), got.count());
        try require.equal("foo", got.get("\"a").?);
        try require.equal("bar", got.get("b").?);
        try require.equal("baz", got.get("c").?);
    }

    {
        var result = try json.fromSlice(test_ally, std.StringHashMap(std.StringHashMap([]const u8)),
            \\{
            \\  "\"a": { "\"d": "foo" },
            \\  "b": { "e": "bar" },
            \\  "c": { "f": "baz" }
            \\}
        );
        defer result.deinit();

        const got = result.value;

        var a = std.StringHashMap([]const u8).init(test_ally);
        var b = std.StringHashMap([]const u8).init(test_ally);
        var c = std.StringHashMap([]const u8).init(test_ally);
        defer {
            a.deinit();
            b.deinit();
            c.deinit();
        }

        try a.put("\"d", "foo");
        try b.put("e", "bar");
        try c.put("f", "baz");

        try require.equalType(std.StringHashMap(std.StringHashMap([]const u8)), got);
        try require.equal(@as(u32, 3), got.count());
        try require.equalType(@TypeOf(a), got.get("\"a").?);
        try require.equalType(@TypeOf(b), got.get("b").?);
        try require.equalType(@TypeOf(c), got.get("c").?);
        try require.equal(a.get("\"d").?, got.get("\"a").?.get("\"d").?);
        try require.equal(b.get("e").?, got.get("b").?.get("e").?);
        try require.equal(c.get("f").?, got.get("c").?.get("f").?);
    }
}

test "parse - optional" {
    try testParseEqual(?bool, &.{
        .{ null, "null" },
        .{ true, "true" },
    });
}

test "parse - pointer" {
    try testParseEqual(*const bool, &.{
        .{ &true, "true" },
    });

    try testParseEqual(*const *const []const u8, &.{
        .{ &&@as([]const u8, "abc"), "\"abc\"" },
    });
}

test "parse - slice" {
    // Strings.
    try testParseEqual([]const u8, &.{
        .{ "", "\"\"" },
        .{ "foo", "\"foo\"" },
        .{ "foo", " \"foo\" " },
        .{ "\"", "\"\\\"\"" },
        .{ "\x08", "\"\\b\"" },
        .{ "\n", "\"\\n\"" },
        .{ "\r", "\"\\r\"" },
        .{ "\t", "\"\\t\"" },
        .{ "\u{12ab}", "\"\\u12ab\"" },
        .{ "\u{AB12}", "\"\\uAB12\"" },
        .{ "\u{1F395}", "\"\\uD83C\\uDF95\"" },
    });

    try testParseEqual([:0]const u8, &.{
        .{ "", "\"\"" },
        .{ "foo", "\"foo\"" },
        .{ "foo", " \"foo\" " },
        .{ "\"", "\"\\\"\"" },
        .{ "\x08", "\"\\b\"" },
        .{ "\n", "\"\\n\"" },
        .{ "\r", "\"\\r\"" },
        .{ "\t", "\"\\t\"" },
        .{ "\u{12ab}", "\"\\u12ab\"" },
        .{ "\u{AB12}", "\"\\uAB12\"" },
        .{ "\u{1F395}", "\"\\uD83C\\uDF95\"" },
    });

    // Non-strings.
    try testParseEqual([]const i32, &.{
        .{ &.{ 1, 2, 3, 4, 5 }, "[1,2,3,4,5]" },
    });

    try testParseEqual([]const [3]i32, &.{
        .{
            &.{
                .{ 1, 2, 3 },
                .{ 4, 5, 6 },
                .{ 7, 8, 9 },
            },
            "[[1,2,3],[4,5,6],[7,8,9]]",
        },
    });

    try testParseEqual([]const []const i32, &.{
        .{
            &.{
                &.{1},
                &.{ 2, 3 },
                &.{ 4, 5, 6 },
                &.{ 7, 8, 9, 10 },
            },
            "[[1],[2,3],[4,5,6],[7,8,9,10]]",
        },
    });

    try testParseEqual([]const []const u8, &.{
        .{
            &.{
                "Foo",
                "Bar",
                "Foobar",
            },
            \\["Foo","Bar","Foobar"]
        },
    });
}

test "parse - struct" {
    const Inner = struct {
        a: void,
        b: usize,
        c: []const []const u8,
    };

    const Outer = struct {
        inner: []const Inner,
    };

    try testParseEqual(Outer, &.{
        .{
            .{ .inner = &.{} },
            \\{
            \\    "inner": []
            \\}
        },
        .{
            .{
                .inner = &.{
                    .{ .a = {}, .b = 1, .c = &.{ "abc", "xyz" } },
                },
            },
            \\{
            \\    "inner": [
            \\        { "a": null, "b": 1, "c": ["abc", "xyz"] }
            \\    ]
            \\}
        },
        .{
            .{
                .inner = &.{
                    .{ .a = {}, .b = 1, .c = &.{ "abc", "xyz" } },
                    .{ .a = {}, .b = 2, .c = &.{ "abc", "def", "xyz" } },
                },
            },
            \\{
            \\    "inner": [
            \\        { "a": null, "b": 1, "c": ["abc", "xyz"] },
            \\        { "a": null, "b": 2, "c": ["abc", "def", "xyz"] }
            \\    ]
            \\}
        },
    });
}

// TODO: Uncomment test once https://github.com/getty-zig/getty/issues/135 finished.
test "parse - union" {
    const Tagged = union(enum) { foo: bool, bar: void };
    try testParseEqual(Tagged, &.{
        .{ .{ .foo = true }, "{\"foo\":true}" },
        .{ .{ .bar = {} }, "{\"bar\":null}" },
    });

    const Untagged = union { foo: bool, bar: void };
    const want_foo = Untagged{ .foo = false };
    const want_bar = Untagged{ .bar = {} };
    const result_foo = try json.fromSlice(test_ally, Untagged, "{\"foo\":false}");
    defer result_foo.deinit();
    const result_bar = try json.fromSlice(test_ally, Untagged, "{\"bar\":null}");
    defer result_bar.deinit();

    try require.equal(want_foo.foo, result_foo.value.foo);
    try require.equal(want_bar.bar, result_bar.value.bar);
}

test "parse - void" {
    try testParseEqual(void, &.{
        .{ {}, "null" },
    });
}

fn testEncodeEqual(comptime T: type, tests: EncodeTest(T)) !void {
    for (tests) |t| {
        const want = t[0];
        const value = t[1];

        const got = try json.toSlice(test_ally, value);
        defer test_ally.free(got);

        try require.equal(want, got);
    }
}

fn testPrettyEncodeEqual(comptime T: type, tests: EncodeTest(T)) !void {
    for (tests) |t| {
        const want = t[0];
        const value = t[1];

        const got = try json.toPrettySlice(test_ally, value);
        defer test_ally.free(got);

        try require.equal(want, got);
    }
}

fn testParseEqual(comptime T: type, tests: ParseTest(T)) !void {
    for (tests) |t| {
        const want = t[0];
        const input = t[1];

        var result = try json.fromSlice(test_ally, T, input);
        defer result.deinit();

        try require.equal(want, result.value);
    }
}

fn EncodeTest(comptime T: type) type {
    return []const std.meta.Tuple(&.{ []const u8, T });
}

fn ParseTest(comptime T: type) type {
    return []const std.meta.Tuple(&.{ T, []const u8 });
}
