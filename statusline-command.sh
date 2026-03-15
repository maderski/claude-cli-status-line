#!/usr/bin/env bash
# Claude Code status line

input=$(cat)

# --- Context window ---
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
pct_int=${pct%.*}
filled=$(( pct_int / 10 ))
empty=$(( 10 - filled ))
bar=""
for i in $(seq 1 $filled); do bar="${bar}█"; done
for i in $(seq 1 $empty);  do bar="${bar}░"; done

if   [ "$pct_int" -ge 80 ]; then color='\033[0;31m'
elif [ "$pct_int" -ge 50 ]; then color='\033[0;33m'
else                              color='\033[0;32m'
fi
ctx_str=$(printf '%b[%s] %s%%%b' "$color" "$bar" "$pct_int" '\033[0m')

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')
if [ -n "$model" ]; then
  model_str=$(printf '%b%s%b' '\033[0;36m' "$model" '\033[0m')
else
  model_str=""
fi

# --- Effort ---
effort=$(echo "$input" | jq -r '.output_style.name // empty')
if [ -n "$effort" ]; then
  effort_str=$(printf '%b%s%b' '\033[0;35m' "$effort" '\033[0m')
else
  effort_str=""
fi

# --- Cost ---
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [ -n "$cost" ]; then
  cost_str=$(printf '%b$%s%b' '\033[0;33m' "$(printf '%.2f' "$cost")" '\033[0m')
else
  cost_str=""
fi

# --- Duration ---
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

# --- Lines changed ---
added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
  lines_str=$(printf '%b+%s%b %b-%s%b' '\033[0;32m' "$added" '\033[0m' '\033[0;31m' "$removed" '\033[0m')
else
  lines_str=""
fi

# --- Git branch (cached 5s) ---
cache_file="/tmp/claude-statusline-git-$$"
cache_age=999
if [ -f "$cache_file" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
fi

if [ "$cache_age" -ge 5 ]; then
  branch=$(git -C "$(echo "$input" | jq -r '.workspace.current_dir // "."')" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  echo "$branch" > "$cache_file"
else
  branch=$(cat "$cache_file")
fi

if [ -n "$branch" ]; then
  git_str=$(printf '%b %s%b' '\033[0;34m' "$branch" '\033[0m')
else
  git_str=""
fi

# --- Agent / worktree ---
agent=$(echo "$input" | jq -r '.agent.name // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')
if [ -n "$agent" ]; then
  agent_str=$(printf '%b[%s]%b' '\033[0;35m' "$agent" '\033[0m')
elif [ -n "$worktree" ]; then
  agent_str=$(printf '%b[wt:%s]%b' '\033[0;35m' "$worktree" '\033[0m')
else
  agent_str=""
fi

# --- Assemble ---
sep=$(printf '%b | %b' '\033[2m' '\033[0m')
output=""
for seg in "$ctx_str" "$model_str" "$effort_str" "$cost_str" "$dur_str" "$lines_str" "$git_str" "$agent_str"; do
  if [ -n "$seg" ]; then
    if [ -n "$output" ]; then
      output="${output}${sep}${seg}"
    else
      output="$seg"
    fi
  fi
done
printf ' %s ' "$output"
