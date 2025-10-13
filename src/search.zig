const std = @import("std");
const Csv = @import("csv.zig").Csv;

pub const SearchResult = struct {
    row: usize,
    col: usize,
};

pub const SearchState = struct {
    allocator: std.mem.Allocator,
    query: []const u8,
    matches: std.ArrayList(SearchResult),
    current_match: usize,
    active: bool,
    input_mode: bool,
    updated: bool,

    pub fn init(allocator: std.mem.Allocator) SearchState {
        return SearchState{
            .allocator = allocator,
            .query = "",
            .matches = std.ArrayList(SearchResult).empty,
            .current_match = 0,
            .active = false,
            .input_mode = false,
            .updated = false,
        };
    }

    pub fn deinit(self: *SearchState) void {
        self.matches.deinit(self.allocator);
    }

    pub fn startSearch(self: *SearchState) void {
        self.active = true;
        self.input_mode = true;
        self.current_match = 0;
        self.updated = true;
    }

    // Cancel search input mode (but keep previous results if any)
    pub fn cancelInput(self: *SearchState) void {
        self.input_mode = false;
        self.updated = true;
        // Don't touch active or matches - might have previous search
    }

    // Completely clear search state and results
    pub fn clearSearch(self: *SearchState) void {
        self.active = false;
        self.input_mode = false;
        self.matches.clearAndFree(self.allocator);
        self.current_match = 0;
        self.query = "";
        self.updated = true;
    }

    pub fn setQuery(self: *SearchState, query: []const u8) void {
        self.query = query;
        self.updated = true;
    }

    pub fn addMatch(self: *SearchState, row: usize, col: usize) !void {
        try self.matches.append(self.allocator, SearchResult{ .row = row, .col = col });
    }

    pub fn nextMatch(self: *SearchState) ?SearchResult {
        if (self.matches.items.len == 0) return null;
        self.current_match = (self.current_match + 1) % self.matches.items.len;
        self.updated = true;
        return self.matches.items[self.current_match];
    }

    pub fn prevMatch(self: *SearchState) ?SearchResult {
        if (self.matches.items.len == 0) return null;
        if (self.current_match == 0)
            self.current_match = self.matches.items.len - 1
        else
            self.current_match -= 1;
        self.updated = true;
        return self.matches.items[self.current_match];
    }

    pub fn getCurrentMatch(self: *SearchState) ?SearchResult {
        if (self.matches.items.len == 0) return null;
        self.updated = true;
        return self.matches.items[self.current_match];
    }

    pub fn performSearch(self: *SearchState, csv: *Csv) !void {
        self.updated = true;
        self.matches.clearAndFree(self.allocator);

        if (self.query.len == 0) return;

        const query_lower = try std.ascii.allocLowerString(self.allocator, self.query);
        defer self.allocator.free(query_lower);

        for (csv.table.items, 0..) |row, row_idx| {
            for (row.items, 0..) |cell, col_idx| {
                const cell_lower = try std.ascii.allocLowerString(self.allocator, cell);
                defer self.allocator.free(cell_lower);

                if (std.mem.indexOf(u8, cell_lower, query_lower) != null) {
                    try self.addMatch(row_idx, col_idx);
                }
            }
        }
    }
};
