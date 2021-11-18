const std = @import("std");

const package_name = "json";
const package_path = "src/lib.zig";

const packages = struct {
    const json = std.build.Pkg{
        .name = package_name,
        .path = .{ .path = package_path },
        .dependencies = &[_]std.build.Pkg{
            getty,
        },
    };

    const getty = std.build.Pkg{
        .name = "getty",
        .path = .{ .path = "deps/getty/src/lib.zig" },
    };
};

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    // Tests
    const step = b.step("test", "Run library tests");
    const t = b.addTest("src/lib.zig");

    t.setBuildMode(mode);
    t.setTarget(target);
    t.addPackage(packages.json);
    t.addPackage(packages.getty);
    step.dependOn(&t.step);

    // Library
    const lib = b.addStaticLibrary(package_name, package_path);
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();
}
