# Claude CLI Status Line

A compact status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows context usage, model, effort, cost, duration, changed lines, Git branch, and agent or worktree information.

<img width="923" height="282" alt="Claude Code status line showing context usage, model, cost, duration, changed lines, and Git branch" src="https://github.com/user-attachments/assets/a722e742-96b4-4db4-87e8-44a2a5e440ea" />

## What It Shows

| Segment | Example | Display |
| --- | --- | --- |
| Context window | `[████░░░░░░] 42%` | Green below 50%, yellow from 50%, red from 80% |
| Model | `Opus` | Cyan |
| Effort level | `default` | Magenta |
| Session cost | `$1.23` | Yellow |
| Duration | `12m34s` | Dim |
| Lines changed | `+50 -12` | Green/red |
| Git branch | `main` | Blue |
| Agent or worktree | `[code-builder]` or `[wt:feature]` | Magenta |

Unavailable values are omitted automatically. The Git branch is cached for five seconds per workspace to keep prompt rendering fast.

## Installation

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Bash, `git`, and `jq`

On macOS, install `jq` with Homebrew:

```bash
brew install jq
```

### Setup Script (Recommended)

Clone the repository and run the installer:

```bash
git clone https://github.com/maderski/claude-cli-status-line.git
cd claude-cli-status-line
./setup.sh
```

The installer:

- Copies `statusline-command.sh` to `~/.claude/statusline-command.sh`
- Makes the installed script executable
- Adds or updates `statusLine` in `~/.claude/settings.json`
- Preserves the rest of your existing Claude Code settings

Restart Claude Code after installation if the status line does not appear immediately.

### Updating

Run the installer again from the cloned repository:

```bash
cd claude-cli-status-line
./setup.sh
```

When the directory is a Git repository, the installer first attempts a fast-forward-only pull and then installs the available local version. If the pull fails, installation continues with the current checkout.

### Manual Installation

Copy the script into your Claude Code configuration directory:

```bash
mkdir -p ~/.claude
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Then add `statusLine` to `~/.claude/settings.json`, preserving any other settings already in the file:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"/Users/YOUR_USERNAME/.claude/statusline-command.sh\""
  }
}
```

### Let Claude Code Implement the Plan

You can also open Claude Code in this repository and ask it to implement the original plan:

```bash
claude "Implement the plan in plan/statusline.md"
```

This creates or updates the status-line script and configures `~/.claude/settings.json` to use it.

## Verification

After installation, send a mock Claude Code payload to the script:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.23,"total_duration_ms":754000,"total_lines_added":50,"total_lines_removed":12},"output_style":{"name":"concise"},"workspace":{"current_dir":"'"$(pwd)"'"}}' | bash ~/.claude/statusline-command.sh
```

The output includes ANSI color codes, so run the command in a terminal to see the formatted status line.

## Testing

Install [bats-core](https://github.com/bats-core/bats-core), then run:

```bash
brew install bats-core
make test
```

Or invoke Bats directly:

```bash
bats tests/statusline.bats
```

The suite covers context rendering and thresholds, model resolution, localized and scientific cost formats, duration and line formatting, Git branch caching, agent/worktree display, malformed inputs, and output assembly.

## Background

The project started from a status-line implementation plan created with Claude for my buddy George. The original plan is available at [`plan/statusline.md`](plan/statusline.md).
