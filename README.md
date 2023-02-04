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

1. Add Getty JSON to your project:

    ```
    git clone --recursive https://github.com/getty-zig/json libs/json
    ```

2. Make the following changes in `build.zig`:

    ```diff
    const std = @import("std");
    +const json = @import("libs/json/build.zig");

    pub fn build(b: *std.build.Builder) void {
        // ...

        const exe = b.addExecutable("my-project", "src/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
    +   exe.addPackage(json.pkg(b));
        exe.install();
    }
    ```

### Gyro

1. Add Getty JSON to your project:

    ```
    gyro add -s github getty-zig/json
    gyro fetch
    ```

2. Make the following changes in `build.zig`:

    ```diff
    const std = @import("std");
    +const pkgs = @import("deps.zig").pkgs;

    pub fn build(b: *std.build.Builder) void {
        // ...

        const exe = b.addExecutable("my-project", "src/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
    +   pkgs.addAllTo(exe);
        exe.install();
    }
    ```

### Zigmod

1. Make the following change in `zigmod.yml`:

    ```diff
    # ...

    root_dependencies:
    +  - src: git https://github.com/getty-zig/json
    ```

2. Add Getty JSON to your project:

    ```
    zigmod fetch
    ```

3. Make the following changes in `build.zig`:

    ```diff
    const std = @import("std");
    +const deps = @import("deps.zig");

    pub fn build(b: *std.build.Builder) void {
        // ...

        const exe = b.addExecutable("my-project", "src/main.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
    +   deps.addAllTo(exe);
        exe.install();
    }
    ```

## API Reference

### Serialization

<details>
<summary><code>toSlice</code> - Serializes a value as a JSON string.</summary>

- **Synopsis**

    ```zig
    fn toSlice(allocator: std.mem.Allocator, value: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const string = try json.toSlice(allocator, point);
        defer allocator.free(string);

        // {"x":1,"y":2}
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toPrettySlice</code> - Serializes a value as a pretty-printed JSON string.</summary>

- **Synopsis**

    ```zig
    fn toPrettySlice(allocator: std.mem.Allocator, value: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

    const Point = struct { x: i32, y: i32 };

    pub fn main() anyerror!void {
        const point = Point{ .x = 1, .y = 2 };

        const string = try json.toPrettySlice(allocator, point);
        defer allocator.free(string);

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
    fn toSliceWith(allocator: std.mem.Allocator, value: anytype, ser: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

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

        const string = try json.toSliceWith(allocator, point, block);
        defer allocator.free(string);

        // [1,2]
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toPrettySliceWith</code> - Serializes a value as a JSON string using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toPrettySliceWith(allocator: std.mem.Allocator, value: anytype, ser: anytype) ![]const u8
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

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

        const string = try json.toPrettySliceWith(allocator, point, block);
        defer allocator.free(string);

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
    fn toWriter(value: anytype, writer: anytype) !void
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
        try json.toWriter(point, stdout);
    }
    ```
</details>

<details>
<summary><code>toPrettyWriter</code> - Serializes a value as pretty-printed JSON into an I/O stream.</summary>

- **Synopsis**

    ```zig
    fn toPrettyWriter(value: anytype, writer: anytype) !void
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
        try json.toPrettyWriter(point, stdout);
    }
    ```
</details>

<details>
<summary><code>toWriterWith</code> - Serializes a value as JSON into an I/O stream using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toWriterWith(value: anytype, writer: anytype, ser: anytype) !void
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
        try json.toWriterWith(point, stdout, block);
    }
    ```
</details>

<details>
<summary><code>toPrettyWriterWith</code> - Serializes a value as pretty-printed JSON into an I/O stream using a Serialization Block or Tuple.</summary>

- **Synopsis**

    ```zig
    fn toPrettyWriterWith(value: anytype, writer: anytype, ser: anytype) !void
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
        try json.toPrettyWriterWith(point, stdout, block);
    }
    ```
</details>

### Deserialization

<details>
<summary><code>fromSlice</code> - Deserializes a value of type <code>T</code> from a string of JSON text.</summary>

- **Synopsis**

    ```zig
    fn fromSlice(allocator: ?std.mem.Allocator, comptime T: type, slice: []const u8) !T
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const Point = struct { x: i32, y: i32 };
    const string =
        \\{
        \\  "x": 1,
        \\  "y": 2
        \\}
    ;

    pub fn main() anyerror!void {
        const point = try json.fromSlice(null, Point, string);

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
        allocator: ?std.mem.Allocator,
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

    const Point = struct { x: i32, y: i32 };

    const block = struct {
        pub fn is(comptime T: type) bool {
            return T == Point;
        }

        pub fn deserialize(allocator: ?std.mem.Allocator, comptime _: type, deserializer: anytype, visitor: anytype) !Point {
            return try deserializer.deserializeSeq(allocator, visitor);
        }

        pub fn Visitor(comptime _: type) type {
            return struct {
                pub usingnamespace getty.de.Visitor(
                    @This(),
                    Point,
                    .{ .visitSeq = visitSeq },
                );

                pub fn visitSeq(_: @This(), allocator: ?std.mem.Allocator, comptime _: type, seq: anytype) !Point {
                    var point: Point = undefined;

                    inline for (std.meta.fields(Point)) |field| {
                        if (try seq.nextElement(allocator, i32)) |elem| {
                            @field(point, field.name) = elem;
                        }
                    }

                    if ((try seq.nextElement(allocator, i32)) != null) {
                        return error.InvalidLength;
                    }

                    return point;
                }
            };
        }
    };

    pub fn main() anyerror!void {
        const point = try json.fromSliceWith(null, Point, "[1,2]", block);

        // Point{ .x = 1, .y = 2 }
        std.debug.print("{any}\n", .{point});
    }
    ```
</details>
