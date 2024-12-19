const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "blas",
        .root_source_file = b.path("src/blas.zig"),
        .target = b.host,
    });

    exe.linkSystemLibrary("flexiblas");
    exe.linkLibC();

    b.installArtifact(exe);
}
