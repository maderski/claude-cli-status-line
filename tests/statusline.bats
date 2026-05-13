#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../statusline-command.sh"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.claude"
  unset TMPDIR

  MOCK_BIN="$(mktemp -d)"
  export PATH="$MOCK_BIN:$PATH"

  # Fixed workspace dir so cache key is deterministic across tests
  TEST_DIR="/tmp/bats-test-workspace"
  TEST_UID="$(id -u)"
  CACHE_KEY=$(printf '%s' "$TEST_DIR" | cksum | awk '{print $1}')
  CACHE_FILE="/tmp/claude-statusline-git-${TEST_UID}-${CACHE_KEY}"
  GIT_LOG="$TEST_HOME/git-calls.log"

  rm -f "$CACHE_FILE" "$GIT_LOG"

  _mock_git "main"
}

teardown() {
  rm -rf "$TEST_HOME" "$MOCK_BIN"
  rm -f "$CACHE_FILE"
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

_mock_git() {
  local branch="${1:-main}"
  # Variables expanded now so the script file has hardcoded paths/values
  cat > "$MOCK_BIN/git" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${GIT_LOG}"
echo "${branch}"
MOCK
  chmod +x "$MOCK_BIN/git"
}

_mock_git_fail() {
  cat > "$MOCK_BIN/git" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${GIT_LOG}"
exit 1
MOCK
  chmod +x "$MOCK_BIN/git"
}

_run() {
  run bash "$SCRIPT" <<< "$1"
}

_strip() {
  # Strip all ANSI escape codes from $output
  printf '%s' "$output" | sed 's/\x1b\[[0-9;]*m//g'
}

_has_ansi() {
  # Check that $output contains a specific ANSI code (fixed-string match)
  printf '%s' "$output" | grep -qF "$1"
}

_json() {
  # Build a JSON payload. Optional first arg is extra fields (comma-prefixed not needed).
  local fields="${1:-}"
  if [ -n "$fields" ]; then
    printf '{%s,"workspace":{"current_dir":"%s"}}' "$fields" "$TEST_DIR"
  else
    printf '{"workspace":{"current_dir":"%s"}}' "$TEST_DIR"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Context window — bar rendering
# ═══════════════════════════════════════════════════════════════════════════════

@test "context bar: 0% shows ten empty blocks" {
  _run "$(_json '"context_window":{"used_percentage":0}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"[░░░░░░░░░░] 0%"* ]]
}

@test "context bar: 50% shows five filled and five empty blocks" {
  _run "$(_json '"context_window":{"used_percentage":50}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"[█████░░░░░] 50%"* ]]
}

@test "context bar: 100% shows ten filled blocks" {
  _run "$(_json '"context_window":{"used_percentage":100}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"[██████████] 100%"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Context window — color thresholds
# ═══════════════════════════════════════════════════════════════════════════════
# Each test uses a payload with no cost and no lines so the tested color
# can only originate from the context bar.

@test "context color: green when below 50%" {
  _run "$(_json '"context_window":{"used_percentage":49}')"
  _has_ansi $'\033[0;32m'
}

@test "context color: yellow at exactly 50%" {
  _run "$(_json '"context_window":{"used_percentage":50}')"
  _has_ansi $'\033[0;33m'
}

@test "context color: yellow at 79%" {
  _run "$(_json '"context_window":{"used_percentage":79}')"
  _has_ansi $'\033[0;33m'
}

@test "context color: red at exactly 80%" {
  _run "$(_json '"context_window":{"used_percentage":80}')"
  _has_ansi $'\033[0;31m'
}

@test "context color: red at 100%" {
  _run "$(_json '"context_window":{"used_percentage":100}')"
  _has_ansi $'\033[0;31m'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Context window — edge / defaults
# ═══════════════════════════════════════════════════════════════════════════════

@test "context: missing context_window defaults to 0%" {
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"0%"* ]]
}

@test "context: empty JSON object exits successfully and shows 0%" {
  _run '{}'
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"0%"* ]]
}

@test "context: negative percentage is clamped to 0%" {
  _run "$(_json '"context_window":{"used_percentage":-5}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"[░░░░░░░░░░] 0%"* ]]
}

@test "context: percentage above 100 is clamped to 100%" {
  _run "$(_json '"context_window":{"used_percentage":150}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"[██████████] 100%"* ]]
}

