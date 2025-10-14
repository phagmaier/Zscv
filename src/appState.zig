const std = @import("std");
const String = @import("string.zig").String;
const Display = @import("display.zig").Display;
const Csv = @import("csv.zig").Csv;
const SearchState = @import("search.zig").SearchState;
pub const SearchResult = @import("search.zig").SearchResult;
const Key = @import("input.zig").Key;

pub const Mode = enum {
    normal,
    search,
    colon,
    quit,
};

/// Application state encapsulation
pub const AppState = struct {
    display: *Display,
    csv: *Csv,
    search_state: *SearchState,
    string: String,
    mode: Mode,
    pub fn init(display: *Display, csv: *Csv, search_state: *SearchState) !AppState {
        return .{
            .display = display,
            .csv = csv,
            .search_state = search_state,
            .string = String.init(),
            .mode = Mode.normal,
        };
    }
    fn add_char(self: *AppState, char: u8) bool {
        const val = self.string.append(char);
        if (val) {
            return true;
        }
        return false;
    }

    pub fn handleSearchModeKey(self: *AppState, key: Key) !bool {
        switch (key) {
            .escape => {
                self.mode = Mode.normal;
                self.search_state.cancelInput();
                self.string.clear();
                return true;
            },

            .enter => {
                try self.search_state.performSearch(self.csv, self.string.get_slice());
                self.mode = Mode.normal;

                if (self.search_state.matches.items.len > 0) {
                    try self.jumpToMatch(self.search_state.matches.items[0]);
                }
                return true;
            },

            .backspace => {
                if (self.string.pop() != null) {
                    return true;
                }
                return false;
            },

            .n => {
                return self.add_char('n');
            },
            .N => {
                return self.add_char('N');
            },
            .q => {
                return self.add_char('q');
            },
            .g => {
                return self.add_char('g');
            },
            .G => {
                return self.add_char('G');
            },
            .slash => {
                return self.add_char('/');
            },

            .colon => {
                return self.add_char(':');
            },

            .char => |c| {
                return self.add_char(c);
            },

            else => return false,
        }
    }

    pub fn handleNormalModeKey(self: *AppState, key: Key) !bool {
        switch (key) {
            .q => {
                self.mode = Mode.quit;
                return false;
            },

            .escape => {
                self.string.clear();
                if (self.search_state.active) {
                    self.search_state.clearSearch();
                    return true;
                }
                return false;
            },

            .slash => {
                self.mode = Mode.search;
                self.string.clear();
                self.search_state.startSearch();
                return true;
            },
            //Add Functionality for this
            .colon => {
                self.mode = Mode.colon;
                self.string.clear();
                return self.add_char(':');
            },

            .n => {
                if (self.search_state.active and self.search_state.matches.items.len > 0) {
                    if (self.search_state.nextMatch()) |match| {
                        try self.jumpToMatch(match);
                        return true;
                    }
                }
                return false;
            },

            .N => {
                if (self.search_state.active and self.search_state.matches.items.len > 0) {
                    if (self.search_state.prevMatch()) |match| {
                        try self.jumpToMatch(match);
                        return true;
                    }
                }
                return false;
            },

            .right => {
                if (self.display.col_page_idx + 1 < self.display.col_pages.items.len) {
                    self.display.col_page_idx += 1;
                    return true;
                }
                return false;
            },

            .left => {
                if (self.display.col_page_idx > 0) {
                    self.display.col_page_idx -= 1;
                    return true;
                }
                return false;
            },

            .down => {
                const max_row = self.csv.table.items.len - 1;
                if (self.display.selected_row < max_row) {
                    self.display.selected_row += 1;
                    const row_page = self.display.selected_row / self.display.visible_rows;
                    if (row_page != self.display.row_page_idx) {
                        self.display.row_page_idx = row_page;
                    }
                    return true;
                }
                return false;
            },

            .up => {
                if (self.display.selected_row > 0) {
                    self.display.selected_row -= 1;
                    const row_page = self.display.selected_row / self.display.visible_rows;
                    if (row_page != self.display.row_page_idx) {
                        self.display.row_page_idx = row_page;
                    }
                    return true;
                }
                return false;
            },

            .page_down => {
                const max_row = self.csv.table.items.len - 1;
                const old_row = self.display.selected_row;
                self.display.selected_row = @min(self.display.selected_row + self.display.visible_rows, max_row);
                self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;
                return old_row != self.display.selected_row;
            },

            .page_up => {
                const old_row = self.display.selected_row;
                if (self.display.selected_row >= self.display.visible_rows) {
                    self.display.selected_row -= self.display.visible_rows;
                } else {
                    self.display.selected_row = 0;
                }
                self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;
                return old_row != self.display.selected_row;
            },

            .G => {
                const old_row = self.display.selected_row;
                self.display.selected_row = self.csv.table.items.len - 1;
                self.display.row_page_idx = self.display.selected_row / self.display.visible_rows;
                return old_row != self.display.selected_row;
            },

            .g => {
                const old_row = self.display.selected_row;
                self.display.selected_row = 0;
                self.display.row_page_idx = 0;
                return old_row != self.display.selected_row;
            },

            .home => {
                const old_page = self.display.col_page_idx;
                self.display.col_page_idx = 0;
                return old_page != 0;
            },

            .end => {
                const old_page = self.display.col_page_idx;
                self.display.col_page_idx = self.display.col_pages.items.len - 1;
                return old_page != self.display.col_page_idx;
            },

            else => return false,
        }
    }

    //Add colon logic you basically just read shit then on enter check if number
    //may add other functunality later for now just try to jump to line
    pub fn handle_colon_key(self: *AppState, key: Key) !bool {
        switch (key) {
            .escape => {
                self.mode = Mode.normal;
                self.search_state.cancelInput();
                self.string.clear();
                return true;
            },

            .enter => {
                try self.handle_col_input();
                self.string.clear();
                self.mode = Mode.normal;
                return true;
            },

            .backspace => {
                if (self.string.pop() != null) {
                    return true;
                }
                return false;
            },

            .n => {
                return self.add_char('n');
            },
            .N => {
                return self.add_char('N');
            },
            .q => {
                return self.add_char('q');
            },
            .g => {
                return self.add_char('g');
            },
            .G => {
                return self.add_char('G');
            },
            .slash => {
                return self.add_char('/');
            },

            .colon => {
                return self.add_char(':');
            },

            .char => |c| {
                return self.add_char(c);
            },

            else => return false,
        }
    }

    //add more commands here currently it just handles q
    fn handle_colon_command(self: *AppState, command: []const u8) void {
        if (std.mem.eql(u8, "q", command)) {
            self.mode = Mode.quit;
        }
    }

    fn handle_col_input(self: *AppState) !void {
        //this just means only the colon is here
        if (self.string.len == 1) {
            return;
        }
        const command = self.string.data[1..self.string.len];
        //number can't be larger than 20 digits
        if (command.len > 20) {
            self.handle_colon_command(command);
        }
        for (command) |c| {
            if (!std.ascii.isDigit(c)) {
                self.handle_colon_command(command);
                return;
            }
        }
        const row = try std.fmt.parseInt(usize, command, 10);
        if (row != self.display.selected_row and row <= self.csv.data.len) {
            self.display.selected_row = row;
            self.display.row_page_idx = row / self.display.visible_rows;
        }
    }

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
