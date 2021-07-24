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

## Quick Start

```zig
const std = @import("std");
const json = @import("json");

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

## Overview

The Getty JSON library provides serialization and deserialization capabilities for the ubiquitous JSON data format.

Whether you are working with JSON data as text, an untyped/loosely-typed representation, or a strongly-typed representation, Getty JSON provides a safe, efficient, and flexible way for converting data between them.

Note that Getty JSON does not _parse_ JSON data, it only serializes and deserializes it. For parsing JSON data, Getty JSON makes use of the JSON module provided in Zig's standard library.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
