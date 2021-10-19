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

const allocator = std.testing.allocator;
const print = std.debug.print;

pub fn main() anyerror!void {
    // serialization
    const slice = try json.toSlice(allocator, [_]i32{ 1, 2, 3 });
    defer json.free(allocator, slice);

    // run-time deserialization
    var list = try json.fromSlice(allocator, std.ArrayList(i32), slice);
    defer json.free(allocator, list);

    // compile-time deserialization
    const array = comptime try json.fromSlice(null, [3]i32, "[1,2,3]");

    // results
    print("{s}\n", .{slice});        // [1,2,3]
    print("{any}\n", .{list.items}); // { 1, 2, 3 }
    print("{any}\n", .{array});      // { 1, 2, 3 }
}
```

## Overview

The Getty JSON library provides serialization and deserialization capabilities for the ubiquitous JSON data format.

Whether you are working with JSON data as text, an untyped/loosely-typed representation, or a strongly-typed representation, Getty JSON provides a safe, efficient, and flexible way for converting data between them.

Note that Getty JSON does not _parse_ JSON data, it only serializes and deserializes it. For parsing JSON data, Getty JSON makes use of the JSON module provided in Zig's standard library.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
