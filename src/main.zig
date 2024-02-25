const std = @import("std");
const mem = std.mem;

const MAX_CONFIG_SIZE = 1024 * 1024;
const MAX_CSV_SIZE = 1024 * 1024;
const MAX_MENU_OUTPUT_SIZE = 1024;

const ParseOutput = struct {
    menu_input: []const u8,
    keys: [][]const u8,
    commands: [][]const u8,
};

fn parseCsv(
    content: []const u8,
    allocator: mem.Allocator,
) !ParseOutput {
    const line_count = blk: {
        var it = std.mem.splitScalar(u8, content, '\n');
        var count: usize = 0;
        while (it.next()) |_| {
            count += 1;
        }
        break :blk count;
    };

    var keys = try allocator.alloc([]const u8, line_count);
    var commands = try allocator.alloc([]const u8, line_count);
    var menu_input = try allocator.alloc(u8, content.len);
    var menu_input_pos: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');

    var i: usize = 0;
    while (lines.next()) |line| {
        var tokens = std.mem.splitScalar(u8, line, ';');
        if (tokens.next()) |key| {
            if (tokens.next()) |command| {
                keys[i] = key;
                commands[i] = command;
                i += 1;

                std.mem.copyForwards(u8, menu_input[menu_input_pos..], key);
                menu_input_pos += key.len;
                menu_input[menu_input_pos] = '\n';
                menu_input_pos += 1;
            }
        }
    }

    return ParseOutput{
        .menu_input = menu_input[0..menu_input_pos],
        .keys = keys[0..i],
        .commands = commands[0..i],
    };
}

fn runMenu(
    cmd: []const []const u8,
    allocator: mem.Allocator,
    menu_input: []const u8,
) !?[]const u8 {
    var child = std.process.Child.init(cmd, allocator);
    child.stdin_behavior = std.process.Child.StdIo.Pipe;
    child.stdout_behavior = std.process.Child.StdIo.Pipe;
    child.stderr_behavior = std.process.Child.StdIo.Inherit;
    try child.spawn();

    try child.stdin.?.writeAll(menu_input);
    child.stdin.?.close();
    child.stdin = null;

    const raw_output = try child.stdout.?.readToEndAlloc(allocator, MAX_MENU_OUTPUT_SIZE);
    const output = std.mem.trim(u8, raw_output, " \n\t");

    _ = try child.kill();

    if (output.len == 0) {
        return null;
    } else {
        return output;
    }
}

pub fn run(
    allocator: mem.Allocator,
    csv_path: []const u8,
    menu_cmd: []const []const u8,
    output_allocation: []u8,
) !?[]const u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const file = std.fs.openFileAbsolute(csv_path, .{}) catch |err| switch (err) {
        std.fs.File.OpenError.FileNotFound => {
            std.log.err("file not found {s}", .{csv_path});
            return null;
        },
        else => return err,
    };
    const content = try file.readToEndAlloc(arena.allocator(), MAX_CSV_SIZE);
    const parsed = try parseCsv(content, arena.allocator());

    const output = try runMenu(
        menu_cmd,
        arena.allocator(),
        parsed.menu_input,
    );

    if (output) |selected| {
        const maybe_index: ?usize = blk: {
            for (0.., parsed.keys) |i, key| {
                if (std.mem.eql(u8, key, selected)) {
                    break :blk i;
                }
            }
            break :blk null;
        };

        if (maybe_index) |index| {
            const command = parsed.commands[index];
            std.mem.copyForwards(u8, output_allocation, command);
            return output_allocation[0..command.len];
        } else {
            std.log.err("option doesn't exit: '{s}'", .{selected});
            return null;
        }
    } else {
        return null;
    }
}

const SiclError = error{
    HomeNotSet,
};

fn cmdToArgv(allocator: mem.Allocator, command: []const u8) !std.ArrayList([]const u8) {
    var output = std.ArrayList([]const u8).init(allocator);
    var iter = std.mem.splitScalar(u8, command, ' ');
    while (iter.next()) |el| {
        try output.append(el);
    }
    return output;
}

