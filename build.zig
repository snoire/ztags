const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.build.Builder) void {
    // Check minimum zig version
    comptime {
        const current_zig = builtin.zig_version;
        const min_zig = std.SemanticVersion.parse("0.11.0-dev.1239+7a2d7ff62") catch unreachable;
        if (current_zig.order(min_zig) == .lt) {
            @compileError(std.fmt.comptimePrint(
                "Your Zig version v{} does not meet the minimum build requirement of v{}",
                .{ current_zig, min_zig },
            ));
        }
    }

    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const strip = b.option(bool, "strip", "Removes symbols and sections from file") orelse false;

    const exe = b.addExecutable("ztags", "src/main.zig");
    exe.override_dest_dir = .{ .custom = "./" };
    exe.strip = strip;
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.expected_exit_code = null;
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
