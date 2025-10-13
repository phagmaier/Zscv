const std = @import("std");
const posix = std.posix;

pub const Key = union(enum) {
    up,
    down,
    left,
    right,
    page_up,
    page_down,
    home,
    end,
    g,
    G,
    q,
    slash,
    n,
    N,
    escape,
    enter,
    backspace,
    char: u8,
    unknown,
};

pub const Input = struct {
    original_termios: posix.termios,

    pub fn init() !Input {
        const stdin = std.fs.File.stdin();

        const original = try posix.tcgetattr(stdin.handle);

        var raw = original;

        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;

        raw.cc[@intFromEnum(posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;

        try posix.tcsetattr(stdin.handle, .FLUSH, raw);

        return Input{
            .original_termios = original,
        };
    }

    pub fn deinit(self: *Input) void {
        const stdin = std.fs.File.stdin();
        posix.tcsetattr(stdin.handle, .FLUSH, self.original_termios) catch {};
    }

    pub fn readKey(self: *Input) !Key {
        _ = self;
        const stdin = std.fs.File.stdin();
        var buf: [6]u8 = undefined;

        const n = try stdin.read(&buf);

        if (n == 1) {
            const c = buf[0];
            return switch (c) {
                'q' => Key.q,
                'g' => Key.g,
                'G' => Key.G,
                'n' => Key.n,
                'N' => Key.N,
                '/' => Key.slash,
                0x1b => Key.escape, // ESC key
                '\r', '\n' => Key.enter,
                0x7f => Key.backspace, // Backspace
                else => {
                    // Check if it's a printable ASCII character
                    if (c >= 32 and c <= 126) {
                        return Key{ .char = c };
                    }
                    return Key.unknown;
                },
            };
        } else if (n == 3 and buf[0] == 0x1b and buf[1] == '[') {
            // Arrow keys: ESC [ A/B/C/D
            return switch (buf[2]) {
                'A' => Key.up,
                'B' => Key.down,
                'C' => Key.right,
                'D' => Key.left,
                else => Key.unknown,
            };
        } else if (n >= 4 and buf[0] == 0x1b and buf[1] == '[') {
            // Extended keys: ESC [ X ~
            if (buf[n - 1] == '~') {
                return switch (buf[2]) {
                    '5' => Key.page_up, // ESC [ 5 ~
                    '6' => Key.page_down, // ESC [ 6 ~
                    'H' => Key.home, // ESC [ H (some terminals)
                    'F' => Key.end, // ESC [ F (some terminals)
                    else => Key.unknown,
                };
            }
            // Some terminals use ESC [ 1 ~ for Home, ESC [ 4 ~ for End
            if (buf[2] == '1' and buf[3] == '~') return Key.home;
            if (buf[2] == '4' and buf[3] == '~') return Key.end;
        }

        return Key.unknown;
    }
};
