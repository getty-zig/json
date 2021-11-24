<p align="center">
  <img alt="Getty" src="https://github.com/getty-zig/logo/blob/main/getty-solid.svg" width="410px">
  <br/>
  <br/>
  <a href="https://github.com/getty-zig/json/releases/latest"><img alt="Version" src="https://img.shields.io/badge/version-N/A-e2725b.svg?style=flat-square"></a>
  <a href="https://ziglang.org/download"><img alt="Zig" src="https://img.shields.io/badge/zig-master-fd9930.svg?style=flat-square"></a>
  <a href="https://actions-badge.atrox.dev/getty-zig/json/goto?ref=main"><img alt="Build status" src="https://img.shields.io/endpoint.svg?url=https%3A%2F%2Factions-badge.atrox.dev%2Fgetty-zig%2Fjson%2Fbadge%3Fref%3Dmain&style=flat-square" /></a>
  <a href="https://github.com/getty-zig/json/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square"></a>
</p>

<p align="center">A serialization library for the JSON data format.</p>

## API Reference

### Serialization

<details>
<summary><code>toSlice</code> - Serializes a value as a JSON string.</summary>

- **Synopsis**

    ```zig
    fn toSlice(allocator: *std.mem.Allocator, value: anytype) ![]const u8
    ```
  
- **Example**
  
    ```zig
    const std = @import("std");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    pub fn main() anyerror!void {
        const string = try json.toSlice(allocator, Coordinate{ .x = 1, .y = 2, .z = 3 });
        defer allocator.free(string);

        // {"x":1,"y":2,"z":3}
        std.debug.print("{s}\n", .{string});
    }
    ```
    </details>

<details>
<summary><code>toPrettySlice</code> - Serializes a value as a pretty-printed JSON string.</summary>

- **Synopsis**

    ```zig
    fn toPrettySlice(allocator: *std.mem.Allocator, value: anytype) ![]const u8
    ```
  
- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    pub fn main() anyerror!void {
        const string = try json.toPrettySlice(allocator, Coordinate{ .x = 1, .y = 2, .z = 3 });
        defer allocator.free(string);

        // {
        //   "x": 1,
        //   "y": 2,
        //   "z": 3
        // }
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toSliceWith</code> - Serializes a value as a JSON string using a <code>getty.Ser</code> value.</summary>

- **Synopsis**

    ```zig
    fn toSliceWith(allocator: *std.mem.Allocator, value: anytype, ser: anytype) ![]const u8
    ```
  
- **Example**

    ```zig
    const std = @import("std");
    const getty = @import("getty");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    const Ser = struct {
        pub usingnamespace getty.Ser(@This(), serialize);

        fn serialize(_: @This(), value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            comptime std.debug.assert(@TypeOf(value) == Coordinate);

            const seq = (try serializer.serializeSequence(3)).sequenceSerialize();
            try seq.serializeElement(value.x);
            try seq.serializeElement(value.y);
            try seq.serializeElement(value.z);
            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const s = Ser{};
        const ser = s.ser();

        const string = try json.toSliceWith(allocator, Coordinate{ .x = 1, .y = 2, .z = 3 }, ser);
        defer allocator.free(string);


        // [1,2,3]
        std.debug.print("{s}\n", .{string});
    }
    ```
</details>

<details>
<summary><code>toPrettySliceWith</code> - Serializes a value as a JSON string using a <code>getty.Ser</code> value.</summary>

- **Synopsis**

    ```zig
    fn toPrettySliceWith(allocator: *std.mem.Allocator, value: anytype, ser: anytype) ![]const u8
    ```
  
- **Example**

    ```zig
    const std = @import("std");
    const getty = @import("getty");
    const json = @import("json");

    const allocator = std.heap.page_allocator;

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    const Ser = struct {
        pub usingnamespace getty.Ser(@This(), serialize);

        fn serialize(_: @This(), value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            comptime std.debug.assert(@TypeOf(value) == Coordinate);

            const seq = (try serializer.serializeSequence(3)).sequenceSerialize();
            try seq.serializeElement(value.x);
            try seq.serializeElement(value.y);
            try seq.serializeElement(value.z);
            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const s = Ser{};
        const ser = s.ser();

        const string = try json.toPrettySliceWith(allocator, Coordinate{ .x = 1, .y = 2, .z = 3 }, ser);
        defer allocator.free(string);

        // [
        //   1,
        //   2,
        //   3
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

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    pub fn main() anyerror!void {
        const stdout = std.io.getStdOut().writer();

        // {"x":1,"y":2,"z":3}
        try json.toWriter(Coordinate{ .x = 1, .y = 2, .z = 3 }, stdout);
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

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    pub fn main() anyerror!void {
        const stdout = std.io.getStdOut().writer();

        // {
        //   "x": 1,
        //   "y": 2,
        //   "z": 3
        // }
        try json.toPrettyWriter(Coordinate{ .x = 1, .y = 2, .z = 3 }, stdout);
    }
    ```
</details>

<details>
<summary><code>toWriterWith</code> - Serializes a value as JSON into an I/O stream using a <code>getty.Ser</code> value.</summary>

- **Synopsis**

    ```zig
    fn toWriterWith(value: anytype, writer: anytype, ser: anytype) !void
    ```
  
- **Example**

    ```zig
    const std = @import("std");
    const getty = @import("getty");
    const json = @import("json");

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    const Ser = struct {
        pub usingnamespace getty.Ser(@This(), serialize);

        fn serialize(_: @This(), value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            comptime std.debug.assert(@TypeOf(value) == Coordinate);

            const seq = (try serializer.serializeSequence(3)).sequenceSerialize();
            try seq.serializeElement(value.x);
            try seq.serializeElement(value.y);
            try seq.serializeElement(value.z);
            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const stdout = std.io.getStdOut().writer();

        const s = Ser{};
        const ser = s.ser();

        // [1,2,3]
        try json.toWriterWith(Coordinate{ .x = 1, .y = 2, .z = 3 }, stdout, ser);
    }
    ```
</details>

<details>
<summary><code>toPrettyWriterWith</code> - Serializes a value as pretty-printed JSON into an I/O stream using a <code>getty.Ser</code> value.</summary>

- **Synopsis**

    ```zig
    fn toPrettyWriterWith(value: anytype, writer: anytype, ser: anytype) !void
    ```
  
- **Example**

    ```zig
    const std = @import("std");
    const getty = @import("getty");
    const json = @import("json");

    const Coordinate = struct {
        x: i32,
        y: i32,
        z: i32,
    };

    const Ser = struct {
        pub usingnamespace getty.Ser(@This(), serialize);

        fn serialize(_: @This(), value: anytype, serializer: anytype) !@TypeOf(serializer).Ok {
            comptime std.debug.assert(@TypeOf(value) == Coordinate);

            const seq = (try serializer.serializeSequence(3)).sequenceSerialize();
            try seq.serializeElement(value.x);
            try seq.serializeElement(value.y);
            try seq.serializeElement(value.z);
            return try seq.end();
        }
    };

    pub fn main() anyerror!void {
        const stdout = std.io.getStdOut().writer();

        const s = Ser{};
        const ser = s.ser();

        // [
        //   1,
        //   2,
        //   3
        // ]
        try json.toPrettyWriterWith(Coordinate{ .x = 1, .y = 2, .z = 3 }, stdout, ser);
    }
    ```
</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
