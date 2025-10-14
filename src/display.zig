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
    // Layout constants - clear and well-named
    const COUNT_COL_WIDTH: usize = 10; // Width of row number column
    const MIN_COL_WIDTH: usize = 8; // Minimum content width for a data column
    const MAX_COL_WIDTH: usize = 50; // Maximum width for any single column
    const CELL_PADDING: usize = 2; // Space inside cell (1 char each side)
    const MIN_TERM_WIDTH: usize = 40; // Minimum terminal width to render anything
    const MARGIN_PERCENT: usize = 4; // 2% on each side = 4% total
    const STATUS_ROWS: usize = 2; // Status bar + one blank line

    allocator: std.mem.Allocator,
    csv: *Csv,
    stdout: *TermWriter,
    tSize: *TermSize,
    visible_rows: usize,
    col_pages: std.ArrayList(usize), // Starting column index for each page
    col_widths: std.ArrayList(usize), // Actual display width for each column (includes padding)
    col_page_idx: usize,
    row_page_idx: usize,
    selected_row: usize,
    show_count: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        csv: *Csv,
        stdout: *TermWriter,
        term_size: *TermSize,
        _: usize, // maxCol - we'll calculate this smartly now
        show_count: bool,
    ) !Display {
        var display = Display{
            .allocator = allocator,
            .csv = csv,
            .stdout = stdout,
            .tSize = term_size,
            .visible_rows = 0,
            .col_pages = std.ArrayList(usize).empty,
            .col_widths = std.ArrayList(usize).empty,
            .col_page_idx = 0,
            .row_page_idx = 0,
            .selected_row = 0,
            .show_count = show_count,
        };

        try display.calculateLayout();
        return display;
    }

    pub fn deinit(self: *Display) void {
        self.col_pages.deinit(self.allocator);
        self.col_widths.deinit(self.allocator);
    }

    pub fn get_header_idxs(self: *Display) struct { usize, usize } {
        const start_idx = self.col_pages.items[self.col_page_idx];
        const end_idx = if (self.col_page_idx + 1 < self.col_pages.items.len)
            self.col_pages.items[self.col_page_idx + 1]
        else
            self.csv.headers.items.len;

        return .{ start_idx, end_idx };
    }

    /// Calculate the usable width for displaying the table
    fn getUsableWidth(self: *Display) usize {
        const term_width = self.tSize.cols;

        // Calculate margins (2% on each side)
        const margin = @max(1, (term_width * MARGIN_PERCENT) / 100);

        // Usable width = terminal - both margins
        const base_width = if (term_width > margin) term_width - margin else term_width;

        // Subtract row count column if shown
        const count_width = if (self.show_count) COUNT_COL_WIDTH + 1 else 0; // +1 for border

        return if (base_width > count_width) base_width - count_width else base_width;
    }

    /// Calculate optimal width for a single column based on its content
    fn getOptimalColumnWidth(content_max: usize) usize {
        // Content width clamped between MIN and MAX
        const content_width = @min(@max(content_max, MIN_COL_WIDTH), MAX_COL_WIDTH);
        // Add padding (space on each side of content)
        return content_width + CELL_PADDING;
    }

    /// Calculate how many borders we need for N columns
    fn getBorderWidth(num_cols: usize) usize {
        // Left border + (N-1) internal borders + right border = N+1 borders
        // But we already count the row number border in getUsableWidth if shown
        return num_cols + 1;
    }

    fn calculateLayout(self: *Display) !void {
        const term_width = self.tSize.cols;
        if (term_width < MIN_TERM_WIDTH) {
            return error.TermTooSmall;
        }

        const usable_width = self.getUsableWidth();
        const num_cols = self.csv.col_max.items.len;

        // First, calculate ideal width for each column
        var ideal_widths = try self.allocator.alloc(usize, num_cols);
        defer self.allocator.free(ideal_widths);

        var total_ideal: usize = 0;
        for (self.csv.col_max.items, 0..) |max_width, i| {
            ideal_widths[i] = getOptimalColumnWidth(max_width);
            total_ideal += ideal_widths[i];
        }

        // Calculate how much width borders will take for all columns
        const all_borders_width = getBorderWidth(num_cols);
        const total_needed = total_ideal + all_borders_width;

        // Case 1: All columns fit! Expand them proportionally to use available space
        if (total_needed <= usable_width) {
            const extra_space = usable_width - total_needed;
            try self.distributeSinglePage(ideal_widths, extra_space);
        }
        // Case 2: Need multiple pages - smart page breaks
        else {
            try self.distributeMultiplePages(ideal_widths, usable_width);
        }

        // Calculate visible rows (terminal height - header - borders - status)
        const header_rows: usize = 4; // top border + header + separator + partial bottom
        self.visible_rows = if (self.tSize.rows > header_rows + STATUS_ROWS)
            self.tSize.rows - header_rows - STATUS_ROWS
        else
            1;
    }

    /// Distribute columns when they all fit on one page - expand to fill space
    fn distributeSinglePage(self: *Display, ideal_widths: []const usize, extra_space: usize) !void {
        try self.col_pages.append(self.allocator, 0); // Single page starting at column 0

        const num_cols = ideal_widths.len;
        var remaining_space = extra_space;

        // Distribute extra space proportionally based on ideal widths
        for (ideal_widths, 0..) |ideal, i| {
            const proportion = if (i < num_cols - 1)
                (ideal * extra_space) / (sumWidths(ideal_widths))
            else
                remaining_space; // Give all remaining to last column

            const final_width = ideal + proportion;
            try self.col_widths.append(self.allocator, final_width);
            remaining_space -= proportion;
        }
    }

    /// Distribute columns across multiple pages - maximize columns per page
    fn distributeMultiplePages(self: *Display, ideal_widths: []const usize, usable_width: usize) !void {
        try self.col_pages.append(self.allocator, 0); // First page starts at 0

        var current_col: usize = 0;
        var current_width: usize = 0;

        while (current_col < ideal_widths.len) {
            const col_width = ideal_widths[current_col];
            const borders_so_far = getBorderWidth(current_col - self.col_pages.items[self.col_pages.items.len - 1] + 1);
            const needed = current_width + col_width + borders_so_far;

            if (needed > usable_width and current_col > self.col_pages.items[self.col_pages.items.len - 1]) {
                // Start new page
                try self.col_pages.append(self.allocator, current_col);
                current_width = 0;
            } else {
                // Add column to current page
                try self.col_widths.append(self.allocator, col_width);
                current_width += col_width;
                current_col += 1;
            }
        }
    }

    /// Sum all widths in an array
    fn sumWidths(widths: []const usize) usize {
        var sum: usize = 0;
        for (widths) |w| sum += w;
        return sum;
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
            for (0..COUNT_COL_WIDTH) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.t_down);
        }

        // Data columns
        for (col_widths, 0..) |width, i| {
            for (0..width) |_| {
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
            const content_width = width - CELL_PADDING;

            if (header.len > content_width) {
                const truncate = if (content_width > 3) content_width - 3 else 0;
                try self.stdout.print(" {s}...", .{header[0..truncate]});
                for (0..(content_width - truncate - 3)) |_| {
                    try self.stdout.write(" ");
                }
                try self.stdout.write(" ");
            } else {
                try self.stdout.print(" {s}", .{header});
                for (0..(content_width - header.len)) |_| {
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
            for (0..COUNT_COL_WIDTH) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.cross);
        }

        // Data columns
        for (col_widths, 0..) |width, i| {
            for (0..width) |_| {
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
            try self.stdout.setBgColor(Colors.ALT_ROW_BG);
        }

        try self.stdout.write(BoxChars.vertical);

        // Count column (conditional)
        if (self.show_count) {
            try self.stdout.print(" {d:<[1]} ", .{ row_num + 1, COUNT_COL_WIDTH - 2 });
            try self.stdout.write(BoxChars.vertical);
        }

        // Data cells
        for (cells, col_widths, 0..) |cell, width, col_idx| {
            const content_width = width - CELL_PADDING;

            // Check if this cell matches the search
            const is_match = isSearchMatch(row_num, col_start + col_idx, search_state);

            if (is_match) {
                try self.stdout.setBgColor(Colors.MATCH_BG);
                try self.stdout.setColor(Colors.MATCH_FG);
            }

            if (cell.len > content_width) {
                const truncate_len = if (content_width > 3) content_width - 3 else 0;
                try self.stdout.print(" {s}...", .{cell[0..truncate_len]});
                const printed_len = truncate_len + 3;
                for (0..(content_width - printed_len)) |_| {
                    try self.stdout.write(" ");
                }
                try self.stdout.write(" ");
            } else {
                try self.stdout.print(" {s}", .{cell});
                for (0..(content_width - cell.len)) |_| {
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
            for (0..COUNT_COL_WIDTH) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.t_up);
        }

        // Data columns
        for (col_widths, 0..) |width, i| {
            for (0..width) |_| {
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
        const col_widths = self.col_widths.items[col_start..col_end];
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
