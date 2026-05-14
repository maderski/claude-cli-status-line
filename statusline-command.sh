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
  (if (.cost.total_cost_usd | type) == "number" or (.cost.total_cost_usd | type) == "string" then (.cost.total_cost_usd | tostring) else "" end),
  (.cost.total_duration_ms // ""),
  ((.cost.total_lines_added // 0) | tonumber? // 0 | floor),
  ((.cost.total_lines_removed // 0) | tonumber? // 0 | floor),
  (.workspace.current_dir // "."),
  (.agent.name // ""),
  (.worktree.name // ""),
  (.model.display_name // "")
')

normalize_cost() {
  local raw="$1"
  local mantissa="$raw"
  local exponent=""
  local normalized
  local comma_suffix
  local dot_suffix
  local comma_count
  local dot_count
  local numeric_pattern='^-?[0-9]+([.][0-9]+)?$'
  local scientific_pattern='^-?([0-9]+([.][0-9]+)?)([eE][+-]?[0-9]+)?$'

  if [[ "$raw" =~ ^(.*)([eE][+-]?[0-9]+)$ ]]; then
    mantissa="${BASH_REMATCH[1]}"
    exponent="${BASH_REMATCH[2]}"
  fi

  # Reject strings that aren't parseable as a currency amount (allow leading/trailing
  # currency symbols like $ or €, but reject embedded letters such as "abc1").
  if ! [[ "$mantissa" =~ ^[^a-zA-Z0-9()]*-?[0-9][0-9,.]*[^a-zA-Z0-9()]*$ ]]; then
    return 1
  fi

  normalized=$(printf '%s' "$mantissa" | tr -cd '0-9,.-')
  if [ -z "$normalized" ] || [ "$normalized" = "-" ]; then
    return 1
  fi

  comma_suffix="${normalized##*,}"
  dot_suffix="${normalized##*.}"

  if [ "$comma_suffix" != "$normalized" ] && [ "$dot_suffix" != "$normalized" ]; then
    if [[ "$normalized" =~ ^-?[0-9]{1,3}(,[0-9]{3})+\.[0-9]+$ ]]; then
      normalized="${normalized//,/}"
    elif [[ "$normalized" =~ ^-?[0-9]{1,3}(\.[0-9]{3})+,[0-9]+$ ]]; then
      normalized="${normalized//./}"
      normalized="${normalized//,/.}"
    else
      return 1
    fi
  elif [ "$comma_suffix" != "$normalized" ]; then
    # Comma-only: treat as thousands when the pattern is unambiguous.
    # Single or repeated `,ddd` groups are thousands, except when the first group is 0
    # (e.g. "0,001"), which stays on the decimal path.
    comma_count="${normalized//[^,]/}"
    if [ -n "$exponent" ]; then
      normalized="${normalized//,/.}"
    elif [[ "$normalized" =~ ^-?[0-9]{1,3}(,[0-9]{3})+$ ]] \
        && ! [[ "$normalized" =~ ^-?0, ]]; then
      normalized="${normalized//,/}"
    else
      normalized="${normalized//,/.}"
    fi
  elif [ "$dot_suffix" != "$normalized" ]; then
    # Dot-only: detect European thousands grouping.
    # Multiple dots (e.g. 1.234.567) are unambiguously thousands; a single dot with
    # exactly 3 decimal digits and a € prefix (e.g. €1.234) is also thousands.
    # Other currencies that use dot-thousands notation (CHF, kr, etc.) are not
    # detected here — without a separator pair they're indistinguishable from decimals.
    dot_count="${normalized//[^.]/}"
    if [ -n "$exponent" ] && [ "${#dot_count}" -gt 1 ]; then
      return 1
    elif [ "${#dot_count}" -gt 1 ] && [[ "$normalized" =~ ^-?[0-9]{1,3}(\.[0-9]{3})+$ ]]; then
      normalized="${normalized//./}"
    elif [ "${#dot_count}" -gt 1 ]; then
      return 1
    elif [ -z "$exponent" ] && [[ "$normalized" =~ ^-?[0-9]{1,3}\.[0-9]{3}$ ]] && [[ "$raw" == *€* ]]; then
      normalized="${normalized//./}"
    fi
  fi

  if ! [[ "$normalized" =~ $numeric_pattern ]]; then
    return 1
  fi

  normalized="${normalized}${exponent}"

  if ! [[ "$normalized" =~ $scientific_pattern ]]; then
    return 1
  fi

  # Accept very small scientific values that underflow to 0.0 in floating point but
  # are still positive (they will display as $0.00 via printf %.2f).
  if ! awk -v value="$normalized" 'BEGIN {
    v = value + 0
    if (v > 0) exit 0
    if (v < 0) exit 1
    exit !(value ~ /[1-9]/)
  }'; then
    return 1
  fi

  printf '%s' "$normalized"
}

# --- Context window ---
pct_int=${pct%.*}
pct_int=${pct_int:-0}
if ! [[ "$pct_int" =~ ^-?[0-9]+$ ]]; then
  pct_int=0
fi
if [ "$pct_int" -lt 0 ]; then
  pct_int=0
elif [ "$pct_int" -gt 100 ]; then
  pct_int=100
fi
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
# Prefer live payload (updates every prompt); fall back to settings.json
if [ -n "$model_payload" ]; then
  model="$model_payload"
else
  settings_model=$(jq -r '.model // empty' ~/.claude/settings.json 2>/dev/null)
  case "$settings_model" in
    *opus*)   model="Opus" ;;
    *sonnet*) model="Sonnet" ;;
    *haiku*)  model="Haiku" ;;
    *)        model="$settings_model" ;;
  esac
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
  if normalized_cost=$(normalize_cost "$cost"); then
    cost_str=$(printf '%b$%s%b' '\033[0;33m' "$(printf '%.2f' "$normalized_cost")" '\033[0m')
  else
    cost_str=""
  fi
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
current_uid=$(id -u 2>/dev/null || echo "unknown")
cache_key=$(printf '%s' "$current_dir" | cksum | awk '{print $1}')
cache_dir="${TMPDIR:-/tmp}"
cache_file="${cache_dir%/}/claude-statusline-git-${current_uid}-${cache_key}"
cache_age=999
cache_trusted=0
cache_writable=1

if [ -L "$cache_file" ]; then
  cache_writable=0
fi

if [ -f "$cache_file" ] && [ "$cache_writable" -eq 1 ]; then
  file_uid=$(stat -c %u "$cache_file" 2>/dev/null || stat -f %u "$cache_file" 2>/dev/null || echo "")
  file_mode=$(stat -c %a "$cache_file" 2>/dev/null || stat -f %Lp "$cache_file" 2>/dev/null || echo "")
  if [ "$file_uid" = "$current_uid" ] && [[ "$file_mode" =~ ^[0-7]{3,4}$ ]]; then
    mode_dec=$(( 8#$file_mode ))
    if (( (mode_dec & 18) == 0 )); then
      cache_trusted=1
    fi
  fi
fi

if [ "$cache_trusted" -eq 1 ]; then
  mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
  cache_age=$(( $(date +%s) - mtime ))
fi

if [ "$cache_age" -ge 5 ]; then
  branch=$(git -C "$current_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # Never write directly to the cache path. A symlink at cache_file would
  # otherwise clobber its target via shell redirection.
  if [ "$cache_writable" -eq 1 ]; then
    cache_tmp="${cache_file}.tmp.$$"
    old_umask=$(umask)
    umask 077
    if printf '%s\n' "$branch" > "$cache_tmp"; then
      mv -f "$cache_tmp" "$cache_file" 2>/dev/null || rm -f "$cache_tmp"
    else
      rm -f "$cache_tmp"
    fi
    umask "$old_umask"
  fi
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
