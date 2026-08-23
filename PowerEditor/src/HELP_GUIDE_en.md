# 📘 Notepad++ for macOS User Guide & Feature Manual

[![Notepad++ macOS](https://img.shields.io/badge/Notepad%2B%2B-macOS%20Native-brightgreen.svg)](https://github.com/notepad-plus-plus/notepad-plus-plus)
[![Engine](https://img.shields.io/badge/Editor-Scintilla%20%2B%20Lexilla-blue.svg)](https://www.scintilla.org/)
[![UI](https://img.shields.io/badge/GUI-Apple%20Cocoa%20%2B%20WebKit-orange.svg)](https://developer.apple.com/)

**Notepad++ for macOS** combines a high-performance Scintilla/Lexilla C++20 editor core with modern Apple Cocoa and WebKit preview engines into a native text and source code editor for macOS.

---

## 🚀 macOS Shortcut Cheatsheet

| Category | Feature | macOS Shortcut | Description |
| :--- | :--- | :--- | :--- |
| **File** | New / Open File | `⌘N` / `⌘O` | Create a new tab or open existing document |
| | Save / Save All | `⌘S` / `⌥⌘S` | Save active file or all open documents |
| | Close Tab / Switch Tab | `⌘W` / `⌥⌘←` `⌥⌘→` | Close current tab or navigate tabs |
| | Reveal in Finder | `⌘R` | Select file's containing folder in Finder |
| **Edit** | Rectangular Column Mode | `⌥` (Option) + Drag | Edit across multiple rectangular lines simultaneously |
| | Column Editor | `⌥⌘C` | Insert number sequences and text prefixes |
| | Join Lines | `⌘J` | Join current line with next line |
| | Split Lines | `⌥⌘J` | Split lines at specified column boundary |
| | Duplicate / Toggle Comment | `⌘D` / `⌘/` | Duplicate line and toggle `//` comment |
| | Convert Case | `⇧⌘U` / `⌘U` | Convert to UPPERCASE / lowercase |
| **Search** | Find / Replace Bar | `⌘F` / `⌥⌘F` | Toggle interactive search/replace panel |
| | Find Next / Previous | `⌘G` / `⇧⌘G` | Navigate matching occurrences |
| | Toggle Bookmark | `⌘F2` (or Margin click) | Set or toggle line bookmark |
| | Next / Previous Bookmark | `F2` / `⇧F2` | Jump between bookmarks |
| | Clear All Bookmarks | `⇧⌘F2` | Clear all bookmarks in document |
| **Panels** | Left File Explorer | `⌘B` | Toggle project folder tree |
| | Bottom Terminal | `⌃\`` or `⌘\` | Toggle interactive zsh shell console |
| | Right Live Preview | `⇧⌘P` | Toggle live GFM Markdown/HTML/JSON preview |
| **View** | Toggle Dark Mode | `⇧⌘D` | Toggle light/dark appearance |
| | Word Wrap Toggle | `⌥⌘W` | Toggle visual word wrapping |
| | Fold / Unfold All Code | `⌥⌘[` / `⌥⌘]` | Fold or expand all code blocks |
| | Fold Current Block | `⌘[` | Fold code block at cursor |

---

## 📌 Top Menu Details & Practical Examples

### 1. 📁 File Menu
- **New (`⌘N`)**: Creates a new untitled buffer (`new 1`, `new 2`...).
- **Open... (`⌘O`)**: Opens native macOS file chooser dialog.
- **Save (`⌘S`) / Save As... (`⇧⌘S`) / Save All (`⌥⌘S`)**: Saves modifications to disk.
- **Close (`⌘W`) / Close All**: Closes active tab or all tabs (prompts for unsaved changes).
- **Reveal in Finder (`⌘R`)**: Opens the containing directory in Finder.
- **Copy Full Path / Copy Filename / Copy Directory Path**: Copies path information to clipboard.

---

### 2. ✏️ Edit Menu
- **Line Operations**:
  - **Duplicate Current Line (`⌘D`)**: Duplicates active line directly below.
  - **Toggle Line Comment (`⌘/`)**: Comments or uncomments active line with `//`.
  - **Join Lines (`⌘J`)**: Merges multiple lines into a single line.
  - **Split Lines (`⌥⌘J`)**: Splits long lines to wrap column width.
  - **Remove Empty Lines**: Deletes empty lines across the document.
  - **Trim Trailing Space**: Strips trailing whitespace and tabs.
- **Column Mode & Column Editor (`⌥⌘C`)**:
  - **Column Mode**: Hold `⌥` (Option) while dragging mouse to select a rectangular block.
  - **Keyboard Column Selection**: `⌥⇧` + Arrow keys (`Option + Shift + ↑/↓/←/→`).
  - **Multi-Caret Typing**: Typing inserts text across all lines in the block simultaneously.
  - **Column Editor (`⌥⌘C`)**: Batch insert text or incrementing sequences (`1, 2, 3...`) in Dec/Hex/Bin/Oct with custom zero-padding.
- **Convert Case**:
  - **UPPERCASE (`⇧⌘U`)**: Converts selected text to uppercase.
  - **lowercase (`⌘U`)**: Converts selected text to lowercase.

---

### 3. 🔍 Search Menu
- **Find (`⌘F`) / Replace (`⌥⌘F`)**:
  - Opens modern search panel with Match Case, Whole Word, and Regular Expressions.
  - Press `Enter` for next match, `Shift+Enter` for previous match, `Esc` to dismiss.
- **Bookmarks**:
  - **Toggle Bookmark (`⌘F2`)**: Sets blue arrow bookmark in margin.
  - **Next / Prev Bookmark (`F2` / `⇧F2`)**: Jumps between bookmarked positions.
  - **Clear All Bookmarks (`⇧⌘F2`)**: Removes all bookmarks.

---

### 4. 👁️ View Menu
- **3 Docking Panels**:
  - **Primary Side Bar (Explorer `⌘B`)**: Tree navigation, file creation, deletion.
  - **Bottom Panel (Terminal `⌃\`` or `⌘\`)**: Embedded zsh with ANSI color support.
  - **Secondary Side Bar (Live Preview `⇧⌘P`)**: Live WebKit GFM Markdown/HTML renderer.
- **Code Folding**:
  - **Fold Current Level (`⌘[`)**: Toggles folding of block under cursor.
  - **Fold All (`⌥⌘[`) / Unfold All (`⌥⌘]`)**: Folds/unfolds all functions and classes.
- **Dark Mode (`⇧⌘D`)**:
  - Authentic themes: Monokai, Dracula, Solarized Dark, Solarized Light, Obsidian.
