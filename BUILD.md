# Building Notepad++

This repository has been ported to macOS with native Cocoa UI, Scintilla Cocoa platform layer, Lexilla lexers, and POSIX compatibility.

For comprehensive macOS build instructions, please refer to:
👉 **[BUILD_MAC.md](BUILD_MAC.md)**

---

## Quick Start (macOS)

### 1. Build Notepad++ Executable
```bash
make -f Makefile.mac
```

### 2. Package macOS Application Bundle (`Notepad++.app`)
```bash
make -f Makefile.mac bundle
```

### 3. Run Automated Unit Test Suite
```bash
make -f Makefile.mac test
```

### 4. Clean Build Artifacts
```bash
make -f Makefile.mac clean
```

---

*Note: Legacy Windows MSVC solutions and GCC makefiles have been deprecated and cleaned up for the macOS native architecture.*
