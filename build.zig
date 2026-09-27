const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        },
    });
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });
    const dll = b.addLibrary(.{
        .name = "setupapi",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    dll.root_module.linkSystemLibrary("kernel32", .{});
    dll.root_module.linkSystemLibrary("advapi32", .{});

    const gen_def = b.addExecutable(.{
        .name = "gen-def",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/gen_def.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = .Debug,
        }),
    });
    const run_gen_def = b.addRunArtifact(gen_def);
    run_gen_def.addFileArg(b.path("system-setupapi.dll"));
    dll.root_module.addObjectFile(run_gen_def.addOutputFileArg("setupapi.def"));

    b.installArtifact(dll);
}
