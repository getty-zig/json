<br/>

<p align="center">
  <img alt="Getty" src="https://github.com/getty-zig/logo/blob/main/getty-solid.svg" width="410px">
  <br/>
  <br/>
  <a href="https://github.com/getty-zig/json/releases/latest"><img alt="Version" src="https://img.shields.io/github/v/release/getty-zig/json?include_prereleases&label=Version"></a>
  <a href="https://ziglang.org/download"><img alt="Zig" src="https://img.shields.io/badge/Zig-master-fd9930.svg"></a>
  <a href="https://getty-zig.github.io/json"><img alt="API Reference" src="https://img.shields.io/badge/API-Reference-7a73ff.svg"></a>
  <a href="https://github.com/getty-zig/json/actions/workflows/test.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/getty-zig/json/test.yml?branch=main&label=Build" /></a>
  <a href="https://github.com/getty-zig/json/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-blue"></a>
</p>

## Overview

_Getty JSON_ is a (de)serialization library for the JSON data format.

## Installation

1. Declare Getty JSON as a dependency (replace `<COMMIT>` with an actual commit SHA):

    ```console
    zig fetch --save git+https://github.com/getty-zig/json.git#<COMMIT>
    ```

2. Expose Getty JSON as a module in `build.zig`:

    ```zig
    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const opts = .{ .target = target, .optimize = optimize };   // 👈
        const json_mod = b.dependency("json", opts).module("json"); // 👈

        const exe = b.addExecutable(.{
            .name = "my-project",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("json", json_mod); // 👈

        // ...
    }
    ```
