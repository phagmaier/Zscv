const std = @import("std");
const TermWriter = @import("termWriter.zig").TermWriter;
const Csv = @import("csv.zig").Csv;
const TermSize = @import("termSize.zig").TermSize;
const SearchState = @import("search.zig").SearchState;
const Mode = @import("mode.zig").Mode;

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
    const COUNT_COL_WIDTH: usize = 10;
    const MIN_COL_WIDTH: usize = 8;
    const MAX_COL_WIDTH: usize = 50;
    const CELL_PADDING: usize = 2;
    const MIN_TERM_WIDTH: usize = 40;
    const MARGIN_COLS: usize = 2; // Minimal margin - just 1 column on each side
    const STATUS_ROWS: usize = 2;

    allocator: std.mem.Allocator,
    csv: *Csv,
    stdout: *TermWriter,
    tSize: *TermSize,
    visible_rows: usize,
    col_pages: std.ArrayList(usize),
    col_widths: std.ArrayList(usize),
    col_page_idx: usize,
    row_page_idx: usize,
    selected_row: usize,
    show_count: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        csv: *Csv,
        stdout: *TermWriter,
        term_size: *TermSize,
        _: usize,
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

    fn getUsableWidth(self: *Display) usize {
        const term_width = self.tSize.cols;
        const margin = MARGIN_COLS;
        const base_width = if (term_width > margin) term_width - margin else term_width;
        const count_width = if (self.show_count) COUNT_COL_WIDTH + 1 else 0;
        return if (base_width > count_width) base_width - count_width else base_width;
    }

    fn getOptimalColumnWidth(content_max: usize) usize {
        const content_width = @min(@max(content_max, MIN_COL_WIDTH), MAX_COL_WIDTH);
        return content_width + CELL_PADDING;
    }

    fn calculateLayout(self: *Display) !void {
        const term_width = self.tSize.cols;
        if (term_width < MIN_TERM_WIDTH) {
            return error.TermTooSmall;
        }

        const usable_width = self.getUsableWidth();
        const num_cols = self.csv.col_max.items.len;

        var ideal_widths = try self.allocator.alloc(usize, num_cols);
        defer self.allocator.free(ideal_widths);

        var total_ideal: usize = 0;
        for (self.csv.col_max.items, 0..) |max_width, i| {
            ideal_widths[i] = getOptimalColumnWidth(max_width);
            total_ideal += ideal_widths[i];
        }

        const all_borders = num_cols + 1;
        const total_needed = total_ideal + all_borders;

        if (total_needed <= usable_width) {
            const extra_space = usable_width - total_needed;
            try self.distributeSinglePage(ideal_widths, extra_space);
        } else {
            try self.distributeMultiplePages(ideal_widths, usable_width);
        }

        const header_rows: usize = 4;
        self.visible_rows = if (self.tSize.rows > header_rows + STATUS_ROWS)
            self.tSize.rows - header_rows - STATUS_ROWS
        else
            1;
    }

    fn distributeSinglePage(self: *Display, ideal_widths: []const usize, extra_space: usize) !void {
        try self.col_pages.append(self.allocator, 0);

        if (extra_space == 0) {
            for (ideal_widths) |w| {
                try self.col_widths.append(self.allocator, w);
            }
            return;
        }

        const total_ideal = sumWidths(ideal_widths);
        var remaining = extra_space;

        for (ideal_widths, 0..) |ideal, i| {
            const is_last = (i == ideal_widths.len - 1);
            const extra = if (is_last)
                remaining
            else blk: {
                const prop = (ideal * extra_space) / total_ideal;
                remaining -= prop;
                break :blk prop;
            };

            try self.col_widths.append(self.allocator, ideal + extra);
        }
    }

    fn distributeMultiplePages(self: *Display, ideal_widths: []const usize, usable_width: usize) !void {
        try self.col_pages.append(self.allocator, 0);

        var page_cols = std.ArrayList(usize).empty;
        defer page_cols.deinit(self.allocator);

        var col_idx: usize = 0;

        while (col_idx < ideal_widths.len) {
            try page_cols.append(self.allocator, ideal_widths[col_idx]);

            const page_total = sumWidths(page_cols.items);
            const page_borders = page_cols.items.len + 1;
            const page_needed = page_total + page_borders;

            if (page_needed > usable_width and page_cols.items.len > 1) {
                _ = page_cols.pop();
                try self.finalizePageColumns(&page_cols, usable_width);
                try self.col_pages.append(self.allocator, col_idx);
                page_cols.clearRetainingCapacity();
            } else {
                col_idx += 1;
            }
        }

        if (page_cols.items.len > 0) {
            try self.finalizePageColumns(&page_cols, usable_width);
        }
    }

    fn finalizePageColumns(self: *Display, page_cols: *std.ArrayList(usize), usable_width: usize) !void {
        const page_total = sumWidths(page_cols.items);
        const page_borders = page_cols.items.len + 1;
        const page_needed = page_total + page_borders;

        if (page_needed < usable_width) {
            const extra = usable_width - page_needed;
            var remaining = extra;

            for (page_cols.items, 0..) |ideal, i| {
                const is_last = (i == page_cols.items.len - 1);
                const add = if (is_last)
                    remaining
                else blk: {
                    const prop = (ideal * extra) / page_total;
                    remaining -= prop;
                    break :blk prop;
                };

                try self.col_widths.append(self.allocator, ideal + add);
            }
        } else {
            for (page_cols.items) |w| {
                try self.col_widths.append(self.allocator, w);
            }
        }
    }

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

    fn renderTopBorder(self: *Display, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.top_left);

        if (self.show_count) {
            for (0..COUNT_COL_WIDTH) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.t_down);
        }

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

    fn renderHeaderSeparator(self: *Display, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.t_right);

        if (self.show_count) {
            for (0..COUNT_COL_WIDTH) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.cross);
        }

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

        if (is_selected) {
            try self.stdout.setBgColor(Colors.SELECTED_BG);
            try self.stdout.setColor(Colors.SELECTED_FG);
        } else if (has_search_match) {
            try self.stdout.setBgColor(Colors.ROW_WITH_MATCH_BG);
        } else if (row_num % 2 == 1) {
            try self.stdout.setBgColor(Colors.ALT_ROW_BG);
        }

        try self.stdout.write(BoxChars.vertical);

        if (self.show_count) {
            try self.stdout.print(" {d:<[1]} ", .{ row_num + 1, COUNT_COL_WIDTH - 2 });
            try self.stdout.write(BoxChars.vertical);
        }

        for (cells, col_widths, 0..) |cell, width, col_idx| {
            const content_width = width - CELL_PADDING;
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

    fn renderBottomBorder(self: *Display, col_widths: []const usize) !void {
        try self.stdout.write(BoxChars.bottom_left);

        if (self.show_count) {
            for (0..COUNT_COL_WIDTH) |_| {
                try self.stdout.write(BoxChars.horizontal);
            }
            try self.stdout.write(BoxChars.t_up);
        }

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

    fn renderSearchInput(self: *Display, input_buffer: []const u8) !void {
        try self.stdout.moveTo(self.tSize.rows, 1);
        try self.stdout.setBgColor(Colors.STATUS_BG);
        try self.stdout.setColor(Colors.STATUS_FG);

        //try self.stdout.print("/", .{});
        try self.stdout.write(input_buffer);
        try self.stdout.print("\x1b[K", .{});

        try self.stdout.resetStyle();
        try self.stdout.flush();
    }

    fn renderColonInput(self: *Display, input_buffer: []const u8) !void {
        try self.stdout.moveTo(self.tSize.rows, 1);
        try self.stdout.setBgColor(Colors.STATUS_BG);
        try self.stdout.setColor(Colors.STATUS_FG);

        // Show the colon input
        try self.stdout.write(input_buffer);
        try self.stdout.print("\x1b[K", .{});

        try self.stdout.resetStyle();
        try self.stdout.flush();
    }

    fn renderHelp(self: *Display) !void {
        const help_line_count = 20;
        const start_row = (self.tSize.rows - help_line_count) / 2;

        // Calculate center position for the help box
        const box_width: usize = 70;
        const start_col = if (self.tSize.cols > box_width) (self.tSize.cols - box_width) / 2 else 1;

        var current_row = start_row;

        // Draw semi-transparent background overlay effect
        try self.stdout.setBgColor(234);

        // Title
        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.setBgColor(24); // Deep blue
        try self.stdout.setColor(231); // Bright white
        try self.stdout.write(" ");
        for (0..box_width - 2) |_| try self.stdout.write(" ");
        try self.stdout.write(" ");
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("  ╔═══════════════════════════════════════════════════════════════╗  ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("  ║              📊 CSV Viewer - Quick Reference 📊              ║  ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("  ╚═══════════════════════════════════════════════════════════════╝  ", .{});
        current_row += 1;

        try self.stdout.resetStyle();
        try self.stdout.setBgColor(237);
        try self.stdout.setColor(231);

        // Navigation section
        current_row += 1;
        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.write("  ");
        try self.stdout.setColor(120); // Green for section headers
        try self.stdout.write("NAVIGATION");
        try self.stdout.setColor(231);
        for (0..box_width - 14) |_| try self.stdout.write(" ");
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    ↑/↓  or  k/j     Move up/down through rows                     ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    ←/→  or  h/l     Navigate between column pages                  ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    g / G             Jump to next/previous search match            ", .{});
        current_row += 1;

        // Search section
        current_row += 1;
        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.write("  ");
        try self.stdout.setColor(220); // Yellow for section headers
        try self.stdout.write("SEARCH");
        try self.stdout.setColor(231);
        for (0..box_width - 10) |_| try self.stdout.write(" ");
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    /                 Start search (highlights all matches)         ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    n / N             Jump to next/previous search match            ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    Escape            Clear search highlighting                     ", .{});
        current_row += 1;

        // Commands section
        current_row += 1;
        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.write("  ");
        try self.stdout.setColor(177); // Purple for section headers
        try self.stdout.write("COMMANDS");
        try self.stdout.setColor(231);
        for (0..box_width - 12) |_| try self.stdout.write(" ");
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    :                 Enter command mode                            ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    :<number>         Jump to specific row number                   ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    Escape            Exit command mode                             ", .{});
        current_row += 1;

        // General section
        current_row += 1;
        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.write("  ");
        try self.stdout.setColor(81); // Cyan for section headers
        try self.stdout.write("GENERAL");
        try self.stdout.setColor(231);
        for (0..box_width - 11) |_| try self.stdout.write(" ");
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    q                 Quit the viewer                               ", .{});
        current_row += 1;

        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.print("    ?                 Toggle this help screen                       ", .{});
        current_row += 1;

        // Footer
        current_row += 1;
        try self.stdout.moveTo(current_row, start_col);
        try self.stdout.setBgColor(24);
        try self.stdout.setColor(250);
        const footer = "Press any key to continue...";
        const padding = (box_width - footer.len) / 2;
        try self.stdout.write(" ");
        for (0..padding - 1) |_| try self.stdout.write(" ");
        try self.stdout.write(footer);
        for (0..padding - 1) |_| try self.stdout.write(" ");
        try self.stdout.write(" ");

        try self.stdout.resetStyle();
        try self.stdout.flush();
    }

    pub fn render(self: *Display, search_state: *const SearchState, input_buffer: []const u8, mode: Mode) !void {
        try self.stdout.clear();
        try self.stdout.hideCursor();

        const col_start, const col_end = self.get_header_idxs();
        const col_widths = self.col_widths.items[col_start..col_end];
        const headers = self.csv.headers.items[col_start..col_end];

        try self.renderTopBorder(col_widths);
        try self.renderHeaderRow(headers, col_widths);
        try self.renderHeaderSeparator(col_widths);

        const data = self.csv.table.items;
        const row_start = self.visible_rows * self.row_page_idx;
        const row_end = @min(row_start + self.visible_rows, data.len);

        for (data[row_start..row_end], row_start..) |row, row_num| {
            const cells = row.items[col_start..col_end];
            try self.renderDataRow(row_num, cells, col_widths, search_state, col_start);
        }

        try self.renderBottomBorder(col_widths);

        switch (mode) {
            .search => try self.renderSearchInput(input_buffer),
            .colon => try self.renderColonInput(input_buffer),
            .normal => try self.renderStatusBar(search_state, input_buffer),
            .help => try self.renderHelp(),
            else => try self.renderStatusBar(search_state, input_buffer),
        }
    }
};
