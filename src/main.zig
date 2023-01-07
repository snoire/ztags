const std = @import("std");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args) |file| {
        const source = try std.fs.cwd().readFileAllocOptions(
            allocator,
            file,
            std.math.maxInt(usize),
            null,
            @alignOf(u8),
            0,
        );
        defer allocator.free(source);

        var tree = try std.zig.parse(allocator, source);
        defer tree.deinit(allocator);
    }
}
