const std = @import("std");

const Scanner = @import("zig-wayland").Scanner;

const version = "0.1.0";

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("staging/ext-session-lock/ext-session-lock-v1.xml");
    scanner.addCustomProtocol(b.path("protocol/river-layout-v3.xml"));

    scanner.generate("wl_seat", 4);
    scanner.generate("wl_output", 4);

    scanner.generate("river_layout_manager_v3", 2);

    scanner.generate("xdg_wm_base", 3);
    scanner.generate("ext_session_lock_manager_v1", 1);

    const flags = b.createModule(.{ .root_source_file = b.path("common/flags.zig") });

    {
        const exe = b.addExecutable(.{
            .name = "tarn-dwindle",
            .root_source_file = b.path("src/dwindle.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addOptions("build_options", options);

        exe.root_module.addImport("flags", flags);
        exe.root_module.addImport("wayland", wayland);
        exe.linkLibC();
        exe.linkSystemLibrary("wayland-client");

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run-dwindle", "Run tarn-dwindle");
        run_step.dependOn(&run_cmd.step);
    }
}
