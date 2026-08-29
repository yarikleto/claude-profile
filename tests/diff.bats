#!/usr/bin/env bats
load test_helper

@test "no changes when profile matches live" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
}

@test "no changes after switching into a moved-thin active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
}

@test "detects unsaved changes" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"unsaved": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
}

@test "detects active memory changes but not project session churn" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo "auto v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent v1" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  echo "session v1" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  echo "auto v2" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent v2" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  echo "session v2" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/-repo/memory/MEMORY.md"* ]]
  [[ "$output" == *"agent-memory/researcher/MEMORY.md"* ]]
  [[ "$output" != *"session.jsonl"* ]]
}

@test "detects deleted files after switching into a moved-thin active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  rm "$CLAUDE_CODE_HOME/settings.json"

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
}

@test "ignores gitignored data dirs for a moved-thin active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  # Untracked data that the managed history policy excludes.
  mkdir -p "$CLAUDE_CODE_HOME/projects/big"
  echo "huge" > "$CLAUDE_CODE_HOME/projects/big/data.bin"
  echo "log" > "$CLAUDE_CODE_HOME/history.jsonl"
  # ...plus one real, tracked change
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
  [[ "$output" != *"projects"* ]]
  [[ "$output" != *"history.jsonl"* ]]
}

@test "non-active profile reports its own state, not live" {
  run_cli_ok fork alpha
  run_cli_ok fork beta   # beta is now active; alpha is not

  # Mutate the ACTIVE profile's live state
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Diffing the NON-active alpha must reflect alpha's own git state,
  # not pick up beta's live changes
  run_cli diff alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
}

@test "detects memory changes in an inactive profile but ignores its sessions" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo "auto v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent v1" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  echo "session v1" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork alpha
  run_cli_ok fork beta

  echo "auto v2" > "$(profile_dir alpha)/projects/-repo/memory/MEMORY.md"
  echo "agent v2" > "$(profile_dir alpha)/agent-memory/researcher/MEMORY.md"
  echo "session v2" > "$(profile_dir alpha)/projects/-repo/session.jsonl"

  run_cli diff alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/-repo/memory/MEMORY.md"* ]]
  [[ "$output" == *"agent-memory/researcher/MEMORY.md"* ]]
  [[ "$output" != *"session.jsonl"* ]]
}

@test "diff: two-arg form fails on nonexistent profile name" {
  run_cli_ok fork default
  run_cli diff nonexistent HEAD
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "diff: user's live .gitignore does not hide unsaved changes" {
  run_cli_ok fork default
  echo '*.local.json' > "$CLAUDE_CODE_HOME/.gitignore"
  echo '{"local": true}' > "$CLAUDE_CODE_HOME/settings.local.json"

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.local.json"* ]]
}

@test "with commit ref shows git diff" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%H' -1)"

  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"

  run_cli diff default "$initial"
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
}

@test "with commit ref shows memory changes but not transcript changes" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  echo "memory v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "session v1" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork default
  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"

  echo "memory v2" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "session v2" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok save -m "Mixed update"

  run_cli diff default "$initial"
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/-repo/memory/MEMORY.md"* ]]
  [[ "$output" != *"session.jsonl"* ]]
}
