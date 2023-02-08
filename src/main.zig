const std = @import("std");
const Ast = std.zig.Ast;
const Node = Ast.Node;
const ScopeList = std.ArrayList(struct {
    kind: []const u8,
    scope: []const u8,
});
const Error = std.os.WriteError || error{OutOfMemory};

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

    ast = try std.zig.Ast.parse(allocator, source, .zig);
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
            const init_node = data.rhs;
            const public = if (ast.fullVarDecl(index).?.visib_token) |_| true else false;

            if (isContainer(init_node)) {
                try printContainer(main_token + 1, init_node, public);
            } else {
                const init_node_tag = ast.nodes.items(.tag)[init_node];
                switch (init_node_tag) {
                    .error_set_decl,
                    .merge_error_sets,
                    => {
                        try printLine(.{
                            .tag = main_token + 1,
                            .kind = "error",
                            .public = public,
                        });
                    },

                    // `var` or `const`
                    else => {
                        try printLine(.{
                            .tag = main_token + 1,
                            .kind = ast.tokenSlice(main_token),
                            .public = public,
                        });
                    },
                }
            }
        },

        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        .fn_decl,
        => {
            var buf: [1]Node.Index = undefined;
            const full = ast.fullFnProto(&buf, index).?;
            const public = if (full.visib_token) |_| true else false;

            // a function may return a struct
            const container_node: ?Node.Index = blk: {
                const return_type_main_token = ast.nodes.items(.main_token)[full.ast.return_type];

                if (std.mem.eql(u8, ast.tokenSlice(return_type_main_token), "type")) {
                    const block_node = data.rhs;
                    const block_node_tag = ast.nodes.items(.tag)[block_node];
                    const block_node_data = ast.nodes.items(.data)[block_node];

                    const statements: []const Node.Index = switch (block_node_tag) {
                        .block_two,
                        .block_two_semicolon,
                        => &.{ block_node_data.lhs, block_node_data.rhs },

                        .block,
                        .block_semicolon,
                        => ast.extra_data[block_node_data.lhs..block_node_data.rhs],

                        else => unreachable,
                    };

                    for (statements) |statement| {
                        if (statement == 0) continue;

                        const statement_tag = ast.nodes.items(.tag)[statement];
                        if (statement_tag == .@"return") {
                            const statement_data = ast.nodes.items(.data)[statement];

                            if (isContainer(statement_data.lhs)) {
                                break :blk statement_data.lhs;
                            }
                        }
                    }
                }
                break :blk null;
            };

            if (container_node) |container| {
                try printContainer(main_token + 1, container, public);
            } else {
                try printLine(.{
                    .tag = main_token + 1,
                    .kind = "function",
                    .public = public,
                });
            }
        },

        .container_field_init => try printLine(.{
            .tag = main_token,
            .kind = "field",
        }),

        .test_decl => try printLine(.{
            .tag = if (data.lhs > 0) data.lhs else main_token,
            .kind = "test",
        }),

        else => |unknown_tag| std.log.debug(
            "unknown: \x1b[33m{s}\x1b[m",
            .{@tagName(unknown_tag)},
        ),
    }
}

fn isContainer(node: Node.Index) bool {
    const tag = ast.nodes.items(.tag)[node];
    return switch (tag) {
        .container_decl_two,
        .container_decl_two_trailing,
        .container_decl,
        .container_decl_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        .tagged_union,
        .tagged_union_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        => true,

        else => false,
    };
}

fn printContainer(tag: Ast.TokenIndex, container: Node.Index, public: bool) Error!void {
    const container_tag = ast.nodes.items(.tag)[container];
    const container_token = ast.nodes.items(.main_token)[container];
    const container_data = ast.nodes.items(.data)[container];

    // const A = `struct {}`, `union {}`, `enum {}` or `opaque {}`
    try printLine(.{
        .tag = tag,
        .kind = ast.tokenSlice(container_token),
        .public = public,
    });

    try stack.append(.{
        .kind = ast.tokenSlice(container_token),
        .scope = ast.tokenSlice(tag),
    });
    defer _ = stack.pop();

    // print tags of their ContainerMembers
    const container_members: []const Node.Index = switch (container_tag) {
        .container_decl_two,
        .container_decl_two_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        => &.{ container_data.lhs, container_data.rhs },

        .container_decl,
        .container_decl_trailing,
        .tagged_union,
        .tagged_union_trailing,
        => ast.extra_data[container_data.lhs..container_data.rhs],

        .container_decl_arg,
        .container_decl_arg_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        => blk: {
            const params = ast.extraData(container_data.rhs, Node.SubRange);
            break :blk ast.extra_data[params.start..params.end];
        },

        else => unreachable,
    };

    for (container_members) |member| {
        if (member == 0) continue;
        try printTags(member);
    }
}

fn printLine(info: struct {
    tag: Ast.TokenIndex,
    kind: []const u8,
    public: bool = false,
}) std.os.WriteError!void {
    const loc = ast.tokenLocation(0, info.tag);
    try writer.print(
        "{s}\t{s}\t{};\"\t{s}\tline:{}\tcolumn:{}",
        .{
            ast.tokenSlice(info.tag),
            filename,
            loc.line + 1,
            info.kind,
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

    if (info.public) {
        try writer.writeAll("\taccess:public");
    }

    try writer.writeByte('\n');
}
