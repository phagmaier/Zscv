const std = @import("std");
const builtin = @import("builtin");
const zcsv = @import("Zcsv");
const Parser = zcsv.Parser;
const Csv = zcsv.Csv;
const TermSize = zcsv.TermSize;
const Display = zcsv.Display;
const Input = zcsv.Input;
const SearchState = zcsv.SearchState;
const TermWriter = zcsv.TermWriter;
const Key = zcsv.Key;
const SearchResult = zcsv.SearchResult;

const MAX_SEARCH_INPUT = 256;

/// Represents the result of handling a key press
const UpdateResult = struct {
    should_quit: bool = false,
    needs_render: bool = false,
};

/// Application state encapsulation
const AppState = struct {
    display: *Display,
    csv: *Csv,
    search_state: *SearchState,
    search_input: []u8,
    search_input_len: usize,

    fn init(
        display: *Display,
        csv: *Csv,
        search_state: *SearchState,
        search_buffer: []u8,
    ) AppState {
        return .{
            .display = display,
            .csv = csv,
            .search_state = search_state,
            .search_input = search_buffer,
            .search_input_len = 0,
        };
    }

    /// Handle a key press in search input mode
    fn handleSearchModeKey(self: *AppState, key: Key) !UpdateResult {
        switch (key) {
            .escape => {
                // Just exit input mode, don't clear results
                self.search_state.cancelInput();
                self.search_input_len = 0;
                return .{ .needs_render = true };
            },

            .enter => {
                self.search_state.setQuery(self.search_input[0..self.search_input_len]);
                try self.search_state.performSearch(self.csv);
                self.search_state.input_mode = false;

                if (self.search_state.matches.items.len > 0) {
                    try self.jumpToMatch(self.search_state.matches.items[0]);
                }
                return .{ .needs_render = true };
            },

            .backspace => {
                if (self.search_input_len > 0) {
                    self.search_input_len -= 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            // These special chars should be typed as regular characters in search mode
            .n => {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = 'n';
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },
            .N => {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = 'N';
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },
            .q => {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = 'q';
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },
            .g => {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = 'g';
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },
            .G => {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = 'G';
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },
            .slash => {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = '/';
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            .char => |c| {
                if (self.search_input_len < MAX_SEARCH_INPUT) {
                    self.search_input[self.search_input_len] = c;
                    self.search_input_len += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            else => return .{ .needs_render = false },
        }
    }

    fn handleNormalModeKey(self: *AppState, key: Key) !UpdateResult {
        switch (key) {
            .q => return .{ .should_quit = true },

            .escape => {
                if (self.search_state.active) {
                    self.search_state.clearSearch();
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            .slash => {
                self.search_state.startSearch();
                self.search_input_len = 0;
                return .{ .needs_render = true };
            },

            .n => {
                if (self.search_state.active and self.search_state.matches.items.len > 0) {
                    if (self.search_state.nextMatch()) |match| {
                        try self.jumpToMatch(match);
                        return .{ .needs_render = true };
                    }
                }
                return .{ .needs_render = false };
            },

            .N => {
                if (self.search_state.active and self.search_state.matches.items.len > 0) {
                    if (self.search_state.prevMatch()) |match| {
                        try self.jumpToMatch(match);
                        return .{ .needs_render = true };
                    }
                }
                return .{ .needs_render = false };
            },

            .right => {
                if (self.display.col_page_idx + 1 < self.display.col_pages.items.len) {
                    self.display.col_page_idx += 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            .left => {
                if (self.display.col_page_idx > 0) {
                    self.display.col_page_idx -= 1;
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            .down => {
                const max_row = self.csv.table.items.len - 1;
                if (self.display.selected_row < max_row) {
                    self.display.selected_row += 1;
                    const row_page = self.display.selected_row / self.display.visible_rows;
                    if (row_page != self.display.row_page_idx) {
                        self.display.row_page_idx = row_page;
                    }
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            .up => {
                if (self.display.selected_row > 0) {
                    self.display.selected_row -= 1;
                    const row_page = self.display.selected_row / self.display.visible_rows;
                    if (row_page != self.display.row_page_idx) {
                        self.display.row_page_idx = row_page;
                    }
                    return .{ .needs_render = true };
                }
                return .{ .needs_render = false };
            },

            .page_down => {
                const max_row = self.csv.table.items.len - 1;
                const old_row = self.display.selected_row;
                self.display.selected_row = @min(self.display.selected_row + self.display.visible_rows, max_row);
                self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;
                return .{ .needs_render = old_row != self.display.selected_row };
            },

            .page_up => {
                const old_row = self.display.selected_row;
                if (self.display.selected_row >= self.display.visible_rows) {
                    self.display.selected_row -= self.display.visible_rows;
                } else {
                    self.display.selected_row = 0;
                }
                self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;
                return .{ .needs_render = old_row != self.display.selected_row };
            },

            .G => {
                const old_row = self.display.selected_row;
                self.display.selected_row = self.csv.table.items.len - 1;
                self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;
                return .{ .needs_render = old_row != self.display.selected_row };
            },

            .g => {
                const old_row = self.display.selected_row;
                self.display.selected_row = 0;
                self.display.row_page_idx = 0;
                return .{ .needs_render = old_row != self.display.selected_row };
            },

            .home => {
                const old_page = self.display.col_page_idx;
                self.display.col_page_idx = 0;
                return .{ .needs_render = old_page != 0 };
            },

            .end => {
                const old_page = self.display.col_page_idx;
                self.display.col_page_idx = self.display.col_pages.items.len - 1;
                return .{ .needs_render = old_page != self.display.col_page_idx };
            },

            else => return .{ .needs_render = false },
        }
    }

    /// Jump display to show a specific search match
    fn jumpToMatch(self: *AppState, match: SearchResult) !void {
        self.display.selected_row = match.row;
        self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;

        // Jump to column page if match is not visible
        const col_start, const col_end = self.display.get_header_idxs();
        if (match.col < col_start or match.col >= col_end) {
            for (self.display.col_pages.items, 0..) |start_idx, i| {
                const end_idx = if (i + 1 < self.display.col_pages.items.len)
                    self.display.col_pages.items[i + 1]
                else
                    self.csv.headers.items.len;

                if (match.col >= start_idx and match.col < end_idx) {
                    self.display.col_page_idx = i;
                    break;
                }
            }
        }
    }
};

pub fn main() !void {
    // ALLOCATORS
    var da = std.heap.DebugAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug)
        da.allocator()
    else
        std.heap.smp_allocator;

    // COMMAND LINE ARGS
    var parser = Parser.init(allocator) catch |err| {
        if (err == error.NoFileGiven) {
            Parser.printHelp();
        }
        return err;
    };

    if (parser.help) {
        Parser.printHelp();
        return;
    }
    defer parser.deinit();

    // CSV data/parsing
    var csv = Csv.init(allocator, parser.delim);
    try csv.parse(parser.path, parser.header);
    defer csv.deinit();

    var term_size = try TermSize.init();
    var stdout: TermWriter = undefined;
    stdout.init();

    var display = try Display.init(
        allocator,
        &csv,
        &stdout,
        &term_size,
        parser.width,
        parser.row_nums,
    );
    defer display.deinit();

    var input = try Input.init();
    defer input.deinit();

    var search_state = SearchState.init(allocator);
    defer search_state.deinit();

    // Initialize app state
    var search_input_buffer: [MAX_SEARCH_INPUT]u8 = undefined;
    var app = AppState.init(&display, &csv, &search_state, &search_input_buffer);

    // Initial render
    try display.render(&search_state, app.search_input[0..app.search_input_len]);

    // Main event loop
    while (true) {
        const key = try input.readKey();

        const result = if (app.search_state.input_mode)
            try app.handleSearchModeKey(key)
        else
            try app.handleNormalModeKey(key);

        if (result.should_quit) break;

        if (result.needs_render) {
            try display.render(&search_state, app.search_input[0..app.search_input_len]);
        }
    }

    try stdout.clear();
    try stdout.showCursor();
}
