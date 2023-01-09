const std = @import("std");

const package_name = "json";
const package_path = "src/json.zig";

var cached_pkg: ?std.build.Pkg = null;

pub fn pkg(b: *std.build.Builder) std.build.Pkg {
    if (cached_pkg == null) {
        const dependencies = b.allocator.create([2]std.build.Pkg) catch unreachable;
        dependencies.* = .{
            .{
                .name = "getty",
                .source = .{ .path = libPath(b, "/libs/getty/src/getty.zig") },
                .dependencies = &[_]std.build.Pkg{},
            },
            .{
                .name = "concepts",
                .source = .{ .path = libPath(b, "/libs/concepts/src/lib.zig") },
                .dependencies = &[_]std.build.Pkg{},
            },
        };

        cached_pkg = .{
            .name = package_name,
            .source = .{ .path = libPath(b, "/src/json.zig") },
            .dependencies = dependencies,
        };
    }

    return cached_pkg.?;
}

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    tests(b, mode, target);
    docs(b);
    clean(b);
}

fn tests(b: *std.build.Builder, mode: std.builtin.Mode, target: std.zig.CrossTarget) void {
    const test_all_step = b.step("test", "Run tests");
    const test_ser_step = b.step("test-ser", "Run serialization tests");
    const test_de_step = b.step("test-de", "Run deserialization tests");

    // Configure tests.
    const t_ser = b.addTest("src/ser.zig");
    t_ser.setTarget(target);
    t_ser.setBuildMode(mode);
    for (pkg(b).dependencies.?) |d| t_ser.addPackage(d);

    const t_de = b.addTest("src/de.zig");
    t_de.setTarget(target);
    t_de.setBuildMode(mode);
    for (pkg(b).dependencies.?) |d| t_de.addPackage(d);

    // Configure module-level test steps.
    test_ser_step.dependOn(&t_ser.step);
    test_de_step.dependOn(&t_de.step);

    // Configure top-level test step.
    test_all_step.dependOn(test_ser_step);
    test_all_step.dependOn(test_de_step);
}

fn docs(b: *std.build.Builder) void {
    const cmd = b.addSystemCommand(&[_][]const u8{
        "zig",
        "build-obj",
        "-femit-docs",
        package_path,
    });

    const docs_step = b.step("docs", "Generate project documentation");
    docs_step.dependOn(&cmd.step);
}

fn clean(b: *std.build.Builder) void {
    const cmd = b.addSystemCommand(&[_][]const u8{
        "rm",
        "-rf",
        "zig-cache",
        "docs",
        "*.o",
        "gyro.lock",
        ".gyro",
    });

    const clean_step = b.step("clean", "Remove project artifacts");
    clean_step.dependOn(&cmd.step);
}

////////////////////////////////////////////////////////////////////////////////
// GitRepoStep (copied from https://github.com/marler8997/zig-build-repos)
////////////////////////////////////////////////////////////////////////////////