const SiclConfig = struct {
    menu_cmd: ?[]const u8,
    csv_path: ?[]const u8,

    fn default(allocator: mem.Allocator) !@This() {
        const home_dir = std.os.getenv("HOME") orelse return SiclError.HomeNotSet;
        const csv_path = try std.fmt.allocPrint(
            allocator,
            "{s}/.local/share/sicl.csv",
            .{home_dir},
        );

        return SiclConfig{
            .csv_path = csv_path,
            .menu_cmd = "bemenu",
        };
    }

    fn updateWithConfig(self: *@This(), allocator: mem.Allocator, path: []const u8) !void {
        var file = std.fs.openFileAbsolute(path, .{}) catch return;
        defer file.close();
        const content = try file.readToEndAlloc(allocator, MAX_CONFIG_SIZE);
        const options = try std.json.parseFromSlice(SiclConfig, allocator, content, std.json.ParseOptions{});

        self.menu_cmd = options.value.menu_cmd orelse self.menu_cmd;
        self.csv_path = options.value.csv_path orelse self.csv_path;
    }

    fn initWithConf(allocator: mem.Allocator) !@This() {
        var config = try SiclConfig.default(allocator);

        const home_dir = std.os.getenv("HOME") orelse return SiclError.HomeNotSet;
        const config_path = try std.fmt.allocPrint(
            allocator,
            "{s}/.config/sicl.json",
            .{home_dir},
        );
        try config.updateWithConfig(allocator, config_path);

        return config;
    }
};

fn show_help() !void {
    var stderr = std.io.getStdErr().writer();
    try stderr.print("USAGE: sicl [options]\n", .{});
    try stderr.print("OPTIONS: \n", .{});
    try stderr.print("\tadd <alias> <command>\n", .{});
    try stderr.print("\trm <alias>\n", .{});
    try stderr.print("\tedit - opens up the $EDITOR on the csv file\n", .{});
}

fn runMenuAndSelecion(allocator: mem.Allocator, config: SiclConfig) !void {
    var output_allocation = try allocator.alloc(u8, MAX_MENU_OUTPUT_SIZE);
    const menu_cmd = try cmdToArgv(allocator, config.menu_cmd.?);

    if (try run(allocator, config.csv_path.?, menu_cmd.items, output_allocation)) |command| {
        // we don't need that anymore
        menu_cmd.deinit();

        var run_args = try std.ArrayList([]const u8).initCapacity(allocator, 32);
        var iter = std.mem.splitScalar(u8, command, ' ');
        while (iter.next()) |el| {
            try run_args.append(el);
        }

        var child = std.process.Child.init(run_args.items, allocator);

        _ = try child.spawnAndWait();
    } else {
        std.log.info("no option selected", .{});
    }
}

fn addEntry(args: []const []const u8, config: SiclConfig) !void {
    if (args.len != 4) {
        try show_help();
        return;
    }

    const alias = args[2];
    const cmd = args[3];

    var csv = try std.fs.openFileAbsolute(
        config.csv_path.?,
        .{ .mode = std.fs.File.OpenMode.read_write },
    );
    try csv.seekFromEnd(0);

    var writer = csv.writer();
    try writer.print("{s};{s}\n", .{ alias, cmd });
}

fn removeEntry(allocator: mem.Allocator, args: []const []const u8, config: SiclConfig) !void {
    if (args.len != 3) {
        try show_help();
        return;
    }

    const alias = args[2];

    var csv = try std.fs.openFileAbsolute(
        config.csv_path.?,
        .{ .mode = std.fs.File.OpenMode.read_write },
    );
    const content = try csv.readToEndAlloc(allocator, MAX_CSV_SIZE);
    const parsed = try parseCsv(content, allocator);

    try csv.seekTo(0);
    var writer = csv.writer();

    for (0..parsed.keys.len) |i| {
        const key = parsed.keys[i];
        const command = parsed.commands[i];

        if (!std.mem.eql(u8, key, alias)) {
            try writer.print("{s};{s}\n", .{ key, command });
        }
    }
    try csv.setEndPos(try writer.context.getPos());
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const config = try SiclConfig.initWithConf(arena.allocator());

    const args = try std.process.argsAlloc(arena.allocator());
    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "add")) {
            try addEntry(args, config);
        } else if (std.mem.eql(u8, args[1], "rm")) {
            try removeEntry(arena.allocator(), args, config);
        } else if (std.mem.eql(u8, args[1], "edit")) {
            const editor = std.process.getEnvVarOwned(arena.allocator(), "EDITOR") catch "/usr/bin/nano";
            const argv = [_][]const u8{ editor, config.csv_path.? };
            var child = std.process.Child.init(&argv, arena.allocator());
            child.stdin_behavior = .Inherit;
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            _ = child.spawnAndWait() catch |e| {
                if (e == error.FileNotFound) {
                    std.log.err("'{s}' doesn't exist", .{editor});
                } else return e;
            };
        } else {
            try show_help();
        }
    } else {
        try runMenuAndSelecion(arena.allocator(), config);
    }
}
