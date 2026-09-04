#!/usr/bin/env bats
load test_helper

# The home-level ~/.claude.json and a live file literally named
# ~/.claude/.claude.json must occupy disjoint namespaces in a profile, so a
# round trip preserves both.

@test "namespace: a live ~/.claude/.claude.json survives alongside the home file" {
  echo '{"home":"OUTER"}' > "$HOME/.claude.json"
  echo '{"inner":"INNER"}' > "$CLAUDE_CODE_HOME/.claude.json"

  run_cli_ok fork p1
  run_cli_ok new p2
  run_cli_ok use p1

  grep -q '"home":"OUTER"' "$HOME/.claude.json"
  grep -q '"inner":"INNER"' "$CLAUDE_CODE_HOME/.claude.json"
}

@test "namespace: the home file still round-trips when there is no inner file" {
  echo '{"home":"ONLY"}' > "$HOME/.claude.json"
  rm -f "$CLAUDE_CODE_HOME/.claude.json"

  run_cli_ok fork p1
  run_cli_ok new p2
  run_cli_ok use p1

  grep -q '"home":"ONLY"' "$HOME/.claude.json"
  [ ! -e "$CLAUDE_CODE_HOME/.claude.json" ]
}

@test "namespace: fork stores the home file outside the live payload" {
  echo '{"home":"OUTER"}' > "$HOME/.claude.json"
  echo '{"inner":"INNER"}' > "$CLAUDE_CODE_HOME/.claude.json"
  run_cli_ok fork p1

  run bash -c "grep -rl 'OUTER' '$(profile_dir p1)'"
  local home_path="$output"
  run bash -c "grep -rl 'INNER' '$(profile_dir p1)'"
  local inner_path="$output"
  [ -n "$home_path" ]
  [ -n "$inner_path" ]
  [ "$home_path" != "$inner_path" ]
}

@test "namespace: migrates a legacy profile that stored the home file at the root" {
  run_cli_ok fork legacy
  run_cli_ok new other        # switch away so 'legacy' is a full stored profile

  # Force the pre-format-2 on-disk layout: home file at the profile root, no
  # reserved file, and no format stamp (so the next run migrates).
  rm -f "$(profile_dir legacy)/.claude-profile-home.json"
  echo '{"home":"LEGACY"}' > "$(profile_dir legacy)/.claude.json"
  rm -f "$CLAUDE_PROFILE_HOME/.format"

  # A switch to the legacy profile must restore its home file, not lose it
  run_cli_ok use legacy
  grep -q '"home":"LEGACY"' "$HOME/.claude.json"
  # It must NOT have been loaded as a live-payload file
  [ ! -e "$CLAUDE_CODE_HOME/.claude.json" ]
  # And the store is now migrated: home file at the reserved name
  [ -f "$(profile_dir legacy)/.claude-profile-home.json" ]
}
