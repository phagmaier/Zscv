const std = @import("std");

pub const TermWriter = struct {
    buff: [4096]u8, // Increased buffer size
    stdout_writer: @TypeOf(std.fs.File.stdout().writer(undefined)),
    stdout: *std.Io.Writer,
    row: usize,
    col: usize,

    pub fn init(self: *TermWriter) void {
        self.* = .{
            .buff = undefined,
            .stdout_writer = undefined,
            .stdout = undefined,
            .row = 1,
            .col = 1,
        };
        self.stdout_writer = std.fs.File.stdout().writer(&self.buff);
        self.stdout = &self.stdout_writer.interface;
    }

    /// Clear the entire screen
    pub fn clear(self: *TermWriter) !void {
        try self.stdout.print("\x1b[2J", .{});
        try self.stdout.print("\x1b[H", .{});
        try self.stdout.flush();
        self.row = 1;
        self.col = 1;
    }

    /// Move cursor to specific position
    pub fn moveTo(self: *TermWriter, row: usize, col: usize) !void {
        try self.stdout.print("\x1b[{d};{d}H", .{ row, col });
        self.row = row;
        self.col = col;
    }

    /// Print to stdout
    pub fn write(self: *TermWriter, str: []const u8) !void {
        try self.stdout.print("{s}", .{str});
        self.col += str.len;
    }

    /// Write at a specific row and col
    pub fn writeAt(self: *TermWriter, row: usize, col: usize, str: []const u8) !void {
        try self.moveTo(row, col);
        try self.write(str);
    }

    /// Printing with format and args
    pub fn print(self: *TermWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout.print(fmt, args);
    }

    /// Print formatted text at specific position
    pub fn printAt(self: *TermWriter, row: usize, col: usize, comptime fmt: []const u8, args: anytype) !void {
        try self.moveTo(row, col);
        try self.print(fmt, args);
    }

    /// Flush buffer to screen
    pub fn flush(self: *TermWriter) !void {
        try self.stdout.flush();
    }

    /// Hide cursor
    pub fn hideCursor(self: *TermWriter) !void {
        try self.stdout.print("\x1b[?25l", .{});
        try self.stdout.flush();
    }

    /// Show cursor
    pub fn showCursor(self: *TermWriter) !void {
        try self.stdout.print("\x1b[?25h", .{});
        try self.stdout.flush();
    }

    /// Set text color (0-255 for 256-color mode)
    pub fn setColor(self: *TermWriter, fg: u8) !void {
        try self.stdout.print("\x1b[38;5;{d}m", .{fg});
    }

    /// Set background color (0-255 for 256-color mode)
    pub fn setBgColor(self: *TermWriter, bg: u8) !void {
        try self.stdout.print("\x1b[48;5;{d}m", .{bg});
    }

    /// Reset all formatting
    pub fn resetStyle(self: *TermWriter) !void {
        try self.stdout.print("\x1b[0m", .{});
    }

    /// Set bold text
    pub fn setBold(self: *TermWriter) !void {
        try self.stdout.print("\x1b[1m", .{});
    }

    /// Clear a specific line
    pub fn clearLine(self: *TermWriter, row: usize) !void {
        try self.moveTo(row, 1);
        try self.stdout.print("\x1b[2K", .{});
    }

    /// Save cursor position
    pub fn saveCursor(self: *TermWriter) !void {
        try self.stdout.print("\x1b[s", .{});
    }

    /// Restore cursor position
    pub fn restoreCursor(self: *TermWriter) !void {
        try self.stdout.print("\x1b[u", .{});
    }
};
