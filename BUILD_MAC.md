# Building Notepad++ for macOS

This document provides complete instructions for building, packaging, and testing **Notepad++ on macOS** across both supported architectures:
1. **Native Cocoa / C++20 Scintilla Edition** (Default ultra-lightweight native build)
2. **VS Code Architecture Edition** (Electron + Monaco Editor + Notepad++ Core Extension & Themes)

---

## 1. System Requirements

- **Operating System**: macOS 10.15 (Catalina) or later (Apple Silicon M1/M2/M3/M4 and Intel x86_64 supported)
- **Compiler**: Apple Clang / LLVM supporting **C++20** and Objective-C++ (`-fobjc-arc`)
- **Build Tools**: GNU Make (`make`), Node.js (>= 20.x), npm
- **System Frameworks**:
  - `Cocoa.framework` (AppKit, Foundation)
  - `QuartzCore.framework`
  - `CoreText.framework`
  - `CoreFoundation.framework`
  - `WebKit.framework`

---

## 2. Edition 1: Native C++20 / Scintilla Build (Default)

### A. Build the Native Binary
```bash
make -f Makefile.mac all
```

### B. Run the 49 Unit Tests
```bash
make -f Makefile.mac test
```

### C. Package Native macOS Application Bundle (`Notepad++.app`)
```bash
make -f Makefile.mac bundle
```
The output will be created at `bin/Notepad++.app`.

---

## 3. Edition 2: VS Code Architecture Build (`vscode/`)

The VS Code architecture port provides the full Monaco Editor engine, extension ecosystem, and integrated terminal packaged with custom Notepad++ features (`extensions/notepadplus-core`) and 7 authentic color themes (`extensions/theme-notepadplus`).

### A. Compile VS Code Architecture Edition
```bash
make -f Makefile.mac vscode-all
```
*(Or run `./scripts/build_vscode.sh`)*

### B. Launch in Standalone Development Mode
```bash
make -f Makefile.mac vscode-run
```

---

## 4. Summary of Makefile.mac Targets

| Target | Description |
| :--- | :--- |
| `make -f Makefile.mac all` | Builds native C++/Scintilla `bin/notepad++` binary (default) |
| `make -f Makefile.mac test` | Runs the 49 automated unit tests (394 assertions) |
| `make -f Makefile.mac bundle` | Creates native standalone `bin/Notepad++.app` bundle |
| `make -f Makefile.mac vscode-all` | Compiles the VS Code edition in `vscode/` |
| `make -f Makefile.mac vscode-run` | Launches the VS Code edition in standalone Electron mode |
| `make -f Makefile.mac clean` | Cleans `build_mac/` and `bin/` build artifacts |
| `make -f Makefile.mac help` | Displays help message with available targets |
