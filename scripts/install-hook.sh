#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALL_DIR="${HOME}/.claude-pets/bin"
CLAUDE_DIR="${HOME}/.claude"

mkdir -p "$INSTALL_DIR"

echo "Building Claude Pets Hook Adapter..."
swift build --package-path "$ROOT_DIR" --product claude-pets-hook
cp "$ROOT_DIR/.build/debug/claude-pets-hook" "$INSTALL_DIR/claude-pets-hook"
chmod 755 "$INSTALL_DIR/claude-pets-hook"

echo ""
echo "Hook Adapter installed at: $INSTALL_DIR/claude-pets-hook"
echo ""
echo "Add the following hook configuration to: $CLAUDE_DIR/settings.json"
echo ""
sed "s|\$HOME|$HOME|g" "$ROOT_DIR/claude-pets-plugin/hooks/hooks.json"
echo ""
echo "The script prints configuration but does not overwrite settings.json."
