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

1. Declare Getty JSON as a dependency in `build.zig.zon`:

    ```diff
    .{
        .name = "my-project",
        .version = "1.0.0",
        .paths = .{""},
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

4. Update `build.zig.zon` with Getty JSON's package hash value:

    ```diff
    .{
        .name = "my-project",
        .version = "1.0.0",
        .paths = .{""},
        .dependencies = .{
            .json = .{
                .url = "https://github.com/getty-zig/json/archive/<COMMIT>.tar.gz",
    +           .hash = "<HASH>",
            },
        },
    }
    ```
