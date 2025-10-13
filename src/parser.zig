const std = @import("std");

const Flags = enum { DELIM, HEADER, WIDTH, ROW_NUM };

pub const ArgParse = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    help: bool,
    delim: u8,
    header: bool,
    width: usize,
    row_nums: bool,

    pub fn init(allocator: std.mem.Allocator) !ArgParse {
        var flags = [_]bool{ false, false, false, false };

        //set to defaults
        var self: ArgParse = .{
            .allocator = allocator,
            .help = false,
            .delim = ',',
            .header = true,
            .width = 40,
            .row_nums = true,
            .path = undefined,
        };

        var args_iter = std.process.args();
        defer args_iter.deinit();
        _ = args_iter.skip();

        if (args_iter.next()) |arg| {
            if (is_equal("-h", arg) or is_equal("--help", arg)) {
                self.help = true;
                return self;
            }

            try self.parse_file(arg);
        } else {
            std.debug.print("Error: No file specified\n", .{});
            std.debug.print("Usage: csv-viewer [OPTIONS] <file>\n", .{});
            std.debug.print("Try 'csv-viewer --help' for more information.\n\n", .{});
            return error.NoFileGiven;
        }

        while (args_iter.next()) |arg| {
            try self.parse_args(arg, &flags, &args_iter);
        }

        return self;
    }

    fn checkDuplicate(flags: *[4]bool, flag: Flags, name: []const u8) !void {
        const idx = @intFromEnum(flag);
        if (flags[idx]) {
            std.debug.print("Error: Flag '{s}' used multiple times\n", .{name});
            return error.DuplicateFlag;
        }
        flags[idx] = true;
    }

    fn is_equal(str: []const u8, arg: [:0]const u8) bool {
        return std.mem.eql(u8, str, arg);
    }

    fn parse_width(self: *ArgParse, args: *std.process.ArgIterator) !void {
        if (args.next()) |arg| {
            self.width = std.fmt.parseUnsigned(usize, arg, 10) catch |err| {
                std.debug.print("Error: Invalid number for --max-width: '{s}'\n", .{arg});
                return err;
            };

            if (self.width < 5) {
                std.debug.print("Error: Width must be at least 5\n", .{});
                return error.InvalidWidth;
            }
        } else {
            std.debug.print("Error: --max-width requires a number\n", .{});
            return error.MissingArgument;
        }
    }

    fn parse_delim(self: *ArgParse, args: *std.process.ArgIterator) !void {
        if (args.next()) |arg| {
            if (arg.len != 1) {
                std.debug.print("Error: Delimiter must be a single character, got: '{s}'\n", .{arg});
                return error.InvalidDelimiter;
            }
            self.delim = arg[0];
        } else {
            std.debug.print("Error: --delim requires a character\n", .{});
            return error.MissingArgument;
        }
    }

    fn parse_args(self: *ArgParse, arg: [:0]const u8, flags: *[4]bool, args: *std.process.ArgIterator) !void {
        if (is_equal("-d", arg) or is_equal("--delim", arg)) {
            try checkDuplicate(flags, Flags.DELIM, arg);
            try self.parse_delim(args);
        } else if (is_equal("-H", arg) or is_equal("--no-header", arg)) {
            try checkDuplicate(flags, Flags.HEADER, arg);
            self.header = false;
        } else if (is_equal("-m", arg) or is_equal("--max-width", arg)) {
            try checkDuplicate(flags, Flags.WIDTH, arg);
            try self.parse_width(args);
        } else if (is_equal("-n", arg) or is_equal("--no-row-numbers", arg)) {
            try checkDuplicate(flags, Flags.ROW_NUM, arg);
            self.row_nums = false;
        } else {
            std.debug.print("Error: Unknown option '{s}'\n", .{arg});
            std.debug.print("Try 'csv-viewer --help' for more information.\n", .{});
            return error.InvalidArgument;
        }
    }

    fn parse_file(self: *ArgParse, arg: [:0]const u8) !void {
        std.fs.cwd().access(arg, .{}) catch |e| switch (e) {
            error.FileNotFound => {
                std.debug.print("Error: File '{s}' does not exist\n", .{arg});
                return error.FileNotFound;
            },
            else => {
                std.debug.print("Error: Cannot access file '{s}': {any}\n", .{ arg, e });
                return e;
            },
        };

        self.path = try self.allocator.dupe(u8, arg);
    }

    pub fn deinit(self: *ArgParse) void {
        self.allocator.free(self.path);
    }

    pub fn printHelp() void {
        std.debug.print(
            \\CSV Viewer - Terminal CSV file viewer with search
            \\
            \\Usage: csv-viewer <file> [OPTIONS]
            \\
            \\(To use -h or --help it must be the first flag passed)
            \\
            \\OPTIONS:
            \\  -h, --help              Show this help message
            \\  -d, --delim <char>      Delimiter character (default: ',')
            \\  -H, --no-header         Treat first row as data, not header
            \\  -m, --max-width <n>     Maximum column width (default: 40)
            \\  -n, --no-row-numbers    Hide row number column
            \\
            \\NAVIGATION:
            \\  ↑/↓         Move up/down one row
            \\  ←/→         Switch column pages
            \\  Page Up/Dn  Move up/down one page
            \\  Home/End    First/last column page
            \\  g/G         Jump to first/last row
            \\  /           Start search
            \\  n/N         Next/previous match
            \\  q           Quit
            \\
            \\Examples:
            \\  csv-viewer data.csv
            \\  csv-viewer -d '|' pipe-separated.txt
            \\  csv-viewer -d '\t' data.tsv
            \\  csv-viewer --no-header -m 60 raw.csv
            \\
        , .{});
    }

    pub fn print(self: *const ArgParse) void {
        std.debug.print("Path: {s}\n", .{self.path});
        std.debug.print("Help: {any}\n", .{self.help});
        std.debug.print("Delim: '{c}' (ASCII {d})\n", .{ self.delim, self.delim });
        std.debug.print("Header: {any}\n", .{self.header});
        std.debug.print("Width: {d}\n", .{self.width});
        std.debug.print("Row Numbers: {any}\n", .{self.row_nums});
    }
};