@test "context: non-numeric percentage falls back to 0%" {
  _run "$(_json '"context_window":{"used_percentage":"abc"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"[░░░░░░░░░░] 0%"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Model
# ═══════════════════════════════════════════════════════════════════════════════

@test "model: opus in settings.json maps to Opus" {
  echo '{"model":"claude-opus-4-7"}' > "$HOME/.claude/settings.json"
  _run "$(_json)"
  [[ "$(_strip)" == *"Opus"* ]]
}

@test "model: sonnet in settings.json maps to Sonnet" {
  echo '{"model":"claude-sonnet-4-6"}' > "$HOME/.claude/settings.json"
  _run "$(_json)"
  [[ "$(_strip)" == *"Sonnet"* ]]
}

@test "model: haiku in settings.json maps to Haiku" {
  echo '{"model":"claude-haiku-4-5"}' > "$HOME/.claude/settings.json"
  _run "$(_json)"
  [[ "$(_strip)" == *"Haiku"* ]]
}

@test "model: unrecognized settings.json model shown as-is" {
  echo '{"model":"custom-model-xyz"}' > "$HOME/.claude/settings.json"
  _run "$(_json)"
  [[ "$(_strip)" == *"custom-model-xyz"* ]]
}

@test "model: uses payload display_name when present" {
  _run "$(_json '"model":{"display_name":"Opus"}')"
  [[ "$(_strip)" == *"Opus"* ]]
}

@test "model: payload display_name takes precedence over settings.json" {
  echo '{"model":"claude-sonnet-4-6"}' > "$HOME/.claude/settings.json"
  _run "$(_json '"model":{"display_name":"Haiku"}')"
  [[ "$(_strip)" == *"Haiku"* ]]
  [[ "$(_strip)" != *"Sonnet"* ]]
}

@test "model: hidden when neither settings.json nor payload provides it" {
  _run "$(_json)"
  # Cyan is only used for model; its absence means model segment is hidden
  ! _has_ansi $'\033[0;36m'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Effort
# ═══════════════════════════════════════════════════════════════════════════════

@test "effort: shown when present in payload" {
  _run "$(_json '"output_style":{"name":"concise"}')"
  [[ "$(_strip)" == *"concise"* ]]
}

@test "effort: hidden when absent from payload" {
  _run "$(_json)"
  [[ "$(_strip)" != *"concise"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Cost
# ═══════════════════════════════════════════════════════════════════════════════

@test "cost: shown and formatted when greater than zero" {
  _run "$(_json '"cost":{"total_cost_usd":1.5}')"
  [[ "$(_strip)" == *'$1.50'* ]]
}

@test "cost: shows two decimal places for small amounts" {
  _run "$(_json '"cost":{"total_cost_usd":0.1}')"
  [[ "$(_strip)" == *'$0.10'* ]]
}

@test "cost: hidden when exactly zero" {
  _run "$(_json '"cost":{"total_cost_usd":0}')"
  [[ "$(_strip)" != *'$'* ]]
}

@test "cost: hidden when absent from payload" {
  _run "$(_json)"
  [[ "$(_strip)" != *'$'* ]]
}

# Simulate jq outputting a comma decimal separator (European locale behavior).
# The mock outputs all 10 fields the script reads, with cost as a comma-formatted
# string. The settings.json jq call is detected by argument and returns empty.
_mock_jq_comma_cost() {
  local comma_cost="$1"
  cat > "$MOCK_BIN/jq" <<MOCK
#!/usr/bin/env bash
if [[ "\$*" == *"settings.json"* ]]; then
  echo ""
  exit 0
fi
printf '0\n\n${comma_cost}\n\n0\n0\n${TEST_DIR}\n\n\n\n'
MOCK
  chmod +x "$MOCK_BIN/jq"
}

@test "cost: comma decimal separator is normalized and displayed with period" {
  _mock_jq_comma_cost "1,50"
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1.50'* ]]
}

@test "cost: small amount with comma decimal separator is normalized correctly" {
  _mock_jq_comma_cost "0,10"
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$0.10'* ]]
}

@test "cost: large amount with comma decimal separator is normalized correctly" {
  _mock_jq_comma_cost "12,34"
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$12.34'* ]]
}

@test "cost: comma decimal string with dollar sign is normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"$0,01"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$0.01'* ]]
}

@test "cost: comma decimal string with currency symbol increments past zero" {
  _run "$(_json '"cost":{"total_cost_usd":"$1,23"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1.23'* ]]
}

@test "cost: comma-grouped thousands without decimal separator are normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"1,234"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1234.00'* ]]
}

@test "cost: multiple comma-grouped thousands without decimal separator are normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"12,345,678"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$12345678.00'* ]]
}

@test "cost: localized zero value with currency symbol stays hidden" {
  _run "$(_json '"cost":{"total_cost_usd":"€0,00"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *'$'* ]]
}

@test "cost: European thousands and decimal separators are normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"€1.234,56"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1234.56'* ]]
}

@test "cost: US thousands and decimal separators are normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"$1,234.56"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1234.56'* ]]
}

