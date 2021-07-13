<h1 align="center">JSON</h1>

<p align="center">
  <a alt="Version" href="https://github.com/getty-zig/json/releases/latest"><img src="https://img.shields.io/badge/version-N/A-e2725b.svg"></a>
  <a alt="Zig" href="https://ziglang.org/download"><img src="https://img.shields.io/badge/zig-master-fd9930.svg"></a>
  <a alt="Build" href="https://github.com/getty-zig/json/actions"><img src="https://github.com/getty-zig/getty/actions/workflows/ci.yml/badge.svg"></a>
  <a alt="License" href="https://github.com/getty-zig/json/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-2598c9"></a>
</p>

<img src="https://github.com/getty-zig/logo/blob/main/getty-solid.svg" alt="Getty" align="right" width="340px" height="370px">

The Getty JSON library provides serialization and deserialization capabilities for the ubiquitous JSON data format.

Whether you are working with JSON data as text, an untyped/loosely-typed representation, or a strongly-typed representation, Getty JSON provides a safe, efficient, and flexible way for converting data between them.

Note that Getty JSON does not _parse_ JSON data, it only serializes and deserializes it. For parsing JSON data, Getty JSON makes use of the JSON module provided in Zig's standard library.

Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo Foo 

```zig
const std = @import("std");
const json = @import("getty_json");

const Point = struct {
    x: i32,
    y: i32,
};

pub fn main() anyerror!void {
    var point = Point{ .x = 1, .y = 2 };

    // Convert Point to JSON string
    var serialized = try json.toString(std.heap.page_allocator, point);
    defer std.heap.page_allocator.free(serialized);

    // Convert JSON string to Point
    var deserialized = try json.fromString(Point, serialized);

    // Print results
    std.debug.print("{s}\n", .{serialized});   // {"x":1,"y":2}
    std.debug.print("{s}\n", .{deserialized}); // Point{ .x = 1, .y = 2 }
}
```

### More: \[[API Reference](https://github.com/getty-zig/json/wiki/Api)\] \[[Wiki](https://github.com/getty-zig/json/wiki)\]
