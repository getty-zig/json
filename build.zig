const std = @import("std");
const pkgs = @import("deps.zig").pkgs;

const Builder = std.build.Builder;

const package_name = "getty_json";
const package_path = "src/lib.zig";

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    // Tests
    const step = b.step("test", "Run library tests");
    const t = b.addTest("src/lib.zig");

    t.setBuildMode(mode);
    t.setTarget(target);
    t.addPackagePath(package_name, package_path);
    pkgs.addAllTo(t);
    step.dependOn(&t.step);

    // Library
    const lib = b.addStaticLibrary(package_name, package_path);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    pkgs.addAllTo(lib);
    lib.install();
}
