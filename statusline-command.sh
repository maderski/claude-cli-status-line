#!/usr/bin/env bash
# Claude Code status line

input=$(cat)

# Parse all fields in a single jq invocation
{
  read -r pct
  read -r effort
  read -r cost
  read -r duration_ms
  read -r added
  read -r removed
  read -r current_dir
  read -r agent
  read -r worktree
  read -r model_payload
} < <(echo "$input" | jq -r '
  (.context_window.used_percentage // 0),
  (.output_style.name // ""),
  (if (.cost.total_cost_usd // 0) > 0 then (.cost.total_cost_usd | tostring) else "" end),
  (.cost.total_duration_ms // ""),
  (.cost.total_lines_added // 0 | floor),
  (.cost.total_lines_removed // 0 | floor),
  (.workspace.current_dir // "."),
  (.agent.name // ""),
  (.worktree.name // ""),
  (.model.display_name // "")
')

# --- Context window ---
pct_int=${pct%.*}
pct_int=${pct_int:-0}
filled=$(( pct_int / 10 ))
empty=$(( 10 - filled ))
bar=""
for (( i = 0; i < filled; i++ )); do bar="${bar}█"; done
for (( i = 0; i < empty;  i++ )); do bar="${bar}░"; done

if   [ "$pct_int" -ge 80 ]; then color='\033[0;31m'
elif [ "$pct_int" -ge 50 ]; then color='\033[0;33m'
else                              color='\033[0;32m'
fi
ctx_str=$(printf '%b[%s] %s%%%b' "$color" "$bar" "$pct_int" '\033[0m')

# --- Model ---
settings_model=$(jq -r '.model // empty' ~/.claude/settings.json 2>/dev/null)
if [ -n "$settings_model" ]; then
  case "$settings_model" in
    *opus*)   model="Opus" ;;
    *sonnet*) model="Sonnet" ;;
    *haiku*)  model="Haiku" ;;
    *)        model="$settings_model" ;;
  esac
else
  model="$model_payload"
fi
if [ -n "$model" ]; then
  model_str=$(printf '%b%s%b' '\033[0;36m' "$model" '\033[0m')
else
  model_str=""
fi

# --- Effort ---
if [ -n "$effort" ]; then
  effort_str=$(printf '%b%s%b' '\033[0;35m' "$effort" '\033[0m')
else
  effort_str=""
fi

# --- Cost ---
if [ -n "$cost" ]; then
  cost_str=$(printf '%b$%s%b' '\033[0;33m' "$(printf '%.2f' "$cost")" '\033[0m')
else
  cost_str=""
fi

# --- Duration ---
if [ -n "$duration_ms" ]; then
  total_sec=$(( duration_ms / 1000 ))
  hours=$(( total_sec / 3600 ))
  mins=$(( (total_sec % 3600) / 60 ))
  secs=$(( total_sec % 60 ))
  if [ "$hours" -gt 0 ]; then
    dur_str=$(printf '%b%dh%dm%ds%b' '\033[2m' "$hours" "$mins" "$secs" '\033[0m')
  elif [ "$mins" -gt 0 ]; then
    dur_str=$(printf '%b%dm%ds%b' '\033[2m' "$mins" "$secs" '\033[0m')
  else
    dur_str=$(printf '%b%ds%b' '\033[2m' "$secs" '\033[0m')
  fi
else
  dur_str=""
fi

# --- Lines changed ---
if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
  lines_str=$(printf '%b+%s%b %b-%s%b' '\033[0;32m' "$added" '\033[0m' '\033[0;31m' "$removed" '\033[0m')
else
  lines_str=""
fi

# --- Git branch (cached 5s per workspace) ---
cache_key=$(printf '%s' "$current_dir" | cksum | awk '{print $1}')
cache_file="/tmp/claude-statusline-git-${cache_key}"
cache_age=999

if [ -f "$cache_file" ]; then
  mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
  cache_age=$(( $(date +%s) - mtime ))
fi

if [ "$cache_age" -ge 5 ]; then
  branch=$(git -C "$current_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
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
