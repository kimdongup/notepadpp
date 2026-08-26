# AGENTS.md

Fork of Notepad++ (upstream: Windows/Win32) being ported to macOS. Two **independent editions** live here:

1. **Native Cocoa edition** (default) — C++20 + Scintilla/Lexilla, built by `Makefile.mac`.
2. **VS Code edition** — a full VS Code source tree in `vscode/` plus custom extensions. See `vscode/AGENTS.md` → `vscode/.github/copilot-instructions.md` before touching anything under `vscode/`.

## Build & Test

There is no root `Makefile`; `-f Makefile.mac` is mandatory:

```bash
make -f Makefile.mac all      # -> bin/notepad++
make -f Makefile.mac test     # builds & runs bin/npp_tests (10 suites)
make -f Makefile.mac bundle   # -> bin/Notepad++.app (ad-hoc signed)
make -f Makefile.mac clean    # removes build_mac/ and bin/
```

- VS Code edition: `make -f Makefile.mac vscode-all` (= `scripts/build_vscode.sh`), run with `cd vscode && npm run electron`. Requires Node >= 20.
- `bin/` and `build_mac/` are gitignored artifacts — never commit them.

## Deploy & Push Workflow (standing user instruction)

After finishing any code change in this repo, always:

1. Verify: `make -f Makefile.mac test`
2. Bundle: `make -f Makefile.mac bundle`
3. Install: `rm -rf /Applications/Notepad++.app && cp -R bin/Notepad++.app /Applications/`
4. Commit (conventional style) and push to `main`: `git push origin main`.

## Architecture (non-obvious parts)

- The macOS app entrypoint is `PowerEditor/src/mac_main.mm` (~7k lines): a self-contained Cocoa/AppKit frontend. It does **not** link the original Win32 core (`Notepad_plus.cpp`, `NppCommands.cpp`, etc.) — those upstream sources stay in-tree for reference only.
- `PowerEditor/src/win_shim/` holds header-only Win32 API stubs so upstream Windows code compiles on clang; `mac_compat.{h,cpp}` maps Win32 types/APIs to POSIX/Cocoa. Platform fixes go in these two places, not by editing upstream logic ad hoc.
- Vendored deps are in-tree, built from source: `scintilla/`, `lexilla/`, `PowerEditor/src/uchardet/`, `PowerEditor/src/pugixml/`. Don't expect system or package-manager versions.
- 94 localization XMLs come from `PowerEditor/installer/nativeLang/` (upstream assets); UI strings are parsed via pugixml at runtime.

## Testing

- Custom framework: `PowerEditor/Test/test_framework.h` (no gtest/catch).
- Test `.cpp` files are **explicitly listed** in `Makefile.mac` `TEST_SRCS` — adding a test file requires editing the Makefile too.
- CI (`.github/workflows/CI_build.yml`) builds upstream Windows targets only; the macOS port has no CI. Verify locally with `make -f Makefile.mac test`.

## Conventions (from CONTRIBUTING.md / git history)

- Tabs, not spaces; Allman braces (`{` on its own line).
- Members prefixed `_`; methods camelCase; classes PascalCase; C++ casts only; `//` comments.
- Commits follow `fix(scope): ...` / `feat(scope): ...` per existing history.
- Root docs are Korean-first (`README.md`) with `_en.md` counterparts — update both when changing user-facing docs.
