const std = @import("std");

pub const TermSize = struct {
    rows: usize,
    cols: usize,

    pub fn init() !TermSize {
        var winsize: std.posix.winsize = undefined;

        const result = std.posix.system.ioctl(std.fs.File.stdout().handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));

        if (std.posix.errno(result) != .SUCCESS) {
            return error.CannotGetTerminalSize;
        }

        return TermSize{
            .rows = winsize.row,
            .cols = winsize.col,
        };
    }
};
