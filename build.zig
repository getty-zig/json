const std = @import("std");

const package_name = "json";
const package_path = "src/json.zig";

const test_path = "tests/test.zig";

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies.
    const dep_opts = .{ .target = target, .optimize = optimize };

    const getty_module = b.dependency("getty", dep_opts).module("getty");
    const concepts_module = b.dependency("concepts", dep_opts).module("concepts");

    // Export Getty JSON as a module.
    const json_module = b.addModule(package_name, .{
        .source_file = .{ .path = package_path },
        .dependencies = &.{
            .{ .name = "getty", .module = getty_module },
            .{ .name = "concepts", .module = concepts_module },
        },
    });

    // Tests.
    {
        const test_all_step = b.step("test", "Run tests");
        const test_ser_step = b.step("test-ser", "Run serialization tests");
        const test_de_step = b.step("test-de", "Run deserialization tests");

        // Serialization tests.
        const t_ser = b.addTest(.{
            .name = "serialization test",
            .root_source_file = .{ .path = "tests/test.zig" },
            .target = target,
            .optimize = optimize,
            .filter = "encode",
        });

        t_ser.addModule("json", json_module);
        test_ser_step.dependOn(&b.addRunArtifact(t_ser).step);
        test_all_step.dependOn(test_ser_step);

        // Deserialization tests.
        const t_de = b.addTest(.{
            .name = "deserialization test",
            .root_source_file = .{ .path = "tests/test.zig" },
            .target = target,
            .optimize = optimize,
            .filter = "parse",
        });

        t_de.addModule("json", json_module);
        test_de_step.dependOn(&b.addRunArtifact(t_de).step);
        test_all_step.dependOn(test_de_step);
    }

    // Documentation.
    {
        const docs_step = b.step("docs", "Generate project documentation");

        // Remove cache.
        const cmd = b.addSystemCommand(&[_][]const u8{
            "rm",
            "-rf",
            "zig-cache",
        });

        const clean_step = b.step("clean", "Remove project artifacts");

        clean_step.dependOn(&cmd.step);
        docs_step.dependOn(clean_step);

        // Build and emit documentation.
        const docs_obj = b.addObject(.{
            .name = "docs",
            .root_source_file = .{ .path = package_path },
            .target = target,
            .optimize = optimize,
        });

        docs_obj.emit_docs = .emit;
        docs_obj.addModule("getty", getty_module);
        docs_obj.addModule("concepts", concepts_module);

        docs_step.dependOn(&docs_obj.step);
    }
}
