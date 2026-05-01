#!/usr/bin/env bash
set -e

# Check prerequisites
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install it with: brew install jq" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pull latest if this is a git repo (makes re-running setup.sh act as an update)
if git -C "$SCRIPT_DIR" rev-parse --git-dir &>/dev/null; then
  echo "Pulling latest changes..."
  git -C "$SCRIPT_DIR" pull --ff-only || echo "Warning: git pull failed, continuing with local version"
fi
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUS_LINE_COMMAND="bash \"$HOME/.claude/statusline-command.sh\""
TMP_SETTINGS="/tmp/claude-settings-tmp.json"

trap 'rm -f "$TMP_SETTINGS"' EXIT

# Copy script
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/statusline-command.sh" "$DEST"
chmod +x "$DEST"
echo "Copied statusline-command.sh to $DEST"

# Merge statusLine into settings.json
if [ -f "$SETTINGS" ]; then
  jq --arg status_line_command "$STATUS_LINE_COMMAND" \
    '.statusLine = ((.statusLine // {}) + {"type": "command", "command": $status_line_command})' \
    "$SETTINGS" > "$TMP_SETTINGS" \
    && mv "$TMP_SETTINGS" "$SETTINGS"
  echo "Updated $SETTINGS"
else
  printf '{\n  "statusLine": {\n    "type": "command",\n    "command": "%s"\n  }\n}\n' "$STATUS_LINE_COMMAND" > "$SETTINGS"
  echo "Created $SETTINGS"
fi

# Verify
echo ""
echo "=== Verification ==="
ls -la "$DEST"
cat "$SETTINGS"
