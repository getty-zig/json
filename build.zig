const std = @import("std");
const pkgs = @import("deps.zig").pkgs;

const package_name = "json";
const package_path = "src/lib.zig";

const json_pkg = std.build.Pkg{
    .name = package_name,
    .source = .{ .path = package_path },
    .dependencies = &[_]std.build.Pkg{
        pkgs.concepts,
        pkgs.getty,
    },
};

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    // Tests
    const step = b.step("test", "Run library tests");
    const t = b.addTest("src/lib.zig");

    t.setBuildMode(mode);
    t.setTarget(target);
    pkgs.addAllTo(t);
    //t.addPackage(json_pkg);
    step.dependOn(&t.step);
}
