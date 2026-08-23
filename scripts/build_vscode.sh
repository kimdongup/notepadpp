#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VSCODE_DIR="$ROOT_DIR/vscode"
OUT_APP_DIR="$ROOT_DIR/bin/vscode_app"

echo "================================================================================"
echo "  Building Notepad++ (VS Code Architecture Edition) for macOS"
echo "================================================================================"

mkdir -p "$OUT_APP_DIR"

cd "$VSCODE_DIR"

echo "==> Compiling Notepad++ Core extension (Column Editor, Panels, Cryptography)..."
npx tsc -p extensions/notepadplus-core/tsconfig.json

echo "==> Compiling VS Code client core..."
npm run compile-client

echo "==> Preparing Notepad++ App Bundle..."
# In development / standalone launcher mode:
# Creates / updates the standalone application launch configuration
if [ -d "$VSCODE_DIR/.build/electron" ]; then
    echo "==> Electron binary ready: $VSCODE_DIR/.build/electron"
fi

echo "================================================================================"
echo "  Notepad++ (VS Code Edition) compilation successful!"
echo "  To launch: cd vscode && npm run electron"
echo "================================================================================"
