const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "exe",
        .root_source_file = b.path("main.zig"),
        //.root_source_file = b.path("src/thread_pool.zig"),
        .target = b.host,
    });

    const zcsv = b.dependency("zcsv", .{
        .target = b.host,
    });
    exe.root_module.addImport("zcsv", zcsv.module("zcsv"));

    exe.linkSystemLibrary("flexiblas");
    exe.linkSystemLibrary("raylib");
    exe.linkLibC();

    b.installArtifact(exe);
}
