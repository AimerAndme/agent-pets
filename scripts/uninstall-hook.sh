#!/bin/sh
set -eu

INSTALL_DIR="${HOME}/.claude-pets/bin"
if [ -f "$INSTALL_DIR/claude-pets-hook" ]; then
  rm "$INSTALL_DIR/claude-pets-hook"
  echo "Removed $INSTALL_DIR/claude-pets-hook"
else
  echo "Hook Adapter is not installed"
fi

echo "Remove the Claude Pets hook entries from ~/.claude/settings.json manually."
