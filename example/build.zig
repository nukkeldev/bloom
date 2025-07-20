const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = mod,
    });
    b.installArtifact(exe);

    // ---

    const bloom_dep = b.dependency("bloom", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("bloom", bloom_dep.module("bloom"));

    // ---

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // ---

    const check_step = b.step("check", "Checks");
    check_step.dependOn(&exe.step);
}
