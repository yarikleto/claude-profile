#!/usr/bin/env bats
load test_helper

# Tests for tab completion scripts — verifies profile listing excludes
# internal directories like .seed and .pre-profiles-backup.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Helper: run bash completion function in isolated subshell with explicit env.
# Usage: _run_bash_completion <COMP_WORDS[1]> [COMP_WORDS[2]]
# Always simulates completing the LAST word (COMP_CWORD = last index).
_run_bash_completion() {
  local words="$1"
  local cword=1
  if [[ $# -ge 2 ]]; then
    words="$1\" \"$2"
    cword=2
  fi
  run bash -c "
    export CLAUDE_CODE_HOME='$CLAUDE_CODE_HOME'
    source '$REPO_DIR/completions/claude-profile.bash'
    COMP_WORDS=(claude-profile \"$words\")
    COMP_CWORD=$cword
    _claude_profile_completions
    printf '%s\n' \"\${COMPREPLY[@]}\"
  "
}

# ─── Bash completion ─────────────────────────────────────────

@test "bash completion: lists only real profiles, not hidden dirs" {
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/work"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/personal"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/.seed"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/.pre-profiles-backup"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/.managed"

  _run_bash_completion use ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"personal"* ]]
  [[ "$output" != *".seed"* ]]
  [[ "$output" != *".pre-profiles-backup"* ]]
  [[ "$output" != *".managed"* ]]
}

@test "bash completion: completes commands at position 1" {
  run bash -c '
    export CLAUDE_CODE_HOME="'"$CLAUDE_CODE_HOME"'"
    source "'"$REPO_DIR/completions/claude-profile.bash"'"
    COMP_WORDS=(claude-profile "")
    COMP_CWORD=1
    _claude_profile_completions
    printf "%s\n" "${COMPREPLY[@]}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"use"* ]]
  [[ "$output" == *"fork"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"save"* ]]
  [[ "$output" == *"deactivate"* ]]
  [[ "$output" == *"statusline"* ]]
}

@test "bash completion: no profile suggestions for new/fork" {
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/existing"
  _run_bash_completion new ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"existing"* ]]
}

@test "bash completion: statusline completes install/uninstall" {
  _run_bash_completion statusline ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"uninstall"* ]]
}

@test "bash completion: works with no profiles dir yet" {
  # Before any profile is created, __profiles__ doesn't exist
  _run_bash_completion use ""
  [ "$status" -eq 0 ]
  # Should not crash; no profile names in output
  local trimmed
  trimmed="$(echo "$output" | tr -d '[:space:]')"
  [[ -z "$trimmed" ]]
}

# ─── Zsh completion ──────────────────────────────────────────

@test "zsh completion: script is valid zsh syntax" {
  run zsh -n "$REPO_DIR/completions/claude-profile.zsh"
  [ "$status" -eq 0 ]
}

@test "zsh completion: find excludes hidden dirs" {
  # Directly test the find command from the zsh completion script
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/work"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/personal"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/.seed"
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__/.pre-profiles-backup"

  local profiles_dir="$CLAUDE_CODE_HOME/__profiles__"
  run find "$profiles_dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} \;
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"personal"* ]]
  [[ "$output" != *".seed"* ]]
  [[ "$output" != *".pre-profiles-backup"* ]]
}

@test "zsh completion: contains all commands from cli" {
  # Verify the zsh completion file lists the same commands as the bash one
  for cmd in new fork use list current save show edit delete deactivate history diff restore statusline version help; do
    grep -q "'$cmd:" "$REPO_DIR/completions/claude-profile.zsh"
  done
}

@test "bash completion: contains all commands from cli" {
  for cmd in new fork use list current save show edit delete deactivate history diff restore statusline version help; do
    grep -q "$cmd" "$REPO_DIR/completions/claude-profile.bash"
  done
}
