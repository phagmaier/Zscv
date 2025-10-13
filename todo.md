**SHOULD DO:**
3.  - **Cell expansion** - Press Enter to see full cell content in a modal/overlay. Really useful for long text.
4.  - **More vim navigation** - `Ctrl+D`/`Ctrl+U` for half-page, `H`/`M`/`L` for screen top/middle/bottom. Feels pro.

**COULD DO:**
5. - **Column iteration** - Tab to switch between row/column nav mode? Interesting but less useful than you'd think.

**ADDITIONAL COOL FEATURES:**

**High Value:**
- **Column sorting** - Press `s` then column number. Huge for data exploration.
- **Export search results** - Press `w` to write matches to new CSV. People love this.
- **Jump to row/column** - Type `:50` to jump to row 50. Vim-style, very useful.
- **Column filtering** - Press `f` to hide/show columns. Declutters view.

**Medium Value:**
- **Copy cell/row to clipboard** - Press `y` (yank). Needs xclip/pbcopy integration.
- **Statistics mode** - Show count/avg/min/max for numeric columns.
- **Freeze panes** - Keep first N columns visible while scrolling right.
- **Multiple file tabs** - Tab between CSVs (like browser tabs).

**Polish:**
- **Help screen** - Press `?` for keybindings overlay. Users will need this.
- **Status messages** - Flash messages like "Copied to clipboard!" for 2 seconds.
- **Search history** - Up arrow to recall previous searches.

## Order:

### Phase 1: Fix Annoyances (This Week)
1. Help screen (? key) 

### Phase 2: Power Features (Next Week)
5. Cell expansion (Enter key)
6. Jump to row/column (`:123` command)
7. Column sorting (basic alphabetic first)

### Phase 3: Polish (Later)
8. More vim navigation
9. Export filtered/searched results
10. Column filtering
11. Copy to clipboard


