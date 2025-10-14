const std = @import("std");

pub const String = struct {
    const CAP = 256;
    len: u16,
    data: [CAP]u8,

    pub fn init() String {
        return String{ .len = 0, .data = undefined };
    }
    pub fn append(self: *String, char: u8) bool {
        if (self.len == String.CAP)
            return false;
        self.data[self.len] = char;
        self.len += 1;
        return true;
    }
    pub fn pop(self: *String) ?u8 {
        if (self.len == 0) {
            return null;
        }

        self.len -= 1;
        return self.data[self.len];
    }

    pub fn clear(self: *String) void {
        self.len = 0;
    }

    //just return an empty slice if 0
    pub fn get_slice(self: *String) []const u8 {
        return self.data[0..self.len];
    }
};
