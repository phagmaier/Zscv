const std = @import("std");
const TermWriter = @import("termWriter.zig").TermWriter;
const Csv = @import("csv.zig").Csv;
const TermSize = @import("termSize.zig").TermSize;
const SearchState = @import("search.zig").SearchState;

const BoxChars = struct {
    const horizontal = "─";
    const vertical = "│";
    const top_left = "┌";
    const top_right = "┐";
    const bottom_left = "└";
    const bottom_right = "┘";
    const cross = "┼";
    const t_down = "┬";
    const t_up = "┴";
    const t_right = "├";
    const t_left = "┤";
};

// Color constants for easy theming
const Colors = struct {
    const SELECTED_BG = 238;
    const SELECTED_FG = 231;
    const MATCH_BG = 58;
    const MATCH_FG = 231;
    const ALT_ROW_BG = 235;
    const ROW_WITH_MATCH_BG = 236;
    const STATUS_BG = 236;
    const STATUS_FG = 255;
};

pub const Display = struct {
    const COUNT_COL_SIZE: usize = 10;
    const MIN_COL_SIZE: usize = 10;
    const MIN_TERM_SIZE: usize = 65;

    allocator: std.mem.Allocator,
    csv: *Csv,
    stdout: *TermWriter,
    tSize: *TermSize,
    visible_rows: usize,
    col_pages: std.ArrayList(usize),
    col_page_idx: usize,
    row_page_idx: usize,
    selected_row: usize,
    maxCol: usize,
    show_count: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        csv: *Csv,
        stdout: *TermWriter,
        term_size: *TermSize,
        maxCol: usize,
        show_count: bool,
    ) !Display {
        const real_max_col = @min(term_size.cols, maxCol);
        var display = Display{
            .allocator = allocator,
            .csv = csv,
            .stdout = stdout,
            .tSize = term_size,
            .visible_rows = 0,
            .col_pages = std.ArrayList(usize).empty,
            .col_page_idx = 0,
            .row_page_idx = 0,
            .selected_row = 0,
            .maxCol = real_max_col,
            .show_count = show_count,
        };

        try display.calculateLayout();
        return display;
    }

    pub fn deinit(self: *Display) void {
        self.col_pages.deinit(self.allocator);
    }

    pub fn get_header_idxs(self: *Display) struct { usize, usize } {
        const start_idx = self.col_pages.items[self.col_page_idx];
        const end_idx = if (self.col_page_idx + 1 < self.col_pages.items.len)
            self.col_pages.items[self.col_page_idx + 1]
        else
            self.csv.headers.items.len;

        return .{ start_idx, end_idx };
    }

    fn calculateLayout(self: *Display) !void {
        const width = self.tSize.cols;
        if (width < Display.MIN_TERM_SIZE) {
            return error.TermTooSmall;
        }

        var total: usize = if (self.show_count)
            Display.COUNT_COL_SIZE + 1
        else
            0;

        try self.col_pages.append(self.allocator, 0);
        var count: usize = 0;

        for (self.csv.col_max.items) |size| {
            const col_width = @min(@max(size, Display.MIN_COL_SIZE), self.maxCol) + 3;
            if (total + col_width >= width) {
                try self.col_pages.append(self.allocator, count);
                total = if (self.show_count)
                    Display.COUNT_COL_SIZE + 1
                else
                    0;
            }
            total += col_width;
            count += 1;
        }

        self.visible_rows = self.tSize.rows - 6;
    }

    fn isSearchMatch(row_num: usize, col_idx: usize, search_state: *const SearchState) bool {
        if (!search_state.active or search_state.matches.items.len == 0) return false;

        for (search_state.matches.items) |match| {
            if (match.row == row_num and match.col == col_idx) return true;
        }
        return false;
    }

    fn rowHasSearchMatch(row_num: usize, search_state: *const SearchState) bool {
        if (!search_state.active or search_state.matches.items.len == 0) return false;

        for (search_state.matches.items) |match| {
            if (match.row == row_num) return true;
        }
        return false;
    }

    /// Render the top border line
    fn renderTopBorder(self: *Display, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.top_left);

        if (self.show_count) {
            for (0..Display.COUNT_COL_SIZE) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.t_down);
        }

        // Data columns
        for (col_widths, 0..) |width, i| {
            const col_width = @min(@max(width, Display.MIN_COL_SIZE), self.maxCol);
            for (0..col_width) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            if (i < col_widths.len - 1) {
                try self.stdout.write(BoxChars.t_down);
            }
        }

        try self.stdout.write(BoxChars.top_right);
        try self.stdout.write("\n");
        try self.stdout.flush();
    }

    /// Render the header row with column names
    fn renderHeaderRow(self: *Display, headers: []const []const u8, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.vertical);

        if (self.show_count) {
            try self.stdout.write(" Count    ");
            try self.stdout.write(BoxChars.vertical);
        }

        for (headers, col_widths) |header, width| {
            const col_width = @min(@max(width, Display.MIN_COL_SIZE), self.maxCol);
            const actual_width = col_width - 2;

            if (header.len > actual_width) {
                const truncate = actual_width - 3;
                try self.stdout.print(" {s}...", .{header[0..truncate]});
                for (0..(actual_width - truncate - 3)) |_| {
                    try self.stdout.write(" ");
                }
                try self.stdout.write(" ");
            } else {
                try self.stdout.print(" {s}", .{header});
                for (0..(actual_width - header.len)) |_| {
                    try self.stdout.write(" ");
                }
                try self.stdout.write(" ");
            }
            try self.stdout.write(BoxChars.vertical);
        }
        try self.stdout.write("\n");
        try self.stdout.flush();
    }

    /// Render the separator between header and data
    fn renderHeaderSeparator(self: *Display, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.t_right);

        if (self.show_count) {
            for (0..Display.COUNT_COL_SIZE) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.cross);
        }

        // Data columns
        for (col_widths, 0..) |width, i| {
            const col_width = @min(@max(width, Display.MIN_COL_SIZE), self.maxCol);
            for (0..col_width) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            if (i < col_widths.len - 1) {
                try self.stdout.write(BoxChars.cross);
            }
        }
        try self.stdout.write(BoxChars.t_left);
        try self.stdout.write("\n");
        try self.stdout.flush();
    }

    /// Render a single data row
    fn renderDataRow(
        self: *Display,
        row_num: usize,
        cells: []const []const u8,
        col_widths: []const usize,
        search_state: *const SearchState,
        col_start: usize,
    ) !void {
        const is_selected = (row_num == self.selected_row);
        const has_search_match = rowHasSearchMatch(row_num, search_state);

        // Apply row styling
        if (is_selected) {
            try self.stdout.setBgColor(Colors.SELECTED_BG);
            try self.stdout.setColor(Colors.SELECTED_FG);
        } else if (has_search_match) {
            try self.stdout.setBgColor(Colors.ROW_WITH_MATCH_BG);
        } else if (row_num % 2 == 1) {
            // Alternating row colors (every odd row)
            try self.stdout.setBgColor(Colors.ALT_ROW_BG);
        }

        try self.stdout.write(BoxChars.vertical);

        // Count column (conditional)
        if (self.show_count) {
            try self.stdout.print(" {d:<[1]} ", .{ row_num + 1, Display.COUNT_COL_SIZE - 2 });
            try self.stdout.write(BoxChars.vertical);
        }

        // Data cells
        for (cells, col_widths, 0..) |cell, width, col_idx| {
            const col_width = @min(@max(width, Display.MIN_COL_SIZE), self.maxCol);
            const actual_width = col_width - 2;

            // Check if this cell matches the search
            const is_match = isSearchMatch(row_num, col_start + col_idx, search_state);

            if (is_match) {
                try self.stdout.setBgColor(Colors.MATCH_BG);
                try self.stdout.setColor(Colors.MATCH_FG);
            }

            if (cell.len > actual_width) {
                const truncate_len = actual_width - 3;
                try self.stdout.print(" {s}...", .{cell[0..truncate_len]});
                const printed_len = truncate_len + 3;
                for (0..(actual_width - printed_len)) |_| {
                    try self.stdout.write(" ");
                }
                try self.stdout.write(" ");
            } else {
                try self.stdout.print(" {s}", .{cell});
                for (0..(actual_width - cell.len)) |_| {
                    try self.stdout.write(" ");
                }
                try self.stdout.write(" ");
            }

            if (is_match) {
                try self.stdout.resetStyle();
                // Reapply row background if needed
                if (is_selected) {
                    try self.stdout.setBgColor(Colors.SELECTED_BG);
                    try self.stdout.setColor(Colors.SELECTED_FG);
                } else if (has_search_match) {
                    try self.stdout.setBgColor(Colors.ROW_WITH_MATCH_BG);
                } else if (row_num % 2 == 1) {
                    try self.stdout.setBgColor(Colors.ALT_ROW_BG);
                }
            }

            try self.stdout.write(BoxChars.vertical);
        }

        try self.stdout.resetStyle();
        try self.stdout.write("\n");
        try self.stdout.flush();
    }

    /// Render the bottom border line
    fn renderBottomBorder(self: *Display, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.bottom_left);

        if (self.show_count) {
            for (0..Display.COUNT_COL_SIZE) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.t_up);
        }

        // Data columns
        for (col_widths, 0..) |width, i| {
            const col_width = @min(@max(width, Display.MIN_COL_SIZE), self.maxCol);
            for (0..col_width) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            if (i < col_widths.len - 1) {
                try self.stdout.write(BoxChars.t_up);
            }
        }

        try self.stdout.write(BoxChars.bottom_right);
        try self.stdout.write("\n");
        try self.stdout.flush();
    }

    /// Render status bar at bottom of screen
    fn renderStatusBar(self: *Display, search_state: *const SearchState, input_buffer: []const u8) !void {
        const total_rows = self.csv.table.items.len;
        const total_col_pages = self.col_pages.items.len;
        const current_row = self.selected_row + 1;
        const current_col_page = self.col_page_idx + 1;

        try self.stdout.moveTo(self.tSize.rows, 1);
        try self.stdout.setBgColor(Colors.STATUS_BG);
        try self.stdout.setColor(Colors.STATUS_FG);

        if (search_state.active and search_state.matches.items.len > 0) {
            try self.stdout.print("Row {d}/{d} | Col Page {d}/{d} | Search: \"{s}\" | Match {d}/{d} | ←→:cols ↑↓:rows n/N:next/prev /:search q:quit", .{
                current_row,
                total_rows,
                current_col_page,
                total_col_pages,
                input_buffer,
                search_state.current_match + 1,
                search_state.matches.items.len,
            });
        } else if (search_state.active) {
            try self.stdout.print("Row {d}/{d} | Col Page {d}/{d} | Search: \"{s}\" | No matches | ←→:cols ↑↓:rows n/N:next/prev /:search q:quit", .{
                current_row,
                total_rows,
                current_col_page,
                total_col_pages,
                input_buffer,
            });
        } else {
            try self.stdout.print("Row {d}/{d} | Col Page {d}/{d} | ←→:cols ↑↓:rows /:search q:quit", .{
                current_row,
                total_rows,
                current_col_page,
                total_col_pages,
            });
        }

        try self.stdout.print("\x1b[K", .{});
        try self.stdout.resetStyle();
        try self.stdout.flush();
    }

    /// Render search input line
    fn renderSearchInput(self: *Display, input_buffer: []const u8) !void {
        try self.stdout.moveTo(self.tSize.rows, 1);
        try self.stdout.setBgColor(Colors.STATUS_BG);
        try self.stdout.setColor(Colors.STATUS_FG);

        try self.stdout.print("/", .{});
        try self.stdout.write(input_buffer);
        try self.stdout.print("\x1b[K", .{});

        try self.stdout.resetStyle();
        try self.stdout.flush();
    }

    /// Main render function
    pub fn render(self: *Display, search_state: *const SearchState, input_buffer: []const u8) !void {
        try self.stdout.clear();
        try self.stdout.hideCursor();

        const col_start, const col_end = self.get_header_idxs();
        const col_widths = self.csv.col_max.items[col_start..col_end];
        const headers = self.csv.headers.items[col_start..col_end];

        // Draw the table structure
        try self.renderTopBorder(col_widths);
        try self.renderHeaderRow(headers, col_widths);
        try self.renderHeaderSeparator(col_widths);

        // Draw data rows
        const data = self.csv.table.items;
        const row_start = self.visible_rows * self.row_page_idx;
        const row_end = @min(row_start + self.visible_rows, data.len);

        for (data[row_start..row_end], row_start..) |row, row_num| {
            const cells = row.items[col_start..col_end];
            try self.renderDataRow(row_num, cells, col_widths, search_state, col_start);
        }

        try self.renderBottomBorder(col_widths);

        if (search_state.input_mode) {
            try self.renderSearchInput(input_buffer);
        } else {
            try self.renderStatusBar(search_state, input_buffer);
        }
    }
};
