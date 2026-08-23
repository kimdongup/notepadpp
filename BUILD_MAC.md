# Building Notepad++ for macOS

This document provides complete instructions for building, packaging, and testing **Notepad++ on macOS** using the native Cocoa / Clang toolchain.

---

## 1. System Requirements

- **Operating System**: macOS 10.15 (Catalina) or later (Apple Silicon M1/M2/M3/M4 and Intel x86_64 supported)
- **Compiler**: Apple Clang / LLVM supporting **C++20** and Objective-C++ (`-fobjc-arc`)
- **Build Tools**: GNU Make (`make`)
- **System Frameworks**:
  - `Cocoa.framework` (AppKit, Foundation)
  - `QuartzCore.framework`
  - `CoreText.framework`
  - `CoreFoundation.framework`

To install the required command-line tools:
```bash
xcode-select --install
```

---

## 2. Architecture Overview

The macOS port of Notepad++ utilizes a clean native Cocoa architecture:
- **UI & Application Controller** (`PowerEditor/src/mac_main.mm`):
  - Native Cocoa `NSApplication`, `NSWindow`, and `NSToolbar` (Unified titlebar style)
  - macOS standard defaults: Unix (`LF`) line endings, UTF-8 without BOM, SF Mono font
  - Interactive Window Titlebar Proxy Icon and Document Edited (`documentEdited`) indicator
  - Native Preferences Sheet (`⌘,`) and standard HIG keybindings (`⌘S`, `⇧⌘Z`, `⌘F`, `⌥⌘F`, `⌘E`, `⌘/`)
  - Drag-and-drop file opening directly from Finder (`NSPasteboardTypeFileURL`)
  - Multi-tab document management via custom `NppTabBarView`
  - Integrated Scintilla view container (`ScintillaView`)
  - 7-cell segmented status bar with instant encoding and EOL conversion
- **Scintilla Cocoa Platform** (`scintilla/cocoa/`):
  - Quartz / CoreText rendering (`PlatCocoa.mm`, `ScintillaCocoa.mm`)
  - Native mouse, retina display, and keyboard event handling
- **Lexilla Lexers** (`lexilla/`):
  - 100+ programming language syntax highlighters compiled statically
- **Encoding & XML Support**:
  - `uchardet` universal charset detection
  - `pugixml` for XML configuration and styling schemas
  - `Utf8_16.cpp` and `EncodingMapper.cpp` for multi-encoding conversions (UTF-8, UTF-16 LE/BE, ANSI codepages)
- **macOS Compatibility Shim** (`PowerEditor/src/win_shim/`, `PowerEditor/src/mac_compat.cpp`):
  - POSIX / Mach-O dynamic binary resolution
  - macOS standard folder mapping (`CSIDL_APPDATA` -> `~/Library/Application Support/Notepad++`, `~/Documents`, `~/Desktop`)
  - Win32 types, file attributes, timers, and clipboard mapping to macOS Cocoa APIs

---

## 3. Build Instructions

All build operations are driven by `Makefile.mac` at the repository root.

### A. Build the Binary
To compile the core executable `bin/notepad++`:
```bash
make -f Makefile.mac
```
Or explicitly:
```bash
make -f Makefile.mac all
```
The output binary will be created at `bin/notepad++`.

### B. Package the macOS Application Bundle (`Notepad++.app`)
To create a standalone macOS `.app` bundle ready to run or install in `/Applications`:
```bash
make -f Makefile.mac bundle
```

This creates `bin/Notepad++.app` with the following structure:
```
bin/Notepad++.app/
└── Contents/
    ├── Info.plist               # App metadata, bundle ID, document types
    ├── PkgInfo                  # Bundle signature (APPL????)
    ├── MacOS/
    │   ├── Notepad++            # Main executable
    │   └── notepad++            # Executable alias
    └── Resources/
        ├── langs.model.xml      # Language definitions
        ├── stylers.model.xml    # Themes and syntax styles
        ├── userDefineLangs/     # Preinstalled UDLs (Markdown, etc.)
        └── *.png                # Cocoa cursor and infobar assets
```

### C. Run the Unit Test Suite
To build and execute the automated test runner (`bin/npp_tests`):
```bash
make -f Makefile.mac test
```

The test runner validates:
1. **Compatibility Layer (`test_mac_compat.cpp`)**:
   - UTF-8 / UTF-16 / WideChar conversions
   - POSIX file operations, timestamps, file attributes
   - Win32 API shims (CRITICAL_SECTION, timers, clipboard, system metrics)
   - Dynamic executable resolution via `_NSGetExecutablePath`
2. **Character Encodings (`test_encoding.cpp`)**:
   - BOM detection (UTF-8, UTF-16 LE, UTF-16 BE)
   - `uchardet` encoding identification
   - Codepage conversions (Windows-1252, Shift-JIS, Big5, GBK, etc.)
3. **XML & Configuration (`test_xml.cpp`)**:
   - `pugixml` parsing and manipulation
   - `langs.model.xml` and `stylers.model.xml` loading
4. **Lexilla & Scintilla Core (`test_lexilla_scintilla.cpp`)**:
   - Lexer instantiation for C++, Python, HTML, XML, Rust, Markdown
   - Property setting and keyword list population
5. **Document Buffer Management (`test_buffer_text.cpp`)**:
   - Multi-document state tracking, undo/redo, modified flags, EOL normalization

### D. Clean Build Artifacts
To remove all intermediate object files and compiled binaries:
```bash
make -f Makefile.mac clean
```

---

## 4. Running the Application

- **From Terminal (CLI mode)**:
  ```bash
  ./bin/notepad++ [file_to_open ...]
  ```

- **Launching the Application Bundle**:
  ```bash
  open bin/Notepad++.app
  ```
  Or drag `bin/Notepad++.app` into `/Applications`.

---

## 5. Summary of Makefile.mac Targets

| Target | Description |
| :--- | :--- |
| `make -f Makefile.mac` | Builds the `bin/notepad++` binary (default target) |
| `make -f Makefile.mac bundle` | Creates the full `bin/Notepad++.app` macOS bundle |
| `make -f Makefile.mac test` | Compiles and executes the automated unit test suite |
| `make -f Makefile.mac clean` | Cleans `build_mac/` and `bin/` directories |
| `make -f Makefile.mac help` | Displays help message with available targets |