@test "cost: scientific notation preserves negative exponent values" {
  _run "$(_json '"cost":{"total_cost_usd":"1E-7"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$0.00'* ]]
}

@test "cost: scientific notation preserves positive exponent values" {
  _run "$(_json '"cost":{"total_cost_usd":"1E+21"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1000000000000000000000.00'* ]]
}

@test "cost: scientific notation with extreme negative exponent shows as zero" {
  _run "$(_json '"cost":{"total_cost_usd":"1E-400"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$0.00'* ]]
}

@test "cost: comma decimal with leading zero is not treated as thousands grouping" {
  _run "$(_json '"cost":{"total_cost_usd":"0,001"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$0.00'* ]]
}

@test "cost: non-numeric string with embedded digit is hidden" {
  _run "$(_json '"cost":{"total_cost_usd":"abc1"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *'$'* ]]
}

@test "cost: comma-grouped thousands with zero-padded group are normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"1,001"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1001.00'* ]]
}

@test "cost: European dot-grouped integer with euro prefix is normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"€1.234"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1234.00'* ]]
}

@test "cost: multiple dot-grouped thousands without decimal are normalized correctly" {
  _run "$(_json '"cost":{"total_cost_usd":"1.234.567"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1234567.00'* ]]
}

@test "cost: US dollar with dot decimal and three fractional digits is not treated as thousands" {
  _run "$(_json '"cost":{"total_cost_usd":"$1.234"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *'$1.23'* ]]
}

@test "cost: malformed comma separators are hidden" {
  _run "$(_json '"cost":{"total_cost_usd":"1,2,3"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *'$'* ]]

  _run "$(_json '"cost":{"total_cost_usd":"1,,2"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *'$'* ]]
}

