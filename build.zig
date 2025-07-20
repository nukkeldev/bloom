const std = @import("std");

pub fn build(b: *std.Build) void {
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

    const mod = b.createModule(.{
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

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = dep_optimize,
        .preferred_linkage = .static,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
        //.install_build_config_h = false,
    });
    mod.linkLibrary(sdl_dep.artifact("SDL3"));

    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = dep_optimize,
        .backend = .sdl3_gpu,
        .with_implot = true,
        .with_node_editor = true,
        .with_freetype = true,
    });
    mod.addImport("zgui", zgui_dep.module("root"));
    mod.linkLibrary(zgui_dep.artifact("imgui"));

    if (enable_tracy) {
        const src = b.dependency("tracy", .{}).path(".");
        const tracy_mod = b.createModule(.{
            .target = target,
            .optimize = dep_optimize,
            .link_libcpp = true,
        });

        tracy_mod.addCMacro("TRACY_ENABLE", "");
        tracy_mod.addIncludePath(src.path(b, "public"));
        tracy_mod.addCSourceFile(.{ .file = src.path(b, "public/TracyClient.cpp") });

        if (target.result.os.tag == .windows) {
            tracy_mod.linkSystemLibrary("dbghelp", .{ .needed = true });
            tracy_mod.linkSystemLibrary("ws2_32", .{ .needed = true });
        }

        const tracy_lib = b.addLibrary(.{
            .name = "tracy",
            .root_module = tracy_mod,
            .linkage = .static,
        });
        tracy_lib.installHeadersDirectory(src.path(b, "public"), "", .{ .include_extensions = &.{".h"} });

        mod.linkLibrary(tracy_lib);
    }

    // -- Check -- //

    const check_step = b.step("check", "Check build");
    check_step.dependOn(&lib.step);

    // -- Tests -- //

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}
