const std = @import("std");
const Table = std.ArrayList(std.ArrayList([]const u8));

pub const Csv = struct {
    const MAX_FILE_SIZE = 2_000_000;
    table: Table,
    headers: std.ArrayList([]const u8),
    col_max: std.ArrayList(usize),
    allocator: std.mem.Allocator,
    col_idx: usize,
    col_size: usize,
    idx: usize,
    data: []const u8,
    delimiter: u8,

    pub fn init(allocator: std.mem.Allocator, delimiter: u8) Csv {
        return Csv{
            .table = Table.empty,
            .headers = std.ArrayList([]const u8).empty,
            .col_max = std.ArrayList(usize).empty,
            .allocator = allocator,
            .col_idx = 0,
            .col_size = 0,
            .idx = 0,
            .data = undefined,
            .delimiter = delimiter,
        };
    }

    fn maybe_set_col_max(self: *Csv) !void {
        if (self.col_idx >= self.col_max.items.len) {
            try self.col_max.append(self.allocator, self.col_size);
        } else if (self.col_max.items[self.col_idx] < self.col_size) {
            self.col_max.items[self.col_idx] = self.col_size;
        }
    }
    pub fn deinit(self: *Csv) void {
        for (0..self.table.items.len) |i| {
            const row = &self.table.items[i];
            for (row.items) |cell| {
                self.allocator.free(cell);
            }
            row.deinit(self.allocator);
        }
        for (self.headers.items) |cell| {
            self.allocator.free(cell);
        }
        self.headers.deinit(self.allocator);
        self.table.deinit(self.allocator);
        //self.allocator.free(self.data);
        self.col_max.deinit(self.allocator);
    }

    pub fn read_csv(self: *Csv, path: []const u8) !void {
        errdefer {
            self.allocator.free(self.data);
        }
        var buffer: [1024]u8 = undefined;
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        const file_size = try file.getEndPos();
        if (file_size > MAX_FILE_SIZE) {
            return error.FileTooLarge;
        }

        var file_reader = file.reader(&buffer);
        const reader = &file_reader.interface;

        self.data = try reader.allocRemaining(self.allocator, std.Io.Limit.unlimited);
    }

    fn parse_quote(self: *Csv, col: *std.ArrayList(u8)) !void {
        self.idx += 1;

        while (self.idx < self.data.len) {
            const char = self.data[self.idx];

            if (char == '"') {
                if (self.idx + 1 < self.data.len and self.data[self.idx + 1] == '"') {
                    try col.append(self.allocator, '"');
                    self.idx += 2;
                    self.col_size += 1;
                } else {
                    self.idx += 1;
                    return;
                }
            }
            //to make display easier we are stripping newlines
            else if (char == '\n') {
                try col.append(self.allocator, ' ');
                self.col_size += 1;
            } else {
                try col.append(self.allocator, char);
                self.idx += 1;
                self.col_size += 1;
            }
        }

        return error.UnterminatedQuote;
    }

    fn skip_line_ending(self: *Csv) void {
        if (self.idx < self.data.len and self.data[self.idx] == '\r') {
            self.idx += 1;
        }
        if (self.idx < self.data.len and self.data[self.idx] == '\n') {
            self.idx += 1;
        }
    }

    fn parse_col(self: *Csv, row: *std.ArrayList([]const u8)) !bool {
        var col = std.ArrayList(u8).empty;
        defer col.deinit(self.allocator);

        while (self.idx < self.data.len) {
            const char = self.data[self.idx];

            if (char == '\n' or char == '\r') {
                if (col.items.len == 0) {
                    try col.append(self.allocator, ' ');
                }
                const col_copy = try self.allocator.dupe(u8, col.items);
                try row.append(self.allocator, col_copy);
                self.skip_line_ending();
                try self.maybe_set_col_max();
                self.col_size = 0; // ← ADD THIS
                self.col_idx = 0;
                return true;
            } else if (char == self.delimiter) {
                if (col.items.len == 0) {
                    try col.append(self.allocator, ' ');
                }
                const col_copy = try self.allocator.dupe(u8, col.items);
                try row.append(self.allocator, col_copy);
                self.idx += 1;
                try self.maybe_set_col_max();
                self.col_size = 0; // ← ADD THIS
                self.col_idx += 1;
                return false;
            } else if (char == '"') {
                try self.parse_quote(&col);
            } else {
                try col.append(self.allocator, char);
                self.idx += 1;
                self.col_size += 1;
            }
        }

        if (col.items.len > 0) {
            const col_copy = try self.allocator.dupe(u8, col.items);
            try row.append(self.allocator, col_copy);
        }
        return true;
    }

    fn parse_row(self: *Csv) !void {
        var row = std.ArrayList([]const u8).empty;
        errdefer {
            for (row.items) |cell| {
                self.allocator.free(cell);
                row.deinit(self.allocator);
            }
        }

        var done = false;
        while (self.idx < self.data.len and !done) {
            done = try self.parse_col(&row);
        }
        std.debug.assert(row.items.len > 0);
        try self.table.append(self.allocator, row);
    }

    fn parse_header(self: *Csv) !void {
        var done = false;
        while (self.idx < self.data.len and !done) {
            done = try self.parse_col(&self.headers);
        }
        std.debug.assert(self.headers.items.len > 0);
    }

    fn def_headers(self: *Csv) !void {
        const len = self.table.items.len;
        for (0..len) |size| {
            const header = try std.fmt.allocPrint(self.allocator, "Col: {d}", .{size});
            try self.headers.append(self.allocator, header);
        }
    }

    pub fn parse(self: *Csv, path: []const u8, dis_header: bool) !void {
        defer self.allocator.free(self.data);
        try self.read_csv(path);

        if (dis_header) {
            try self.parse_header();
        } else {
            try self.parse_row();
            try self.def_headers();
        }

        while (self.idx < self.data.len) {
            try self.parse_row();
        }
    }
};