@test "cost: malformed dot separators are hidden" {
  _run "$(_json '"cost":{"total_cost_usd":"1.2.3"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *'$'* ]]

  _run "$(_json '"cost":{"total_cost_usd":"12..34"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *'$'* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Duration
# ═══════════════════════════════════════════════════════════════════════════════

@test "duration: shows seconds only for under one minute" {
  _run "$(_json '"cost":{"total_duration_ms":45000}')"
  [[ "$(_strip)" == *"45s"* ]]
}

@test "duration: shows minutes and seconds for one to 59 minutes" {
  _run "$(_json '"cost":{"total_duration_ms":125000}')"  # 2m5s
  [[ "$(_strip)" == *"2m5s"* ]]
}

@test "duration: shows hours minutes seconds for one hour or more" {
  _run "$(_json '"cost":{"total_duration_ms":3661000}')"  # 1h1m1s
  [[ "$(_strip)" == *"1h1m1s"* ]]
}

@test "duration: hidden when absent from payload" {
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *"0s"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Lines changed
# ═══════════════════════════════════════════════════════════════════════════════

@test "lines: shown when lines added is nonzero" {
  _run "$(_json '"cost":{"total_lines_added":10,"total_lines_removed":0}')"
  [[ "$(_strip)" == *"+10"* ]]
}

@test "lines: shown when lines removed is nonzero" {
  _run "$(_json '"cost":{"total_lines_added":0,"total_lines_removed":5}')"
  [[ "$(_strip)" == *"-5"* ]]
}

@test "lines: hidden when both added and removed are zero" {
  _run "$(_json '"cost":{"total_lines_added":0,"total_lines_removed":0}')"
  [[ "$(_strip)" != *"+0"* ]]
  [[ "$(_strip)" != *"-0"* ]]
}

@test "lines: float values from payload are truncated to integers" {
  _run "$(_json '"cost":{"total_lines_added":10.9,"total_lines_removed":3.2}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"+10"* ]]
  [[ "$(_strip)" == *"-3"* ]]
}

@test "lines: numeric strings are accepted and truncated to integers" {
  _run "$(_json '"cost":{"total_lines_added":"10.9","total_lines_removed":"3.2"}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"+10"* ]]
  [[ "$(_strip)" == *"-3"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Git branch — caching
# ═══════════════════════════════════════════════════════════════════════════════

@test "git: calls git on cache miss and shows branch" {
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [ -f "$GIT_LOG" ]
  [[ "$(_strip)" == *"main"* ]]
}

@test "git: reads from cache and skips git call when cache is fresh" {
  echo "cached-branch" > "$CACHE_FILE"
  chmod 600 "$CACHE_FILE"
  # mtime is now → age 0, well under the 5-second threshold
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"cached-branch"* ]]
  [ ! -f "$GIT_LOG" ]
}

@test "git: ignores cache when file is group/world writable" {
  echo "poisoned-branch" > "$CACHE_FILE"
  chmod 666 "$CACHE_FILE"
  _mock_git "trusted-branch"

  _run "$(_json)"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" == *"trusted-branch"* ]]
  [ -f "$GIT_LOG" ]
}

@test "git: calls git again when cache is stale" {
  echo "old-branch" > "$CACHE_FILE"
  # Back-date the cache file so its age exceeds 5 seconds
  touch -t 197001010000 "$CACHE_FILE"
  _mock_git "new-branch"
  _run "$(_json)"
  [ "$status" -eq 0 ]
  [ -f "$GIT_LOG" ]
  [[ "$(_strip)" == *"new-branch"* ]]
}

@test "git: branch hidden when git command fails" {
  _mock_git_fail
  _run "$(_json)"
  [ "$status" -eq 0 ]
  # Blue is only used for git; its absence means the branch segment is hidden
  ! _has_ansi $'\033[0;34m'
}

@test "git: shows non-default branch name" {
  _mock_git "feature/my-feature"
  _run "$(_json)"
  [[ "$(_strip)" == *"feature/my-feature"* ]]
}

@test "git: cache file is written under TMPDIR when provided" {
  export TMPDIR="$TEST_HOME/custom-tmpdir"
  mkdir -p "$TMPDIR"
  expected_cache_file="${TMPDIR%/}/claude-statusline-git-${TEST_UID}-${CACHE_KEY}"

  _run "$(_json)"
  [ "$status" -eq 0 ]
  [ -f "$expected_cache_file" ]
}

@test "git: cache write does not clobber symlink target" {
  target_file="$TEST_HOME/symlink-target"
  echo "DO-NOT-OVERWRITE" > "$target_file"
  ln -s "$target_file" "$CACHE_FILE"
  _mock_git "safe-branch"

  _run "$(_json)"
  [ "$status" -eq 0 ]
  [ -L "$CACHE_FILE" ]
  [[ "$(_strip)" == *"safe-branch"* ]]
  [[ "$(cat "$target_file")" == "DO-NOT-OVERWRITE" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Agent / worktree
# ═══════════════════════════════════════════════════════════════════════════════

@test "agent: shown in brackets when present" {
  _run "$(_json '"agent":{"name":"code-builder"}')"
  [[ "$(_strip)" == *"[code-builder]"* ]]
}

@test "worktree: shown with wt: prefix when agent is absent" {
  _run "$(_json '"worktree":{"name":"feature-wt"}')"
  [[ "$(_strip)" == *"[wt:feature-wt]"* ]]
}

@test "agent: takes precedence over worktree when both present" {
  _run "$(_json '"agent":{"name":"my-agent"},"worktree":{"name":"my-wt"}')"
  [[ "$(_strip)" == *"[my-agent]"* ]]
  [[ "$(_strip)" != *"[wt:"* ]]
}

@test "agent/worktree: both hidden when absent" {
  # No effort either, so magenta is entirely absent
  _run "$(_json)"
  ! _has_ansi $'\033[0;35m'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Output assembly
# ═══════════════════════════════════════════════════════════════════════════════

@test "assembly: segments are separated by pipe with spaces" {
  _run "$(_json '"context_window":{"used_percentage":10},"model":{"display_name":"Opus"}')"
  [[ "$(_strip)" == *" | "* ]]
}

@test "assembly: no separator when only one segment is present" {
  # git fails → no branch; no model, effort, cost, duration, lines, or agent in JSON
  _mock_git_fail
  _run "$(_json '"context_window":{"used_percentage":10}')"
  [ "$status" -eq 0 ]
  [[ "$(_strip)" != *" | "* ]]
}

@test "assembly: output is padded with a leading and trailing space" {
  _run "$(_json '"context_window":{"used_percentage":10}')"
  [[ "$output" == " "* ]]
  [[ "$output" == *" " ]]
}
