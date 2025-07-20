const std = @import("std");

var builder: *std.Build = undefined;

pub fn link_sdl(
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
) void {
    const sdl_dep = builder.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .preferred_linkage = linkage,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
        //.install_build_config_h = false,
    });
    mod.linkLibrary(sdl_dep.artifact("SDL3"));
}

pub fn link_zgui(
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const zgui_dep = builder.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3_gpu,
        .with_implot = true,
        .with_node_editor = true,
        .with_freetype = true,
    });
    mod.addImport("zgui", zgui_dep.module("root"));
    mod.linkLibrary(zgui_dep.artifact("imgui"));
}

pub fn link_tracy(
    mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const src = builder.dependency("tracy", .{}).path(".");
    const tracy_mod = builder.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    tracy_mod.addCMacro("TRACY_ENABLE", "");
    tracy_mod.addIncludePath(src.path(builder, "public"));
    tracy_mod.addCSourceFile(.{ .file = src.path(builder, "public/TracyClient.cpp") });

    if (target.result.os.tag == .windows) {
        tracy_mod.linkSystemLibrary("dbghelp", .{ .needed = true });
        tracy_mod.linkSystemLibrary("ws2_32", .{ .needed = true });
    }

    const tracy_lib = builder.addLibrary(.{
        .name = "tracy",
        .root_module = tracy_mod,
        .linkage = .static,
    });
    tracy_lib.installHeadersDirectory(src.path(builder, "public"), "", .{ .include_extensions = &.{".h"} });

    mod.linkLibrary(tracy_lib);
}

pub fn build(b: *std.Build) void {
    builder = b;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Linkage mode") orelse .static;

    const dep_optimize = b.option(std.builtin.OptimizeMode, "dep-optimize", "Dependency optimization mode") orelse .ReleaseFast;

    const enable_tracy = b.option(bool, "enable-tracy", "Enable tracy profiling (low overhead)") orelse false;
    const enable_tracy_callstack = b.option(bool, "enable-tracy-callstack", "Enforce callstack collection for tracy regions") orelse false;

    // Build Options

    const options = b.addOptions();
    options.addOption(bool, "enable_tracy", enable_tracy);
    options.addOption(bool, "enable_tracy_callstack", enable_tracy_callstack);

    // -- Module and Library -- //

    const mod = b.addModule("bloom", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build-opts", .module = options.createModule() }},
    });

    const lib = b.addLibrary(.{
        .name = "bloom",
        .root_module = mod,
        .linkage = linkage,
    });
    b.installArtifact(lib);

    // -- Dependencies -- //

    link_sdl(mod, target, dep_optimize, .static);
    link_zgui(mod, target, dep_optimize);
    if (enable_tracy) link_tracy(mod, target, dep_optimize);

    // -- Check -- //

    const check_step = b.step("check", "Check build");
    check_step.dependOn(&lib.step);

    // -- Tests -- //

    const tests = b.addTest(.{ .root_module = mod, .filters = b.args orelse &.{} });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
