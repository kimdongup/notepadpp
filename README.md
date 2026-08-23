# Notepad++ for macOS

[![macOS Build](https://img.shields.io/badge/platform-macOS%2010.15+-brightgreen.svg)](BUILD_MAC.md)
[![C++20](https://img.shields.io/badge/C%2B%2B-20-blue.svg)](https://en.wikipedia.org/wiki/C%2B%2B20)
[![Unit Tests](https://img.shields.io/badge/tests-49%20passed%20(100%25)-success.svg)](BUILD_MAC.md)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Notepad++ for macOS** is a native port of the popular Windows text and source code editor [Notepad++](https://github.com/notepad-plus-plus/notepad-plus-plus). Built with **Apple Clang C++20**, **Cocoa (AppKit/Foundation)**, **Scintilla Cocoa**, and **Lexilla**, it delivers full Notepad++ feature parity adhering to macOS Human Interface Guidelines (HIG).

---

## 🌟 Key Features

### 🍏 Native macOS Experience & Standards
- **macOS Standards Compliance**:
  - **Default Line Endings**: Unix (`LF`)
  - **Default Encoding**: UTF-8 without BOM
  - **Default Typography**: `SF Mono` / System Monospaced Font
  - **Unified Titlebar**: Integrated document proxy icon and unsaved changes dirty dot (`documentEdited`)
  - **Finder Drag-and-Drop**: Direct file opening from macOS Finder (`NSPasteboardTypeFileURL`)
  - **macOS Directory Mapping**: Configuration and User Defined Languages mapped to `~/Library/Application Support/Notepad++`
- **Application Icon & Dock**: Native high-resolution application icon (`AppIcon.icns` / `Configure.icns`) with runtime Dock injection.

---

### 📑 Complete 11-Category Menu Bar
1. **Notepad++**: About Notepad++, Preferences (`⌘,`), Services, Hide (`⌘H`), Hide Others (`⌥⌘H`), Quit (`⌘Q`).
2. **File**:
   - New (`⌘N`), Open (`⌘O`), Reload from Disk (`⌘R`), Save (`⌘S`), Save As (`⇧⌘S`), Save All (`⌥⌘S`)
   - Rename File, Reveal in Finder (`⇧⌘R`), Open in Terminal (`⌥⌘T`), Copy Full Path, Copy Filename, Copy Directory Path
   - Close Tab (`⌘W`), Close All (`⇧⌘W`), Close All BUT Active, Close All to Left, Close All to Right.
3. **Edit**:
   - Undo (`⌘Z`), Redo (`⇧⌘Z`), Cut (`⌘X`), Copy (`⌘C`), Paste (`⌘V`), Select All (`⌘A`)
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
   - **Generate MD5 Hash** (Selection / full text, auto-copied to clipboard)
   - **Generate SHA-256 Hash** (Selection / full text, auto-copied to clipboard)
   - **Base64 Encode / Base64 Decode**
   - **URL Encode / URL Decode**.
10. **Macro**:
    - Start / Stop Recording (`⌃⌘R`, status bar indicator `REC ●`)
    - Playback Macro (`⌃⌘P`).
11. **Window & Help**: Window management and standard Apple About Panel.

---

### 🛠️ 25-Action Native Top Toolbar (`NSToolbar`)
Quick one-click access to:
- **Files**: New, Open, Save, Save All, Close, Close All
- **Editing**: Cut, Copy, Paste, Undo, Redo
- **Search & Zoom**: Find, Replace, Zoom In, Zoom Out
- **View Helpers**: Word Wrap, Line Numbers, All Characters (White Space/EOL), Indentation Guides
- **Productivity**: Macro Record (`REC ●`), Macro Playback, Document Summary, Open in Terminal, Dark Mode, Preferences

---

### ⚙️ Master-Detail Preferences Window (`⌘,`)
11 comprehensive settings categories:
- **⚙️ General**: Tab close buttons, double-click to close, pin tabs, toolbar and status bar options.
- **✏️ Editing**: Multi-Selection / Multi-Caret (`⌘`+Click), Column Editing (`⌥`+Drag), scroll past EOF, smooth scrolling.
- **📐 Margins & Border**: Line numbers margin, bookmark margin, code folding, **vertical column edge guide (80/100/120)**.
- **📄 New Document**: Default EOL (Unix LF / CRLF / CR), default encoding, default language.
- **⇥ Indentation & Tabs**: Tab size (2/4/8 spaces), Soft Tabs (Replace by spaces) vs Hard Tabs, smart auto-indent, indent guides.
- **🎨 Themes & Dark Mode**: 7 themes (**Notepad++ Dark**, **Default Light**, **Monokai Pro**, **Dracula**, **Solarized Dark**, **Solarized Light**, **Obsidian**) with refined neutral gray caret line and selection highlights.
- **💡 Highlighting**: Matching braces `()[]{}`, HTML/XML tag matching, current line highlight, smart word highlighting.
- **⚡ Auto-Completion**: Auto-close matching pairs `()`, `[]`, `{}`, `""`, `''`, `<>`, document word completion, function calltips.
- **🔍 Searching**: Wrap around, auto-fill search with selection (`⌘E`), default match case, whole word, regex.
- **💾 Backup & Session**: Session recovery (restore open tabs), 7-second auto-save snapshots, backup on save (`.bak`).
- **🚀 Performance**: Large file optimization threshold (200MB limit).

---

## 🏗️ Architecture

```
notepadpp/
├── PowerEditor/
│   ├── src/
│   │   ├── mac_main.mm          # Native Cocoa application entrypoint & controllers
│   │   ├── mac_compat.cpp/.h    # Win32 to POSIX/Cocoa compatibility shim
│   │   ├── AppIcon.icns         # High-resolution application icon
│   │   └── Utf8_16.cpp          # Multi-byte and Unicode conversion engine
│   └── Test/
│       └── test_*.cpp           # Automated unit test suites
├── scintilla/cocoa/             # Scintilla Cocoa platform layer (Quartz & CoreText)
├── lexilla/                     # Lexilla syntax highlighters
└── Makefile.mac                 # macOS native build orchestration
```

---

## 🚀 Quick Start & Building

### 1. Prerequisites
- macOS 10.15 or later (Apple Silicon M1/M2/M3/M4 & Intel x86_64)
- Xcode Command Line Tools:
  ```bash
  xcode-select --install
  ```

### 2. Build Commands
```bash
# Build the executable (bin/notepad++)
make -f Makefile.mac all

# Run the 49 automated unit tests (394 assertions)
make -f Makefile.mac test

# Create standalone macOS Application Bundle (bin/Notepad++.app)
make -f Makefile.mac bundle
```

### 3. Running the App
```bash
# Launch the application bundle
open bin/Notepad++.app

# Or launch directly from terminal
./bin/notepad++ [files...]
```

---

## 🧪 Verification & Automated Testing

The automated test runner (`bin/npp_tests`) executes 49 test suites covering string conversions, POSIX file I/O, UTF-8/UTF-16/BOM codecs, `uchardet` encoding detection, `pugixml` parsing, Lexilla syntax lexers, and document buffers:

```
================================================================================
  Notepad++ macOS Unit Test Suite Execution
================================================================================
  Total Tests:       49
  Passed:            49 (100% PASS)
  Failed:            0
  Total Assertions:  394
  Total Time:        14.55 ms
================================================================================
>>> ALL TESTS PASSED SUCCESSFULLY! <<<
```

---

## 📄 License

Notepad++ is distributed under the [GNU General Public License v3](LICENSE).
Ported to macOS with native Cocoa frontend.
