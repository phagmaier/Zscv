# 📊 Zcsv — Fast Terminal CSV Viewer in Zig

A blazing-fast, lightweight, terminal-based CSV viewer written in **Zig**, featuring **Vim-inspired keybindings**, **search**, and **clean table rendering** — perfect for quick CSV inspection, especially over SSH.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Zig](https://img.shields.io/badge/Zig-0.15.1-orange.svg)](https://ziglang.org/)
[![Status](https://img.shields.io/badge/Status-Active%20Development-green.svg)]()

---

##  Note 
**This is in a very early beta stage** 

## ✨ Features

- 🚀 **Fast & Lightweight** – Handles CSVs up to ~2MB with instant load times  
- 🔍 **Search & Highlighting** – Case-insensitive substring search with colorized matches  
- ⌨️ **Vim-Inspired Navigation** – Familiar, efficient keybindings  
- 🧭 **Column Pagination** – View wide tables that exceed screen width  
- 🎨 **Colorized UI** – Alternating rows, selection, and match highlighting  
- ⚙️ **Configurable** – Custom delimiters, column widths, and header handling  
- 📡 **SSH-Friendly** – Runs in any terminal, no GUI required  
- 📏 **Clean Layout** – Unicode box-drawing characters for polished table rendering  

---

## 🎯 Why Zcsv?

`Zcsv` bridges the gap between basic CLI tools (`cat`, `less`) and heavy GUI apps (Excel, LibreOffice). It’s built for **fast, interactive data exploration directly in your terminal**.

**Ideal for:**
- Inspecting CSVs on remote servers  
- Validating and spot-checking data  
- Searching through large datasets quickly  
- Working in terminal-only environments  

---

## 📥 Installation

### Requirements
- **Zig 0.15.1** or later  
- **256-color terminal** support  

### Build from Source

```bash
# Clone the repository
git clone https://github.com/phagmaier/Zcsv.git
cd Zcsv

# Build in release mode
zig build -Doptimize=ReleaseSafe

# Optional: install to PATH
sudo cp zig-out/bin/Zcsv /usr/local/bin/
```

---

## 📦 Using as a Library

`Zcsv` can also be used as a **library** in your own Zig projects for CSV parsing and display.

### 1. Add as a Dependency
In your `build.zig.zon`:

```zig
.{
    .name = "my-awesome-app",
    .version = "0.1.0",
    .dependencies = .{
        .zcsv = .{
            .url = "https://github.com/phagmaier/Zcsv/archive/main.tar.gz",
            .hash = "1220...", // Fill after running `zig build`
        },
    },
}
```

---

## 🚀 Command-Line Usage

```bash
zcsv [OPTIONS] <file>
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h, --help` | Show help message | - |
| `-d, --delim <char>` | Delimiter character | `,` |
| `-H, --no-header` | Treat first row as data | false |
| `-m, --max-width <n>` | Maximum column width | 40 |
| `-n, --no-row-numbers` | Hide row number column | false |

### Examples

```bash
# Basic usage
zcsv data.csv

# Tab-separated file
zcsv -d $'\t' data.tsv

# Pipe-separated, custom width
zcsv -d '|' -m 60 data.txt

# No header, hide row numbers
zcsv --no-header --no-row-numbers raw-data.csv
```

---

## ⌨️ Keybindings

### Navigation
| Key | Action |
|-----|--------|
| `↑` / `↓` | Move up/down one row |
| `←` / `→` | Switch column pages |
| `Page Up` / `Page Down` | Scroll one page |
| `Home` / `End` | Jump to first/last column page |
| `g` / `G` | Jump to first/last row |

### Search
| Key | Action |
|-----|--------|
| `/` | Start search |
| `Enter` | Execute search |
| `n` / `N` | Next/previous match |
| `Esc` | Exit search mode |

### Misc
| Key | Action |
|-----|--------|
| `q` | Quit viewer |

---

## 🎨 Visual Highlights

- Alternating row colors for readability  
- Highlighted current row and matches  
- Compact status bar (position, mode, hints)  
- Clean box-drawing table borders  

---

## 📋 Development Status

### ✅ Completed
- CSV parsing with configurable delimiters  
- Column & row pagination  
- Case-insensitive search with highlighting  
- Command-line argument parsing  
- Configurable width, header, row numbers  
- Vim-style navigation  
- Colored UI  

### 🚧 Phase 1 — Fix Annoyances *(Current)*
- [ ] Clear search highlight (Esc twice)  
- [ ] Redraw only on state changes  
- [ ] Add in-app help screen (`?`)  

### 🧠 Phase 2 — Power Features *(Next)*
- [ ] Expand cell view (`Enter`)  
- [ ] Jump to row/column (`:123`)  
- [ ] Sort by column (`s` then number)  
- [ ] More Vim motions (`Ctrl+D/U`, `H/M/L`)  

### 🎯 Phase 3 — Polish & Extras
- [ ] Export search results  
- [ ] Filter columns (`f`)  
- [ ] Copy cell/row to clipboard (`y`)  
- [ ] Search history  
- [ ] Stats mode (count/avg/min/max)  
- [ ] Flash messages for actions  
- [ ] Freeze columns  
- [ ] Multi-file tabs  

---

## 🏗️ Architecture

`Zcsv` is built as a **core library** plus a **TUI front-end**.

**Main Files**
```
main.zig        - Entry point, event loop
csv.zig         - CSV parsing with arena allocator
display.zig     - Rendering & display logic
search.zig      - Search state and matches
input.zig       - Keyboard input (raw mode)
termWriter.zig  - Terminal output abstraction
termSize.zig    - Terminal size detection
argparse.zig    - Command-line parser
```

**Design Principles**
- Render only visible rows (efficient pagination)  
- Pre-calculate column widths  
- Direct terminal control (no ncurses dependency)  
- Minimize allocations / zero-copy when possible  

---

## 🤝 Contributing

Contributions are always welcome!  
Areas you can help with:

1. 🚀 **Performance** – Streaming support for >2MB files  
2. ✨ **Features** – Help implement roadmap items  
3. 🧪 **Testing** – Edge cases and malformed CSVs  
4. 📖 **Docs** – Tutorials and usage examples  
5. 🖥️ **Platform Support** – Different terminals/systems  

---

## 📝 Known Limitations

- Max file size: ~2MB (configurable)  
- No regex search (yet)  
- No editing or write-back  
- Terminal must support 256 colors  

---

## 🐛 Reporting Bugs

When reporting issues, include:
- Terminal type & version  
- File details (size, delimiter, etc.)  
- Steps to reproduce  
- Expected vs. actual behavior  

[➡️ Open an Issue](https://github.com/phagmaier/Zcsv/issues)

---

## 📜 License

**MIT License** — see [`LICENSE`](LICENSE) for details.

---

## 🙏 Acknowledgments

- Inspired by [`visidata`](https://www.visidata.org/), `csvkit`, and `less`  
- Built with [Zig](https://ziglang.org/) my new favorite language
- Built with a hatred for Rust my least favorite language
- Uses Unicode box-drawing for clean visual layout  
- Ai slop for writing this emoji infested abomination of a readme that i was too lazy to

---

**⭐ Star the repo if Zcsv made your terminal life easier!**
