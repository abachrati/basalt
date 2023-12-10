const std = @import("std");

pub fn build(b: *std.Build) !void {
    const exe = b.addExecutable(.{
        .name = "basalt",
        .root_source_file = .{ .path = "src/main.zig" },
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run basalt");
    const run_exe = b.addRunArtifact(exe);
    run_step.dependOn(&run_exe.step);

    const test_step = b.step("test", "Run unit tests");

    var dir = try std.fs.cwd().openIterableDir("src/", .{});
    var walk = try dir.walk(b.allocator);

    // Recursively walk the `src/` directory and add all `.zig` files to the test step
    while (try walk.next()) |file| {
        if (std.mem.eql(u8, file.path[file.path.len - 3 ..], "zig")) {
            const path = b.fmt("src/{s}", .{file.path});
            const unit_test = b.addTest(.{ .root_source_file = .{ .path = path } });
            const run_unit_test = b.addRunArtifact(unit_test);
            test_step.dependOn(&run_unit_test.step);
        }
    }

    walk.deinit();
    dir.close();
}
