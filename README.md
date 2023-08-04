<br/>

<p align="center">
  <img alt="Getty" src="https://github.com/getty-zig/logo/blob/main/getty-solid.svg" width="410px">
  <br/>
  <br/>
  <a href="https://github.com/getty-zig/json/releases/latest"><img alt="Version" src="https://img.shields.io/github/v/release/getty-zig/json?include_prereleases&label=version"></a>
  <a href="https://github.com/getty-zig/json/actions/workflows/test.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/getty-zig/json/test.yml?branch=main" /></a>
  <a href="https://ziglang.org/download"><img alt="Zig" src="https://img.shields.io/badge/zig-master-fd9930.svg"></a>
  <a href="https://github.com/getty-zig/json/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

## Overview

_Getty JSON_ is a (de)serialization library for the JSON data format.

## Installation

### Manual

1. Declare Getty JSON as a dependency in `build.zig.zon`:

    ```diff
    .{
        .name = "my-project",
        .version = "1.0.0",
        .dependencies = .{
    +       .json = .{
    +           .url = "https://github.com/getty-zig/json/archive/<COMMIT>.tar.gz",
    +       },
        },
    }
    ```

2. Expose Getty JSON as a module in `build.zig`:

    ```diff
    const std = @import("std");

    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

    +   const opts = .{ .target = target, .optimize = optimize };
    +   const json_module = b.dependency("json", opts).module("json");

        const exe = b.addExecutable(.{
            .name = "test",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
    +   exe.addModule("json", json_module);
        exe.install();

        ...
    }
    ```

3. Obtain Getty JSON's package hash:

    ```
    $ zig build
    my-project/build.zig.zon:6:20: error: url field is missing corresponding hash field
            .url = "https://github.com/getty-zig/json/archive/<COMMIT>.tar.gz",
                   ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    note: expected .hash = "<HASH>",
    ```

4. Update `build.zig.zon` with hash value:

    ```diff
    .{
        .name = "my-project",
        .version = "1.0.0",
        .dependencies = .{
            .json = .{
                .url = "https://github.com/getty-zig/json/archive/<COMMIT>.tar.gz",
    +           .hash = "<HASH>",
            },
        },
    }
    ```

## API Reference

### Serialization

<details>
<summary><code>toSlice</code> - Serializes a value as a JSON string.</summary>

