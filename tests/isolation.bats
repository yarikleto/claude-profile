#!/usr/bin/env bats
# Tests that verify profile isolation — changes in one profile
# never leak to another or to the original backup.

load test_helper

@test "isolation: changing active profile doesn't affect other profiles" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  # Modify alpha's working state
  echo '{"alpha_only": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Switch to beta — alpha should be saved, beta loaded
  run_cli_ok use beta

  # Beta should have the original settings, NOT alpha's change
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"alpha_only"' "$CLAUDE_CODE_HOME/settings.json"

  # Alpha's profile dir should have its change
  grep -q '"alpha_only"' "$(profile_dir alpha)/settings.json"
}

@test "isolation: original backup never changes" {
  run_cli_ok fork default
  run_cli_ok use default

  local backup="$(backup_dir)"
  local original_settings
  original_settings="$(cat "$backup/settings.json")"

  # Make multiple changes and saves
  echo '{"v1": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "v1"
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "v2"

  # Backup must be unchanged
  local current_settings
  current_settings="$(cat "$backup/settings.json")"
  [ "$original_settings" = "$current_settings" ]
}

@test "isolation: new profile has only minimal seeded config" {
  run_cli_ok new empty
  run_cli_ok use empty

  # Only minimal seeded files should exist
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]
  [ ! -f "$CLAUDE_CODE_HOME/CLAUDE.md" ]
  [ ! -d "$CLAUDE_CODE_HOME/agents" ]
  [ ! -d "$CLAUDE_CODE_HOME/skills" ]
  [ ! -d "$CLAUDE_CODE_HOME/rules" ]
  [ ! -f "$CLAUDE_CODE_HOME/keybindings.json" ]
}

@test "isolation: deactivate fully restores after multiple switches" {
  run_cli_ok fork alpha
  run_cli_ok new beta

  # Switch around, modifying state each time
  run_cli_ok use alpha
  echo '{"alpha": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok use beta
  echo '{"beta": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok use alpha
  run_cli_ok deactivate

  # Original state should be back
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"alpha"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"beta"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "isolation: MCP config is per-profile" {
  run_cli_ok fork with-mcp
  run_cli_ok new without-mcp
  run_cli_ok use with-mcp

  # Modify MCP in with-mcp
  echo '{"mcpServers": {"custom": {}}}' > "$HOME/.claude.json"
  run_cli_ok save -m "Custom MCP"

  # Switch to without-mcp (has minimal seeded config)
  run_cli_ok use without-mcp
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]

  # Switch back
  run_cli_ok use with-mcp
  grep -q '"custom"' "$HOME/.claude.json"
}

@test "isolation: tests don't touch real home directory" {
  # HOME should be inside BATS temp dir
  [[ "$HOME" == *"bats"* ]] || [[ "$HOME" == */tmp/* ]]
  [[ "$CLAUDE_CODE_HOME" == *"bats"* ]] || [[ "$CLAUDE_CODE_HOME" == */tmp/* ]]
}

@test "isolation: tests are immune to an ambient GIT_DIR" {
  # A git hook (e.g. the pre-push hook) runs with GIT_DIR/GIT_INDEX_FILE
  # exported. If those leaked into a test, its `git commit`s would write to
  # the caller's repo instead of the isolated HOME — which once corrupted a
  # real branch. test_helper.bash scrubs the inherited git environment at
  # load time so this holds for every test.
  [ -z "${GIT_DIR:-}" ]
  [ -z "${GIT_WORK_TREE:-}" ]
  [ -z "${GIT_INDEX_FILE:-}" ]

  # Behavioural guard: the tool's git operations must land inside the isolated
  # profiles dir, never in some ambient repo.
  run_cli_ok fork probe
  [ -d "$(profile_dir probe)/.git" ]
  git -C "$(profile_dir probe)" rev-parse --absolute-git-dir | grep -qF "$BATS_TEST_TMPDIR"
}
