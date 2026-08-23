# Notepad++ for macOS

[![macOS Build](https://img.shields.io/badge/platform-macOS%2010.15+-brightgreen.svg)](BUILD_MAC.md)
[![C++20](https://img.shields.io/badge/C%2B%2B-20-blue.svg)](https://en.wikipedia.org/wiki/C%2B%2B20)
[![Localization](https://img.shields.io/badge/languages-94%20countries-orange.svg)](#-94-languages-global-ui-localization)
[![Unit Tests](https://img.shields.io/badge/tests-66%20passed%20(100%25)-success.svg)](BUILD_MAC.md)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

**Notepad++ for macOS** is a native port of [Notepad++](https://github.com/notepad-plus-plus/notepad-plus-plus)—the world's most beloved text and source code editor—built specifically for macOS. Engineered with **Apple Clang C++20**, **Cocoa (AppKit/Foundation)**, **Scintilla Cocoa**, **Lexilla**, and **WebKit**, it adheres strictly to Apple's Human Interface Guidelines (HIG) while preserving Notepad++'s rich editing capabilities and full 94-language global localization.

---

## 🌟 Key Features

### 🌐 94 Languages Global UI Localization
- **Native 94-Language XML Support**:
  - Leverages authentic Notepad++ localization XML files (`PowerEditor/installer/nativeLang/*.xml`) parsed in real time via `pugixml`.
  - Switch languages on the fly under **Preferences (`⌘,`) > General > Display Language**.
  - Top 16 popular languages (`English`, `한국어`, `日本語`, `简体中文`, `繁體中文`, `Français`, `Deutsch`, `Español`, `Italiano`, `Русский`, `Português`, `Brazilian Portuguese`, `Nederlands`, `Polski`, `Türkçe`, `Tiếng Việt`) are prioritized at the top, followed by 78 alphabetical options.
- **Dynamic Real-Time UI Updates**:
  - **macOS Menu Bar**: All 11 top-level menus and submenu items translated dynamically.
  - **Find & Replace Bar (`NppFindBarView`)**: Labels, buttons, and match checkboxes.
  - **Side & Bottom Panels**: Explorer, Terminal, and Preview panel headers and tooltips.
  - **Column Editor Dialog (`NppColumnEditor`)**: Groupboxes, radices, and format options.
  - **Preferences Window (`NppPreferences`)**: 11 master categories and detail views.
  - **Status Bar (`StatusBar`)**: Line/col, selection range, encoding, and line ending indicators.
- **macOS Optimization & Session Persistence**:
  - Windows-specific accelerators (`(&F)`, `(&E)`, `&amp;`) are cleanly stripped for native macOS text rendering.
  - Selected language settings persist seamlessly in `session.json` across app launches.

---

### 📖 Help & Documentation System
- **Notepad++ Help Guide Dialog (`⇧⌘/` or F1)**:
  - Interactive manual accessible from **Help > Notepad++ Help Guide** or shortcut **`⇧⌘/`** (F1).
  - Quick tips for Column Mode shortcuts, 3-panel split views, encoding conversion, and macros.
- **High-Speed Responsive Tooltips**:
  - **0.05s instant display** with high-contrast **14pt typography** on toolbar buttons.
- **Comprehensive Project Documentation**:
  - [BUILD_MAC.md](BUILD_MAC.md): macOS build pipelines and automated test execution.
  - [ScintillaCocoaIME_en.md](ScintillaCocoaIME_en.md): Technical whitepaper on Scintilla Cocoa CJK/Korean IME bug resolution.
  - [CONTRIBUTING_en.md](CONTRIBUTING_en.md): Contribution guidelines and coding standards.

---

### 🔲 Column Mode & Column Editor (`⌥⌘C` / Option+Drag)
- **Column Mode Selection**:
  - **Rectangular Block Selection**: Hold `⌥` (Option) while dragging with mouse or use `⌥⇧` (Option+Shift) + arrow keys.
  - **Multi-Caret Typing & Multi-Column Paste**: Type across multiple lines simultaneously.
- **Column Editor Dialog**:
  - Shortcut: **`⌥⌘C`** (or Edit > `Column Editor...`).
  - **Text Insertion**: Prefix or insert strings across all selected lines.
  - **Number Sequence Insertion**: Initial number, increment, repeat count, radices (**Dec/Hex/Oct/Bin**), and padding format (**None / Leading Zeros / Spaces**).

---

### 🍏 Modern IDE 3-Panel Split View (VS Code Style Layout)
- **Primary Side Panel (Left - Finder-Style Explorer)**:
  - Toggle via toolbar icon (`sidebar.left`) or `⌥⌘1`.
  - Default directory is `~/` (Home) with automatic folder sync for active files.
  - Native macOS Finder system icons with smooth asynchronous lazy loading.
- **Bottom Panel (Bottom - Embedded Interactive Terminal)**:
  - Toggle via toolbar icon (`dock.rectangle`) or `⌥⌘2`.
  - Live `/bin/zsh` shell session with prompt `$ `, working directory tracking (`cd`), and history.
  - **`Open in Terminal.app`** quick action button.
- **Secondary Side Panel (Right - Live WebKit Preview)**:
  - Toggle via toolbar icon (`sidebar.right`) or `⌥⌘3`.
  - Real-time rendering synchronized with editor typing for Markdown (GFM), HTML, JSON, XML/SVG, C++, Python, and SQL.

---

### 🔄 Seamless Session Persistence & Restore
- **Instant State Serialization**:
  - Automatically records open file paths, caret/scroll coordinates, active tabs, panel states, and unsaved buffers to `session.json`.
- **Full Restoration on Launch**:
  - Restores exact window geometry, document hierarchy, and unsaved drafts without data loss.

---

### 🇰🇷 Scintilla Cocoa CJK / Korean IME Architecture
- **Flawless Syllable Composition & Progression**:
  - Adopts React Native PR #56082 State Guard (`mIsComposing`) architecture to isolate active IME composition sessions from disruptive UI redraws and background disk serialization.
  - Prevents in-place syllable overwriting, supports reverse backspace decomposition, Enter (Return) line breaking, and automatic mouse-click commit.
  - Read [ScintillaCocoaIME_en.md](ScintillaCocoaIME_en.md) for full technical analysis and code diffs.

---

### 📑 11 Full Menu Categories
1. **Notepad++**: About, Preferences (`⌘,`), Services, Hide (`⌘H`), Hide Others (`⌥⌘H`), Quit (`⌘Q`)
2. **File**: New (`⌘N`), Open (`⌘O`), Reload (`⌘R`), Save (`⌘S`), Save As (`⇧⌘S`), Save All (`⌥⌘S`), Close (`⌘W`), Close All (`⇧⌘W`), Reveal in Finder (`⇧⌘R`), Open in Terminal (`⌥⌘T`), Copy Paths
3. **Edit**: Undo (`⌘Z`), Redo (`⇧⌘Z`), Cut (`⌘X`), Copy (`⌘C`), Paste (`⌘V`), Select All (`⌘A`), Column Editor (`⌥⌘C`), Line Operations (Duplicate `⌘D`, Join `⌃J`, Move `⌥↑`/`⌥↓`, Sort, Remove Empty), Case Conversions (`⇧⌘U`/`⌘U`), Comment Toggle (`⌘/`)
4. **Search**: Find (`⌘F`), Find Next (`⌘G`), Find Prev (`⇧⌘G`), Replace (`⌥⌘F`), Go to Line (`⌘L`), Matching Brace (`⌘B`), Bookmarks (`⌘F2`, `F2`, `⇧F2`)
5. **View**: Toggle Explorer (`⌥⌘1`), Toggle Terminal (`⌥⌘2`), Toggle Preview (`⌥⌘3`), Zoom (`⌘+`/`⌘-`/`⌘0`), Word Wrap (`⌥⌘W`), Line Numbers, Whitespace symbols, Dark Mode (`⇧⌘D`)
6. **Encoding**: UTF-8 (Default), UTF-8 BOM, UTF-16 LE, UTF-16 BE, ANSI (CP1252), Korean (EUC-KR), Japanese (Shift-JIS), Chinese (Big5, GB2312), Line Endings (LF/CRLF/CR)
7. **Language**: C/C++, Python, JavaScript/TypeScript, HTML, XML, JSON, CSS, Markdown, SQL, Rust, Go, Java, Swift, Kotlin, PHP, YAML, Shell (24+ languages)
8. **Settings**: Preferences (`⌘,`), Style Configurator (7 authentic themes)
9. **Tools**: MD5 / SHA-256 Hash Generator (auto clipboard copy)
10. **Window**: Minimize, Zoom, Window management
11. **Help**: Notepad++ Help Guide (`⇧⌘/` or F1), About Notepad++

---

## 🚀 Quick Start & Build Instructions

### [Edition 1] Native C++/Scintilla Build
```bash
# 1. Build executable (bin/notepad++)
make -f Makefile.mac all

# 2. Run 66 automated unit tests (568 assertions)
make -f Makefile.mac test

# 3. Create standalone macOS application bundle (bin/Notepad++.app)
make -f Makefile.mac bundle

# 4. Launch Application
open bin/Notepad++.app
```

### [Edition 2] VS Code Architecture Build (`vscode/`)
```bash
# 1. Compile VS Code Edition
make -f Makefile.mac vscode-all

# 2. Launch in Standalone Electron Mode
make -f Makefile.mac vscode-run
```

---

## 🧪 Test & Verification Results

The automated test runner (`bin/npp_tests`) validates string conversions, POSIX file I/O, UTF-8/UTF-16/BOM codecs, `uchardet` encoding detection, `pugixml` serialization, Lexilla syntax lexers, buffer operations, tab drag reordering, and session persistence across 66 test cases:

```
================================================================================
  Test Execution Summary
================================================================================
  Total Tests:       66
  Passed:            66 (100% PASS)
  Failed:            0
  Total Assertions:  568
  Total Time:        124.72 ms
================================================================================
>>> ALL TESTS PASSED SUCCESSFULLY! <<<
```

---

## 📄 License

Notepad++ is distributed under the [GNU General Public License v3](LICENSE).
Ported to native macOS Cocoa front-end.
