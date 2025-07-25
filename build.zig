const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zig-tree-sitter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lib.linkLibrary(core.artifact("tree-sitter"));

    b.installArtifact(lib);

    const module = b.addModule("tree-sitter", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.linkLibrary(lib);

    const docs = b.addObject(.{
        .name = "tree-sitter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install generated docs");
    docs_step.dependOn(&install_docs.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.linkLibrary(lib);

    const json_lib = b.addLibrary(.{
        .name = "tree-sitter-json-stipped",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    json_lib.addIncludePath(b.path("vendor/tree-sitter-json/src"));
    json_lib.addCSourceFile(.{
        .file = b.path("vendor/tree-sitter-json/src/parser.c"),
    });
    tests.linkLibrary(json_lib);

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