const GitRepoStep = struct {
    step: std.build.Step,
    builder: *std.build.Builder,
    url: []const u8,
    name: []const u8,
    branch: ?[]const u8 = null,
    sha: []const u8,
    path: []const u8,
    sha_check: ShaCheck = .warn,
    fetch_enabled: bool,

    pub const ShaCheck = enum {
        none,
        warn,
        err,

        pub fn reportFail(self: ShaCheck, comptime fmt: []const u8, args: anytype) void {
            switch (self) {
                .none => unreachable,
                .warn => std.log.warn(fmt, args),
                .err => {
                    std.log.err(fmt, args);
                    std.os.exit(0xff);
                },
            }
        }
    };

    var cached_default_fetch_option: ?bool = null;

    pub fn defaultFetchOption(b: *std.build.Builder) bool {
        if (cached_default_fetch_option) |_| {} else {
            cached_default_fetch_option = if (b.option(bool, "fetch", "automatically fetch network resources")) |o| o else false;
        }
        return cached_default_fetch_option.?;
    }

    pub fn create(b: *std.build.Builder, opt: struct {
        url: []const u8,
        branch: ?[]const u8 = null,
        sha: []const u8,
        path: ?[]const u8 = null,
        sha_check: ShaCheck = .warn,
        fetch_enabled: ?bool = null,
    }) *GitRepoStep {
        var result = b.allocator.create(GitRepoStep) catch @panic("memory");
        const name = std.fs.path.basename(opt.url);
        result.* = GitRepoStep{
            .step = std.build.Step.init(.custom, "clone a git repository", b.allocator, make),
            .builder = b,
            .url = opt.url,
            .name = name,
            .branch = opt.branch,
            .sha = opt.sha,
            .path = if (opt.path) |p| (b.allocator.dupe(u8, p) catch @panic("memory")) else (std.fs.path.resolve(b.allocator, &[_][]const u8{
                b.build_root,
                "lib",
                name,
            })) catch @panic("memory"),
            .sha_check = opt.sha_check,
            .fetch_enabled = if (opt.fetch_enabled) |fe| fe else defaultFetchOption(b),
        };
        return result;
    }

    fn hasDependency(step: *const std.build.Step, dep_candidate: *const std.build.Step) bool {
        for (step.dependencies.items) |dep| {
            if (dep == dep_candidate or hasDependency(dep, dep_candidate))
                return true;
        }
        return false;
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(GitRepoStep, "step", step);

        std.fs.accessAbsolute(self.path, .{}) catch {
            const branch_args = if (self.branch) |b| &[2][]const u8{ " -b ", b } else &[2][]const u8{ "", "" };
            if (!self.fetch_enabled) {
                std.debug.print("Error: git repository '{s}' does not exist\n", .{self.path});
                std.debug.print("       Use -Dfetch to download it automatically, or run the following to clone it:\n", .{});
                std.debug.print("       git clone {s}{s}{s} {s} && git -C {3s} checkout {s} -b fordep\n", .{
                    self.url,
                    branch_args[0],
                    branch_args[1],
                    self.path,
                    self.sha,
                });
                std.os.exit(1);
            }

            {
                var args = std.ArrayList([]const u8).init(self.builder.allocator);
                defer args.deinit();
                try args.append("git");
                try args.append("clone");
                try args.append(self.url);
                try args.append(self.path);
                if (self.branch) |branch| {
                    try args.append("-b");
                    try args.append(branch);
                }
                try run(self.builder, args.items);
            }
            try run(self.builder, &[_][]const u8{
                "git",
                "-C",
                self.path,
                "checkout",
                self.sha,
                "-b",
                "fordep",
            });
        };

        try self.checkSha();
    }

    fn checkSha(self: GitRepoStep) !void {
        if (self.sha_check == .none)
            return;

        const result: union(enum) { failed: anyerror, output: []const u8 } = blk: {
            const result = std.ChildProcess.exec(.{
                .allocator = self.builder.allocator,
                .argv = &[_][]const u8{
                    "git",
                    "-C",
                    self.path,
                    "rev-parse",
                    "HEAD",
                },
                .cwd = self.builder.build_root,
                .env_map = self.builder.env_map,
            }) catch |e| break :blk .{ .failed = e };
            try std.io.getStdErr().writer().writeAll(result.stderr);
            switch (result.term) {
                .Exited => |code| {
                    if (code == 0) break :blk .{ .output = result.stdout };
                    break :blk .{ .failed = error.GitProcessNonZeroExit };
                },
                .Signal => break :blk .{ .failed = error.GitProcessFailedWithSignal },
                .Stopped => break :blk .{ .failed = error.GitProcessWasStopped },
                .Unknown => break :blk .{ .failed = error.GitProcessFailed },
            }
        };
        switch (result) {
            .failed => |err| {
                return self.sha_check.reportFail("failed to retreive sha for repository '{s}': {s}", .{ self.name, @errorName(err) });
            },
            .output => |output| {
                if (!std.mem.eql(u8, std.mem.trimRight(u8, output, "\n\r"), self.sha)) {
                    return self.sha_check.reportFail("repository '{s}' sha does not match\nexpected: {s}\nactual  : {s}\n", .{ self.name, self.sha, output });
                }
            },
        }
    }

    fn run(builder: *std.build.Builder, argv: []const []const u8) !void {
        {
            var msg = std.ArrayList(u8).init(builder.allocator);
            defer msg.deinit();
            const writer = msg.writer();
            var prefix: []const u8 = "";
            for (argv) |arg| {
                try writer.print("{s}\"{s}\"", .{ prefix, arg });
                prefix = " ";
            }
            std.log.info("[RUN] {s}", .{msg.items});
        }

        var child = std.ChildProcess.init(argv, builder.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.cwd = builder.build_root;
        child.env_map = builder.env_map;

        try child.spawn();
        const result = try child.wait();
        switch (result) {
            .Exited => |code| if (code != 0) {
                std.log.err("git clone failed with exit code {}", .{code});
                std.os.exit(0xff);
            },
            else => {
                std.log.err("git clone failed with: {}", .{result});
                std.os.exit(0xff);
            },
        }
    }

    pub fn getPath(self: *const GitRepoStep, who_wants_to_know: *const std.build.Step) []const u8 {
        if (!hasDependency(who_wants_to_know, &self.step))
            @panic("a step called GitRepoStep.getPath but has not added it as a dependency");
        return self.path;
    }
};

const unresolved_dir = (struct {
    inline fn unresolvedDir() []const u8 {
        return comptime std.fs.path.dirname(@src().file) orelse ".";
    }
}).unresolvedDir();

fn thisDir(allocator: std.mem.Allocator) []const u8 {
    if (comptime unresolved_dir[0] == '/') {
        return unresolved_dir;
    }

    const cached_dir = &(struct {
        var cached_dir: ?[]const u8 = null;
    }).cached_dir;

    if (cached_dir.* == null) {
        cached_dir.* = std.fs.cwd().realpathAlloc(allocator, unresolved_dir) catch unreachable;
    }

    return cached_dir.*.?;
}

inline fn libPath(b: *std.build.Builder, comptime suffix: []const u8) []const u8 {
    return libPathAllocator(b.allocator, suffix);
}

inline fn libPathAllocator(allocator: std.mem.Allocator, comptime suffix: []const u8) []const u8 {
    return libPathInternal(allocator, suffix.len, suffix[0..suffix.len].*);
}

fn libPathInternal(allocator: std.mem.Allocator, comptime len: usize, comptime suffix: [len]u8) []const u8 {
    if (suffix[0] != '/') @compileError("suffix must be an absolute path");

    if (comptime unresolved_dir[0] == '/') {
        return unresolved_dir ++ @as([]const u8, &suffix);
    }

    const cached_dir = &(struct {
        var cached_dir: ?[]const u8 = null;
    }).cached_dir;

    if (cached_dir.* == null) {
        cached_dir.* = std.fs.path.resolve(allocator, &.{ thisDir(allocator), suffix[1..] }) catch unreachable;
    }

    return cached_dir.*.?;
}
