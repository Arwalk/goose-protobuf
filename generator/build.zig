const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const protobuf_mod = protobuf_dep.module("protobuf");

    // zig-protobuf exports only the `protobuf` module. Its descriptor.proto
    // and plugin.proto bindings import each other through `../`, which a
    // module rooted at either file may not do, so copy both into one tree
    // under a small root file and build the module from that.
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(
        protobuf_dep.path("bootstrapped-generator/google/protobuf.pb.zig"),
        "google/protobuf.pb.zig",
    );
    _ = wf.addCopyFile(
        protobuf_dep.path("bootstrapped-generator/google/protobuf/compiler.pb.zig"),
        "google/protobuf/compiler.pb.zig",
    );
    const pb_plugin_root = wf.add("pb_plugin.zig",
        \\pub const descriptor = @import("google/protobuf.pb.zig");
        \\pub const plugin = @import("google/protobuf/compiler.pb.zig");
        \\
    );
    const pb_plugin_mod = b.createModule(.{
        .root_source_file = pb_plugin_root,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protobuf", .module = protobuf_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "protoc-gen-goose",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "protobuf", .module = protobuf_mod },
                .{ .name = "pb_plugin", .module = pb_plugin_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "Run protoc-gen-goose").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    b.step("test", "Run generator unit tests").dependOn(&b.addRunArtifact(tests).step);
}
