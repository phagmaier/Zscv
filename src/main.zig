//const Parser = @import("parser.zig").ArgParse;
//const Csv = @import("csv.zig").Csv;
//const TermSize = @import("termSize.zig").TermSize;
//const Display = @import("display.zig").Display;
//const Input = @import("input.zig").Input;
//const SearchState = @import("search.zig").SearchState;
//const TermWriter = @import("termWriter.zig").TermWriter;
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

const MAX_SEARCH_INPUT = 256;

pub fn main() !void {
    //ALLOCATORS
    var da = std.heap.DebugAllocator(.{}){};
    const allocator = if (builtin.mode == .Debug)
        da.allocator()
    else
        std.heap.smp_allocator;

    //COMMAND LINE ARGS
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

    //Csv data/parsing
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

    var search_input: [MAX_SEARCH_INPUT]u8 = undefined;
    var search_input_len: usize = 0;

    while (true) {
        try display.render(&search_state, search_input[0..search_input_len]);
        const key = try input.readKey();

        // ----------------  SEARCH-TYPING MODE  -------------------------
        if (search_state.input_mode) {
            switch (key) {
                .escape => {
                    search_state.endSearch();
                    search_input_len = 0;
                },
                .enter => {
                    search_state.setQuery(search_input[0..search_input_len]);
                    try search_state.performSearch(&csv);
                    search_state.input_mode = false;

                    // Jump to FIRST match
                    if (search_state.matches.items.len > 0) {
                        const first = search_state.matches.items[0];
                        display.selected_row = first.row; // ✓ Already correct index
                        display.row_page_idx = display.selected_row / display.visible_rows;

                        // column-page jump (if possible)
                        const col_start, const col_end = display.get_header_idxs();
                        if (first.col < col_start or first.col >= col_end) {
                            for (display.col_pages.items, 0..) |start_idx, i| {
                                const end_idx = if (i + 1 < display.col_pages.items.len)
                                    display.col_pages.items[i + 1]
                                else
                                    csv.headers.items.len; // Changed from csv.table.items[0].items.len
                                if (first.col >= start_idx and first.col < end_idx) {
                                    display.col_page_idx = i;
                                    break;
                                }
                            }
                        }
                    }
                },
                .backspace => {
                    if (search_input_len > 0) search_input_len -= 1;
                },

                //Dealing with special keys in search mode
                .n => {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = 'n';
                        search_input_len += 1;
                    }
                },
                .N => {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = 'N';
                        search_input_len += 1;
                    }
                },
                .q => {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = 'q';
                        search_input_len += 1;
                    }
                },
                .g => {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = 'g';
                        search_input_len += 1;
                    }
                },
                .G => {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = 'G';
                        search_input_len += 1;
                    }
                },
                .slash => {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = '/';
                        search_input_len += 1;
                    }
                },

                .char => |c| {
                    if (search_input_len < MAX_SEARCH_INPUT) {
                        search_input[search_input_len] = c;
                        search_input_len += 1;
                    }
                },
                else => {},
            }
            continue;
        }

        // ----------------  NORMAL MODE  --------------------------------
        switch (key) {
            .q => break,

            .slash => {
                search_state.startSearch();
                search_input_len = 0;
            },

            .n => {
                if (search_state.active and search_state.matches.items.len > 0) {
                    if (search_state.nextMatch()) |match| {
                        display.selected_row = match.row; // ✓ NO -1!
                        display.row_page_idx = display.selected_row / display.visible_rows;

                        const col_start, const col_end = display.get_header_idxs();
                        if (match.col < col_start or match.col >= col_end) {
                            for (display.col_pages.items, 0..) |start_idx, i| {
                                const end_idx = if (i + 1 < display.col_pages.items.len)
                                    display.col_pages.items[i + 1]
                                else
                                    csv.headers.items.len; // Changed
                                if (match.col >= start_idx and match.col < end_idx) {
                                    display.col_page_idx = i;
                                    break;
                                }
                            }
                        }
                    }
                }
            },

            // ========== SHIFT+N KEY (previous match) ==========
            .N => {
                if (search_state.active and search_state.matches.items.len > 0) {
                    if (search_state.prevMatch()) |match| {
                        display.selected_row = match.row; // ✓ NO -1!
                        display.row_page_idx = display.selected_row / display.visible_rows;

                        const col_start, const col_end = display.get_header_idxs();
                        if (match.col < col_start or match.col >= col_end) {
                            for (display.col_pages.items, 0..) |start_idx, i| {
                                const end_idx = if (i + 1 < display.col_pages.items.len)
                                    display.col_pages.items[i + 1]
                                else
                                    csv.headers.items.len; // Changed
                                if (match.col >= start_idx and match.col < end_idx) {
                                    display.col_page_idx = i;
                                    break;
                                }
                            }
                        }
                    }
                }
            },

            .right => {
                if (display.col_page_idx + 1 < display.col_pages.items.len)
                    display.col_page_idx += 1;
            },
            .left => {
                if (display.col_page_idx > 0) display.col_page_idx -= 1;
            },

            .down => {
                const max_row = csv.table.items.len - 1; // Changed from len - 2
                if (display.selected_row < max_row) {
                    display.selected_row += 1;
                    const row_page = display.selected_row / display.visible_rows;
                    if (row_page != display.row_page_idx) display.row_page_idx = row_page;
                }
            },

            .page_down => {
                const max_row = csv.table.items.len - 1; // Changed from len - 2
                display.selected_row = @min(display.selected_row + display.visible_rows, max_row);
                display.row_page_idx = display.selected_row / display.visible_rows;
            },

            .G => {
                display.selected_row = csv.table.items.len - 1; // Changed from len - 2
                display.row_page_idx = display.selected_row / display.visible_rows;
            },
            .up => {
                if (display.selected_row > 0) {
                    display.selected_row -= 1;
                    const row_page = display.selected_row / display.visible_rows;
                    if (row_page != display.row_page_idx) display.row_page_idx = row_page;
                }
            },

            .page_up => {
                if (display.selected_row >= display.visible_rows)
                    display.selected_row -= display.visible_rows
                else
                    display.selected_row = 0;
                display.row_page_idx = display.selected_row / display.visible_rows;
            },
            .home => display.col_page_idx = 0,
            .end => display.col_page_idx = display.col_pages.items.len - 1,
            .g => {
                display.selected_row = 0;
                display.row_page_idx = 0;
            },

            else => {},
        }
    }

    try stdout.clear();
    try stdout.showCursor();
}
