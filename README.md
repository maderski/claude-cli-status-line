# claude-cli-status-line

Get usage and what model is being used within the Claude CLI.

George had Claude create this plan to add a status line to the CLI.

<img width="923" height="282" alt="image" src="https://github.com/user-attachments/assets/a722e742-96b4-4db4-87e8-44a2a5e440ea" />


## Setup

To have Claude execute the status line plan, open Claude Code in this repo and ask it to implement the `statusline.md` file:

```
claude "Implement the plan in statusline.md"
```

This will create (or update) `~/.claude/statusline-command.sh` and configure `~/.claude/settings.json` to point to it.

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- `bash` and `jq` available on your system

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

After implementation, test with mock JSON:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.23,"total_duration_ms":754000,"total_lines_added":50,"total_lines_removed":12},"output_style":{"name":"concise"},"workspace":{"current_dir":"'"$(pwd)"'"}}' | bash ~/.claude/statusline-command.sh
```
