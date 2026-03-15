Plan: Build Out Claude Code Status Line

 Context

 The user has an existing Claude Code status line script at ~/.claude/statusline-command.sh that displays three
  segments: a context window progress bar, model name, and effort level. The goal is to enhance it with
 additional useful segments while keeping it fast and readable. This plan is written so another person's agent
 can implement it independently.

 Current State

 File: ~/.claude/statusline-command.sh
 Config: ~/.claude/settings.json — statusLine.command points to the script
 Dependencies: bash, jq

 Current segments:
 1. Context window — 10-char progress bar, green/yellow/red by usage
 2. Model name — cyan text
 3. Effort level — magenta text

 Available JSON Input Fields

 The script receives JSON on stdin from Claude Code with these fields:

 ┌──────────────────────────────────────────────────────┬───────────────────┬───────────────────────┐
 │                        Field                         │       Type        │        Example        │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ model.display_name                                   │ string            │ "Opus"                │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ model.id                                             │ string            │ "claude-opus-4-6"     │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ context_window.used_percentage                       │ number            │ 25                    │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ context_window.context_window_size                   │ number            │ 200000                │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ context_window.current_usage.input_tokens            │ number            │ 50000                 │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ context_window.current_usage.output_tokens           │ number            │ 12000                 │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ context_window.current_usage.cache_read_input_tokens │ number            │ 8000                  │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ cost.total_cost_usd                                  │ number            │ 0.42                  │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ cost.total_duration_ms                               │ number            │ 120000                │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ cost.total_lines_added                               │ number            │ 156                   │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ cost.total_lines_removed                             │ number            │ 23                    │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ workspace.current_dir                                │ string            │ "/home/user/project"  │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ workspace.project_dir                                │ string            │ "/home/user/project"  │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ output_style.name                                    │ string            │ "default"             │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ version                                              │ string            │ "1.0.80"              │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ exceeds_200k_tokens                                  │ boolean           │ false                 │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ vim.mode                                             │ string (optional) │ "NORMAL"              │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ agent.name                                           │ string (optional) │ "code-builder"        │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ worktree.name                                        │ string (optional) │ "my-feature"          │
 ├──────────────────────────────────────────────────────┼───────────────────┼───────────────────────┤
 │ worktree.branch                                      │ string (optional) │ "worktree-my-feature" │
 └──────────────────────────────────────────────────────┴───────────────────┴───────────────────────┘

 Implementation Plan

 Step 1: Add session cost segment

 After the effort level segment, add a cost display:

 cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
 if [ -n "$cost" ]; then
   cost_str=$(printf '%b$%s%b' '\033[0;33m' "$(printf '%.2f' "$cost")" '\033[0m')
 else
   cost_str=""
 fi

 Display as $0.42 in yellow.

 Step 2: Add session duration segment

 Convert total_duration_ms to a human-readable format:

 duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
 if [ -n "$duration_ms" ]; then
   total_sec=$(( duration_ms / 1000 ))
   mins=$(( total_sec / 60 ))
   secs=$(( total_sec % 60 ))
   if [ "$mins" -gt 0 ]; then
     dur_str=$(printf '%b%dm%ds%b' '\033[2m' "$mins" "$secs" '\033[0m')
   else
     dur_str=$(printf '%b%ds%b' '\033[2m' "$secs" '\033[0m')
   fi
 else
   dur_str=""
 fi

 Display as 12m34s in dim text.

 Step 3: Add git branch segment (with caching)

 Git commands are slow — cache the result for 5 seconds:

 cache_file="/tmp/claude-statusline-git-$$"
 cache_age=999
 if [ -f "$cache_file" ]; then
   cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
 fi

 if [ "$cache_age" -ge 5 ]; then
   branch=$(git -C "$(echo "$input" | jq -r '.workspace.current_dir // "."')" rev-parse --abbrev-ref HEAD
 2>/dev/null || echo "")
   echo "$branch" > "$cache_file"
 else
   branch=$(cat "$cache_file")
 fi

 if [ -n "$branch" ]; then
   git_str=$(printf '%b %s%b' '\033[0;34m' "$branch" '\033[0m')
 else
   git_str=""
 fi

 Display as  main in blue (using a Unicode branch symbol).

 Step 4: Add lines changed segment

 Show net lines added/removed:

 added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
 removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
 if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
   lines_str=$(printf '%b+%s%b %b-%s%b' '\033[0;32m' "$added" '\033[0m' '\033[0;31m' "$removed" '\033[0m')
 else
   lines_str=""
 fi

 Display as +156 -23 in green/red.

 Step 5: Show agent/worktree name when active

 agent=$(echo "$input" | jq -r '.agent.name // empty')
 worktree=$(echo "$input" | jq -r '.worktree.name // empty')
 if [ -n "$agent" ]; then
   agent_str=$(printf '%b[%s]%b' '\033[0;35m' "$agent" '\033[0m')
 elif [ -n "$worktree" ]; then
   agent_str=$(printf '%b[wt:%s]%b' '\033[0;35m' "$worktree" '\033[0m')
 else
   agent_str=""
 fi

 Step 6: Assemble final output

 Use a separator character (e.g., | dimmed, or    double-space) between segments. Only include non-empty
 segments:

 # Build segment array, filter empties, join with separator
 sep=$(printf '%b | %b' '\033[2m' '\033[0m')
 output=""
 for seg in "$ctx_str" "$model_str" "$effort_str" "$cost_str" "$dur_str" "$lines_str" "$git_str" "$agent_str";
 do
   if [ -n "$seg" ]; then
     if [ -n "$output" ]; then
       output="${output}${sep}${seg}"
     else
       output="$seg"
     fi
   fi
 done
 printf ' %s ' "$output"

 Final segment order (left to right):

 [████░░░░░░] 25%  |  Opus  |  default  |  $0.42  |  12m34s  |  +156 -23  |   main  |  [code-builder]

 Files to Modify

 - ~/.claude/statusline-command.sh — the only file; rewrite with all segments

 Verification

 1. Unit test with mock JSON:
 echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":42},"cost":{"total_cost_usd":1.23,"
 total_duration_ms":754000,"total_lines_added":50,"total_lines_removed":12},"output_style":{"name":"concise"},"
 workspace":{"current_dir":"'"$(pwd)"'"}}' | bash ~/.claude/statusline-command.sh
 1. Expected: all segments render with correct colors and values.
 2. Test with minimal JSON:
 echo '{}' | bash ~/.claude/statusline-command.sh
 2. Expected: graceful fallback — shows the context bar placeholder, no crashes.
 3. Test with agent/worktree fields:
 echo '{"agent":{"name":"code-builder"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":10}
 ,"output_style":{"name":"default"},"cost":{"total_cost_usd":0,"total_duration_ms":5000,"total_lines_added":0,"
 total_lines_removed":0}}' | bash ~/.claude/statusline-command.sh
 3. Expected: [code-builder] segment appears at the end.
 4. Performance: Run time echo '...' | bash ~/.claude/statusline-command.sh — should complete in under 50ms
 (excluding git on first run).
 5. Live test: Open Claude Code and verify the status line renders correctly at the bottom of the terminal