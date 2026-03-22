# claude-cli-status-line

Get usage and what model is being used within the Claude CLI.

My buddy George had Claude create this plan to add a status line to the CLI.

<img width="923" height="282" alt="image" src="https://github.com/user-attachments/assets/a722e742-96b4-4db4-87e8-44a2a5e440ea" />


## Setup

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `bash` and `jq` available on your system (`brew install jq`)

There are three ways to set this up:

### Option 1 — Setup script (recommended)

```bash
./setup.sh
```

This copies the script to `~/.claude/` and merges the `statusLine` config into `~/.claude/settings.json`, preserving any existing settings.

### Option 2 — Manual

Copy the pre-built script to your `.claude` folder and register it in your settings:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
```

Then add the following to `~/.claude/settings.json` (create it if it doesn't exist):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

### Option 3 — Let Claude implement it

Open Claude Code in this repo and ask it to implement the plan:

```
claude "Implement the plan in plan/statusline.md"
```

This will create (or update) `~/.claude/statusline-command.sh` and configure `~/.claude/settings.json` to point to it.

### What it does

The status line displays the following segments at the bottom of the Claude CLI:

| Segment | Example | Color |
|---------|---------|-------|
| Context window | `[████░░░░░░] 25%` | Green/Yellow/Red |
| Model name | `Opus` | Cyan |
| Effort level | `default` | Magenta |
| Session cost | `$0.42` | Yellow |
| Duration | `12m34s` | Dim |
| Lines changed | `+156 -23` | Green/Red |
| Git branch | ` main` | Blue |
| Agent/Worktree | `[code-builder]` | Magenta |

### Verifying it works

After setup, test with mock JSON:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.23,"total_duration_ms":754000,"total_lines_added":50,"total_lines_removed":12},"output_style":{"name":"concise"},"workspace":{"current_dir":"'"$(pwd)"'"}}' | bash ~/.claude/statusline-command.sh
```
