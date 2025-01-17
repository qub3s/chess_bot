const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.host;
    const optimize = b.standardOptimizeOption(.{});

    // START building simd
    const simd = b.addStaticLibrary(.{
        .name = "simd",
        .target = target,
        .optimize = optimize,
    });
    simd.addCSourceFiles(.{ .files = &.{"c_src/simd/vm_mul.c"} });
    simd.addIncludePath(b.path("simd"));
    simd.linkLibC();
    simd.installHeader(b.path("c_src/simd/vm_mul.h"), "c_src/simd/vm_mul.h");

    b.installArtifact(simd);
    // END building simd

    const exe = b.addExecutable(.{
        .name = "exe",
        //.root_source_file = b.path("main.zig"),
        .root_source_file = b.path("src/nn.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(simd);
    exe.linkSystemLibrary("flexiblas");
    exe.linkSystemLibrary("raylib");

    exe.addIncludePath(b.path("c_src/simd/"));

    exe.linkLibC();

    b.installArtifact(exe);
}