- **Synopsis**

    ```zig
    fn toSlice(ally: std.mem.Allocator, value: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const page_ally = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const string = try json.toSlice(page_ally, point);
        defer page_ally.free(string);

        // {"x":1,"y":2}
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toPrettySlice</code> - Serializes a value as a pretty-printed JSON string.</summary>

- **Synopsis**

    ```zig
    fn toPrettySlice(ally: std.mem.Allocator, value: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const page_ally = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const string = try json.toPrettySlice(page_ally, point);
        defer page_ally.free(string);

        // {
        //   "x": 1,
        //   "y": 2
        // }
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toSliceWith</code> - Serializes a value as a JSON string using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toSliceWith(ally: std.mem.Allocator, value: anytype, ser: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const page_ally = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    const block = struct {
        pub fn is(comptime T: type) bool {
            return T == Point;
        }

        pub fn serialize(value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            var s = try serializer.serializeSeq(2);
            const seq = s.seq();

            inline for (std.meta.fields(Point)) |field| {
                try seq.serializeElement(@field(value, field.name));
            }

            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const string = try json.toSliceWith(page_ally, point, block);
        defer page_ally.free(string);

        // [1,2]
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toPrettySliceWith</code> - Serializes a value as a JSON string using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toPrettySliceWith(ally: std.mem.Allocator, value: anytype, ser: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const page_ally = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    const block = struct {
        pub fn is(comptime T: type) bool {
            return T == Point;
        }

        pub fn serialize(value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            var s = try serializer.serializeSeq(2);
            const seq = s.seq();

            inline for (std.meta.fields(Point)) |field| {
                try seq.serializeElement(@field(value, field.name));
            }

            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const string = try json.toPrettySliceWith(page_ally, point, block);
        defer page_ally.free(string);

        // [
        //   1,
        //   2
        // ]
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toWriter</code> - Serializes a value as JSON into an I/O stream.</summary>

- **Synopsis**

    ```zig
    fn toWriter(ally: ?std.mem.Allocator, value: anytype, writer: anytype) !void
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const Point = struct { x: i32, y: i32 };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const stdout = std.io.getStdOut().writer();

        // {"x":1,"y":2}
        try json.toWriter(null, point, stdout);
    }
    ```
</details>

<details>
<summary><code>toPrettyWriter</code> - Serializes a value as pretty-printed JSON into an I/O stream.</summary>

- **Synopsis**

    ```zig
    fn toPrettyWriter(ally: ?std.mem.Allocator, value: anytype, writer: anytype) !void
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const Point = struct { x: i32, y: i32 };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const stdout = std.io.getStdOut().writer();

        // {
        //   "x": 1,
        //   "y": 2
        // }
        try json.toPrettyWriter(null, point, stdout);
    }
    ```
</details>

<details>
<summary><code>toWriterWith</code> - Serializes a value as JSON into an I/O stream using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toWriterWith(ally: ?std.mem.Allocator, value: anytype, writer: anytype, ser: anytype) !void
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const Point = struct { x: i32, y: i32 };

    const block = struct {
        pub fn is(comptime T: type) bool {
            return T == Point;
        }

        pub fn serialize(value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            var s = try serializer.serializeSeq(2);
            const seq = s.seq();

            try seq.serializeElement(value.x);
            try seq.serializeElement(value.y);

            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const stdout = std.io.getStdOut().writer();

        // [1,2]
        try json.toWriterWith(null, point, stdout, block);
    }
    ```
</details>

<details>
<summary><code>toPrettyWriterWith</code> - Serializes a value as pretty-printed JSON into an I/O stream using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toPrettyWriterWith(ally: ?std.mem.Allocator, value: anytype, writer: anytype, ser: anytype) !void
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const Point = struct { x: i32, y: i32 };

    const block = struct {
        pub fn is(comptime T: type) bool {
            return T == Point;
        }

        pub fn serialize(value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            var s = try serializer.serializeSeq(2);
            const seq = s.seq();

            try seq.serializeElement(value.x);
            try seq.serializeElement(value.y);

            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const stdout = std.io.getStdOut().writer();

        // [
        //   1,
        //   2
        // ]
        try json.toPrettyWriterWith(null, point, stdout, block);
    }
    ```
</details>

### Deserialization

<details>
<summary><code>fromSlice</code> - Deserializes a value of type <code>T</code> from a string of JSON text.</summary>

- **Synopsis**

    ```zig
    fn fromSlice(ally: std.mem.Allocator, comptime T: type, slice: []const u8) !T
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const page_ally = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };
    const string =
        \\{
        \\  "x": 1,
        \\  "y": 2
        \\}
    ;

    pub fn main() anyerror!void {
        const point = try json.fromSlice(page_ally, Point, string);

        // Point{ .x = 1, .y = 2 }
        std.debug.print("{any}\n", .{point});
    }
    ```
</details>

<details>
<summary><code>fromSliceWith</code> - Deserializes a value of type <code>T</code> from a string of JSON text using a Deserialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn fromSliceWith(
        ally: std.mem.Allocator,
        comptime T: type,
        slice: []const u8,
        de: anytype,
    ) !T
    ```

- **Example**

    ```zig
    const std = @import("std");
    const getty = @import("getty");
    const json = @import("json");

    const page_ally = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    const block = struct {
        pub fn is(comptime T: type) bool {
            return T == Point;
        }

        pub fn deserialize(ally: ?std.mem.Allocator, comptime _: type, deserializer: anytype, visitor: anytype) !Point {
            return try deserializer.deserializeSeq(ally, visitor);
        }

        pub fn Visitor(comptime _: type) type {
            return struct {
                pub usingnamespace getty.de.Visitor(
                    @This(),
                    Point,
                    .{ .visitSeq = visitSeq },
                );

                pub fn visitSeq(_: @This(), ally: ?std.mem.Allocator, comptime _: type, seq: anytype) !Point {
                    var point: Point = undefined;

                    inline for (std.meta.fields(Point)) |field| {
                        if (try seq.nextElement(ally, i32)) |elem| {
                            @field(point, field.name) = elem;
                        }
                    }

                    if ((try seq.nextElement(ally, i32)) != null) {
                        return error.InvalidLength;
                    }

                    return point;
                }
            };
        }
    };

    pub fn main() anyerror!void {
        const point = try json.fromSliceWith(page_ally, Point, "[1,2]", block);

        // Point{ .x = 1, .y = 2 }
        std.debug.print("{any}\n", .{point});
    }
    ```
</details>
