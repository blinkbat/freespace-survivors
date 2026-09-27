const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize, .linux_display_backend = .X11 });
    const exe = artifact(b, dep, target, optimize, false);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run Freespace Survivors").dependOn(&run.step);
    const tests = artifact(b, dep, target, optimize, true);
    const test_run = b.addRunArtifact(tests);
    b.step("test", "Verify flight, combat, progression, and settings").dependOn(&test_run.step);
    const check = b.step("check", "Type check without linking");
    check.dependOn(&artifact(b, dep, target, optimize, false).step);
    check.dependOn(&artifact(b, dep, target, optimize, true).step);
}

fn artifact(b: *std.Build, dep: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, is_test: bool) *std.Build.Step.Compile {
    const module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    module.addImport("raylib", dep.module("raylib"));
    const out = if (is_test) b.addTest(.{ .root_module = module }) else b.addExecutable(.{ .name = "freespace-survivors", .root_module = module });
    out.linkLibrary(dep.artifact("raylib"));
    // Debug builds retain large bounded world/run temporaries; Windows defaults to 1 MiB.
    out.stack_size = 8 * 1024 * 1024;
    return out;
}
