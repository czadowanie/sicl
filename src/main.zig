const std = @import("std");

fn parse(content: []const u8, out: *std.StringHashMap([]const u8)) !usize {
    var lines = std.mem.splitScalar(u8, content, '\n');
    var keys_len: usize = 0;
    while (lines.next()) |line| {
        std.log.info("line: '{s}'", .{line});
        var tokens = std.mem.splitScalar(u8, line, ';');
        if (tokens.next()) |key| {
            if (tokens.next()) |value| {
                try out.put(key, value);
                keys_len += key.len + 1;
            }
        }
    }

    return keys_len;
}

const cmd = "/home/nm/.local/bin/menuwrapper";
// const cmd = "fzf";

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const file = try std.fs.openFileAbsolute("/home/nm/.config/sicl.csv", .{});
    const content = try file.readToEndAlloc(arena.allocator(), 1024 * 1024);
    var map = std.StringHashMap([]const u8).init(arena.allocator());
    const keys_len = try parse(content, &map);
    var menu_input = try arena.allocator().alloc(u8, keys_len);

    {
        var pos: usize = 0;
        var iter = map.keyIterator();
        while (iter.next()) |key| {
            std.mem.copyForwards(u8, menu_input[pos..], key.*);
            pos += key.len;
            menu_input[pos] = '\n';
            pos += 1;
        }
    }

    const output = blk: {
        var child = std.process.Child.init(&.{cmd}, arena.allocator());
        child.stdin_behavior = std.process.Child.StdIo.Pipe;
        child.stdout_behavior = std.process.Child.StdIo.Pipe;
        child.stderr_behavior = std.process.Child.StdIo.Inherit;
        try child.spawn();

        std.log.info("spawned menu! pid: {d}", .{child.id});
        try child.stdin.?.writeAll(menu_input);
        child.stdin.?.close();
        child.stdin = null;

        std.log.info("wrote input into menu", .{});

        const raw_output = try child.stdout.?.readToEndAlloc(arena.allocator(), 1024);
        const output = std.mem.trim(u8, raw_output, " \n\t");

        _ = try child.kill();

        break :blk output;
    };

    std.log.info("menu exited", .{});
    std.log.info("output '{s}'", .{output});

    const option = map.get(output).?;

    std.log.info("running '{s}'", .{option});

    var run_args = std.ArrayList([]const u8).init(arena.allocator());
    {
        var iter = std.mem.splitScalar(u8, option, ' ');
        while (iter.next()) |el| {
            try run_args.append(el);
        }
    }

    var child = std.process.Child.init(run_args.items, arena.allocator());
    _ = try child.spawnAndWait();
}
