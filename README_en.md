# Notepad++ for macOS

[![macOS Build](https://img.shields.io/badge/platform-macOS%2010.15+-brightgreen.svg)](BUILD_MAC.md)
[![C++20](https://img.shields.io/badge/C%2B%2B-20-blue.svg)](https://en.wikipedia.org/wiki/C%2B%2B20)
[![Unit Tests](https://img.shields.io/badge/tests-49%20passed%20(100%25)-success.svg)](BUILD_MAC.md)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Notepad++ for macOS** is a native port of the popular Windows text and source code editor [Notepad++](https://github.com/notepad-plus-plus/notepad-plus-plus). Built with **Apple Clang C++20**, **Cocoa (AppKit/Foundation)**, **Scintilla Cocoa**, **Lexilla**, and **WebKit**, it delivers full Notepad++ feature parity adhering to macOS Human Interface Guidelines (HIG).

---

## 🌟 Key Features

### 🔲 Column Mode & Column Editor (`⌥⌘C` / Option+Drag)
- **Column Mode (열 모드)**:
  - **Rectangular Selection**: `⌥` (Option) + Drag or `⌥⇧` (Option+Shift) + Arrow keys for multi-line column block selections.
  - **Multi-Caret Typing & Multi-Paste**: `⌘` + Click for multiple independent carets; paste replaces into each column line.
  - **Column Editor Dialog (열 편집기)**:
    - Shortcut: `⌥⌘C` (or Edit menu > `Column Editor... (열 편집기)`) or toolbar button.
    - **Text to Insert**: Insert prefix/strings simultaneously across all selected column lines.
    - **Number to Insert**: Initial number, Increase by, Repeat count, Format (**Dec, Hex, Oct, Bin**), and Leading characters (**None, Zeros, Spaces**).

---

### 🍏 Modern IDE 3-Panel Layout (VS Code Style)
- **Primary Side Panel (Left - Finder Tree starting at `~/`)**:
  - Toggle via top-right toolbar button (`sidebar.left`) or `⌘B`.
  - Displays a native macOS **Finder-style hierarchy starting at `~/` (Home directory)** with authentic system icons.
  - Non-blocking **Lazy-Loading** (0-lag on-demand inspection of folders).
  - Double-click any file to open it in an editor tab; double-click folder to expand/collapse.
- **Bottom Panel (Bottom - Embedded Interactive Terminal Pane)**:
  - Toggle via top-right toolbar button (`dock.rectangle`) or `⌃\`` (Control+Backtick).
  - Embedded split console pane with real-time `/bin/zsh` execution, prompt `$ `, directory tracking (`cd`), and command history.
  - Top bar includes one-click button to open external **macOS `Terminal.app`** at the current directory.
- **Secondary Side Panel (Right - Language Guide & Live WebKit Preview)**:
  - Toggle via top-right toolbar button (`sidebar.right`) or `⇧⌘P`.
  - **Default Screen**: Provides an intuitive guide asking to select a language from the **`Language` menu** (with quick-select buttons for Markdown, HTML, JSON, XML, C++, Python, SQL).
  - **Live Rendering**: Renders Markdown, HTML, JSON, XML/SVG, and Syntax-highlighted code live as you type in Scintilla.

---

### 📑 Complete 11-Category Menu Bar
1. **Notepad++**: About Notepad++, Preferences (`⌘,`), Services, Hide (`⌘H`), Hide Others (`⌥⌘H`), Quit (`⌘Q`).
2. **File**:
   - New (`⌘N`), Open (`⌘O`), Reload from Disk (`⌘R`), Save (`⌘S`), Save As (`⇧⌘S`), Save All (`⌥⌘S`)
   - Rename File, Reveal in Finder (`⇧⌘R`), Open in Terminal (`⌥⌘T`), Copy Full Path, Copy Filename, Copy Directory Path
   - Close Tab (`⌘W`), Close All (`⇧⌘W`), Close All BUT Active, Close All to Left, Close All to Right.
3. **Edit**:
   - Undo (`⌘Z`), Redo (`⇧⌘Z`), Cut (`⌘X`), Copy (`⌘C`), Paste (`⌘V`), Select All (`⌘A`)
   - **Column Editor... (열 편집기)** (`⌥⌘C`): Insert text or incrementing numbers into column selections.
   - **Line Operations**: Duplicate Line (`⌘D`), Split Lines, Join Lines (`⌃J`), Move Selected Lines Up/Down (`⌥↑`/`⌥↓`), Sort Ascending/Descending, Remove Duplicate Lines, Remove Empty Lines, Remove Empty Lines with Blank
   - **Blank Operations**: Trim Trailing Space, Trim Leading Space
   - **Convert Case**: UPPERCASE (`⇧⌘U`), lowercase (`⌘U`)
   - **Insert**: Date Time Short (`yyyy-MM-dd HH:mm`), Date Time Long
   - **Comments**: Toggle Line Comment (`⌘/`).
4. **Search**:
   - Find (`⌘F`), Find Next (`⌘G`), Find Previous (`⇧⌘G`), Replace (`⌥⌘F`), Use Selection for Find (`⌘E`), **Mark All Occurrences**
   - Go to Line (`⌘L`), Go to Matching Brace (`⌘B`)
   - **Bookmarks**: Toggle Bookmark (`⌘F2`), Next Bookmark (`F2`), Previous Bookmark (`⇧F2`), Clear All Bookmarks.
5. **View**:
   - **Toggle Primary Side Bar (Finder Tree)** (`⌘B`)
   - **Toggle Bottom Panel (Embedded Terminal)** (`⌃\``)
   - **Toggle Secondary Side Bar (Language Preview)** (`⇧⌘P`)
   - Zoom In (`⌘+`), Zoom Out (`⌘-`), Restore Default Zoom (`⌘0`)
   - Word Wrap (`⌥⌘W`), Line Numbers, Show All Characters (White Space / EOL), Show Indent Guides
   - Fold All (`⌥⌘0`), Unfold All (`⌥⇧⌘0`), Document Summary dialog, Dark Mode toggle (`⇧⌘D`).
6. **Encoding**:
   - UTF-8 (Default), UTF-8 BOM, UTF-16 LE, UTF-16 BE, ANSI (CP1252), Korean (EUC-KR), Japanese (Shift-JIS), Chinese (Big5, GB2312)
   - Convert to Unix (LF), Convert to Windows (CRLF), Convert to Mac (CR).
7. **Language**: 24+ highlighters including C/C++, Python, JavaScript/TypeScript, HTML, XML, JSON, CSS, Markdown, SQL, Rust, Go, Java, PHP, YAML, Shell, TOML, Zig.
8. **Settings**:
   - **Preferences...** (`⌘,`): Complete Master-Detail settings window.
   - **Style Configurator...**: Direct theme and typography selection.
9. **Tools & Cryptography**:
   - **Generate MD5 Hash / SHA-256 Hash**
   - **Base64 Encode / Base64 Decode**
   - **URL Encode / URL Decode**.
10. **Macro**: Record (`⌃⌘R`, status bar indicator `REC ●`) and Playback (`⌃⌘P`).
11. **Window & Help**: Window management and standard Apple About Panel.

---

## 🚀 Quick Start & Building

```bash
# Build the executable (bin/notepad++)
make -f Makefile.mac all

# Run the 49 automated unit tests (394 assertions)
make -f Makefile.mac test

# Create standalone macOS Application Bundle (bin/Notepad++.app)
make -f Makefile.mac bundle

# Launch the application
open bin/Notepad++.app
```

---

## 🧪 Verification & Automated Testing

The automated test runner (`bin/npp_tests`) executes 49 test suites covering string conversions, POSIX file I/O, UTF-8/UTF-16/BOM codecs, `uchardet` encoding detection, `pugixml` parsing, Lexilla syntax lexers, and document buffers:

```
================================================================================
  Test Execution Summary
================================================================================
  Total Tests:       49
  Passed:            49 (100% PASS)
  Failed:            0
  Total Assertions:  394
  Total Time:        17.27 ms
================================================================================
>>> ALL TESTS PASSED SUCCESSFULLY! <<<
```

---

## 📄 License

Notepad++ is distributed under the [GNU General Public License v3](LICENSE).
Ported to macOS with native Cocoa frontend.
