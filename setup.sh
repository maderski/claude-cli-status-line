#!/usr/bin/env bash
set -e

# Check prerequisites
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install it with: brew install jq" >&2
  exit 1
fi

CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUS_LINE_COMMAND="bash ~/.claude/statusline-command.sh"

# Copy script
mkdir -p "$CLAUDE_DIR"
cp "$(dirname "$0")/statusline-command.sh" "$DEST"
chmod +x "$DEST"
echo "Copied statusline-command.sh to $DEST"

# Merge statusLine into settings.json
if [ -f "$SETTINGS" ]; then
  jq '. + {"statusLine": {"command": "'"$STATUS_LINE_COMMAND"'"}}' \
    "$SETTINGS" > /tmp/claude-settings-tmp.json \
    && mv /tmp/claude-settings-tmp.json "$SETTINGS"
  echo "Updated $SETTINGS"
else
  printf '{\n  "statusLine": {\n    "command": "%s"\n  }\n}\n' "$STATUS_LINE_COMMAND" > "$SETTINGS"
  echo "Created $SETTINGS"
fi

# Verify
echo ""
echo "=== Verification ==="
ls -la "$DEST"
cat "$SETTINGS"
