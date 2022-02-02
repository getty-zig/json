<p align="center">
  <img alt="Getty" src="https://github.com/getty-zig/logo/blob/main/getty-solid.svg" width="410px">
  <br/>
  <br/>
  <a href="https://github.com/getty-zig/json/releases/latest"><img alt="Version" src="https://img.shields.io/badge/version-N/A-e2725b.svg?style=flat-square"></a>
  <a href="https://ziglang.org/download"><img alt="Zig" src="https://img.shields.io/badge/zig-0.9.0-fd9930.svg?style=flat-square"></a>
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

    pub fn main() anyerror!void {
        const string = try json.toSlice(allocator, coordinate);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

    pub fn main() anyerror!void {
        const string = try json.toPrettySlice(allocator, coordinate);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

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

        const string = try json.toSliceWith(allocator, coordinate, ser);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

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

        const string = try json.toPrettySliceWith(allocator, coordinate, ser);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

    pub fn main() anyerror!void {
        const stdout = std.io.getStdOut().writer();

        // {"x":1,"y":2,"z":3}
        try json.toWriter(coordinate, stdout);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

    pub fn main() anyerror!void {
        const stdout = std.io.getStdOut().writer();

        // {
        //   "x": 1,
        //   "y": 2,
        //   "z": 3
        // }
        try json.toPrettyWriter(coordinate, stdout);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

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
        try json.toWriterWith(coordinate, stdout, ser);
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const coordinate = Coordinate{ .x = 1, .y = 2, .z = 3 };

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
        try json.toPrettyWriterWith(coordinate, stdout, ser);
    }
    ```
</details>

### Deserialization

<details>
<summary><code>fromSlice</code> - Deserializes a value of type <code>T</code> from a string of JSON text.</summary>

- **Synopsis**

    ```zig
    fn fromSlice(allocator: ?*std.mem.Allocator, comptime T: type, slice: []const u8) !T
    ```

- **Example**

    ```zig
    const std = @import("std");
    const json = @import("json");

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const string =
        \\{
        \\  "x": 1,
        \\  "y": 2,
        \\  "z": 3
        \\}
    ;

    pub fn main() anyerror!void {
        const coordinate = try json.fromSlice(null, Coordinate, string);

        // Coordinate{ .x = 1, .y = 2, .z = 3 }
        std.debug.print("{any}\n", .{coordinate});
    }
    ```
</details>

<details>
<summary><code>fromSliceWith</code> - Deserializes a value of type <code>T</code> from a string of JSON text using a <code>getty.De</code> value.</summary>

- **Synopsis**

    ```zig
    fn fromSliceWith(
        allocator: ?*std.mem.Allocator,
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

    const Coordinate = struct { x: i32, y: i32, z: i32 };
    const string =
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    ;

    const Visitor = struct {
        pub usingnamespace getty.de.Visitor(
            @This(),
            Coordinate,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            visitSequence,
            undefined,
            undefined,
            undefined,
        );

        pub fn visitSequence(_: @This(), sequenceAccess: anytype) !Coordinate {
            var coordinate: Coordinate = undefined;

            inline for (std.meta.fields(Coordinate)) |field| {
                if (try sequenceAccess.nextElement(i32)) |elem| {
                    @field(coordinate, field.name) = elem;
                }
            }

            if ((try sequenceAccess.nextElement(i32)) != null) {
                return error.InvalidLength;
            }

            return coordinate;
        }
    };

    pub fn main() anyerror!void {
        var v = Visitor{};
        const visitor = v.visitor();

        var d = getty.de.SequenceDe(@TypeOf(visitor)){ .visitor = visitor };
        const de = d.de();

        const coordinate = try json.fromSliceWith(null, Coordinate, string, de);

        // Coordinate{ .x = 1, .y = 2, .z = 3 }
        std.debug.print("{any}\n", .{coordinate});
    }
    ```
</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
