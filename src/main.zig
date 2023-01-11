const std = @import("std");
const Ast = std.zig.Ast;
const Node = Ast.Node;
const ScopeList = std.ArrayList(struct {
    kind: []const u8,
    scope: []const u8,
});

var ast: Ast = undefined;
var stack: ScopeList = undefined;
var writer: std.fs.File.Writer = undefined;
var filename: []const u8 = undefined;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} file.zig\n", .{args[0]});
        return;
    }

    filename = args[1];
    const source = try std.fs.cwd().readFileAllocOptions(
        allocator,
        filename,
        std.math.maxInt(usize),
        null,
        @alignOf(u8),
        0,
    );
    defer allocator.free(source);

    ast = try std.zig.parse(allocator, source);
    defer ast.deinit(allocator);

    stack = ScopeList.init(allocator);
    defer stack.deinit();

    writer = std.io.getStdOut().writer();
    try printTags(0); // print root node of Ast
}

fn printTags(index: Node.Index) !void {
    const tag = ast.nodes.items(.tag)[index];
    const main_token = ast.nodes.items(.main_token)[index];
    const data = ast.nodes.items(.data)[index];

    switch (tag) {
        .root => {
            // root ContainerMembers
            for (ast.rootDecls()) |member| {
                try printTags(member);
            }
        },

        .simple_var_decl => {
            const init_node_tag = ast.nodes.items(.tag)[data.rhs];
            const init_node_token = ast.nodes.items(.main_token)[data.rhs];
            const init_node_data = ast.nodes.items(.data)[data.rhs];

            switch (init_node_tag) {
                .container_decl_two,
                .container_decl_two_trailing,
                .container_decl,
                .container_decl_trailing,
                => {
                    // const a = `struct {}`, `union {}`, `enum {}` or `opaque {}`
                    try printLine(main_token + 1, ast.tokenSlice(init_node_token));

                    try stack.append(.{
                        .kind = ast.tokenSlice(init_node_token),
                        .scope = ast.tokenSlice(main_token + 1),
                    });
                    defer _ = stack.pop();

                    // print tags of their ContainerMembers
                    switch (init_node_tag) {
                        .container_decl_two,
                        .container_decl_two_trailing,
                        => {
                            if (init_node_data.lhs > 0) try printTags(init_node_data.lhs);
                            if (init_node_data.rhs > 0) try printTags(init_node_data.rhs);
                        },
                        .container_decl,
                        .container_decl_trailing,
                        => {
                            for (ast.extra_data[init_node_data.lhs..init_node_data.rhs]) |member| {
                                try printTags(member);
                            }
                        },
                        else => unreachable,
                    }
                },

                // `var` or `const`
                else => try printLine(main_token + 1, ast.tokenSlice(main_token)),
            }
        },

        .container_field_init => try printLine(main_token, "field"),

        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        .fn_decl,
        => try printLine(main_token + 1, "function"),

        .test_decl => try printLine(if (data.lhs > 0) data.lhs else main_token, "test"),

        else => |unknown_tag| std.log.debug(
            "unknown: \x1b[33m{s}\x1b[m",
            .{@tagName(unknown_tag)},
        ),
    }
}

fn printLine(tag: Ast.TokenIndex, kind: []const u8) !void {
    const loc = ast.tokenLocation(0, tag);
    try writer.print(
        "{s}\t{s}\t{};\"\t{s}\tline:{}\tcolumn:{}",
        .{
            ast.tokenSlice(tag),
            filename,
            loc.line + 1,
            kind,
            loc.line + 1,
            loc.column + 1,
        },
    );

    // write scopes
    if (stack.items.len > 0) {
        try writer.print("\t{s}:", .{stack.getLast().kind});

        try writer.print("{s}", .{stack.items[0].scope});
        for (stack.items[1..]) |scope| {
            try writer.print(".{s}", .{scope.scope});
        }
    }

    try writer.writeByte('\n');
}
