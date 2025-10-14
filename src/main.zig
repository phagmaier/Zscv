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
const AppState = zcsv.AppState;
const Mode = zcsv.Mode;
const InputMode = zcsv.InputMode;

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
    var app = try AppState.init(&display, &csv, &search_state);

    // Initial render
    try display.render(&search_state, app.string.get_slice());

    // Main event loop
    var update = false;
    while (true) {
        if (app.mode == Mode.quit) {
            break;
        }
        if (update) {
            try display.render(&search_state, app.string.get_slice());
        }

        const key = try input.readKey();
        update = switch (app.mode) {
            Mode.normal => try app.handleNormalModeKey(key),
            Mode.search => try app.handleSearchModeKey(key),
            Mode.colon => try app.handle_colon_key(key),
            else => true,
        };
    }

    try stdout.clear();
    try stdout.showCursor();
}
