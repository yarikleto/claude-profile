#!/usr/bin/env bats
load test_helper

# Helper: create sample bulk data in live location
setup_bulk_data() {
  # projects/ with some content
  mkdir -p "$CLAUDE_CODE_HOME/projects/my-project"
  echo '{"transcript": true}' > "$CLAUDE_CODE_HOME/projects/my-project/session.jsonl"
  mkdir -p "$CLAUDE_CODE_HOME/projects/my-project/memory"
  echo "user likes TDD" > "$CLAUDE_CODE_HOME/projects/my-project/memory/user.md"

  # agent-memory/
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/my-agent"
  echo "remembered" > "$CLAUDE_CODE_HOME/agent-memory/my-agent/data.txt"

  # todos/
  mkdir -p "$CLAUDE_CODE_HOME/todos"
  echo '{"todo": 1}' > "$CLAUDE_CODE_HOME/todos/task1.json"

  # plans/
  mkdir -p "$CLAUDE_CODE_HOME/plans"
  echo '{"plan": 1}' > "$CLAUDE_CODE_HOME/plans/plan1.json"

  # tasks/
  mkdir -p "$CLAUDE_CODE_HOME/tasks"
  echo '{"task": 1}' > "$CLAUDE_CODE_HOME/tasks/task1.json"

  # plugins/
  mkdir -p "$CLAUDE_CODE_HOME/plugins"
  echo '{"installed": true}' > "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"

  # history.jsonl
  echo '{"msg": "hello"}' > "$CLAUDE_CODE_HOME/history.jsonl"
}

@test "fork: captures bulk items (all types)" {
  setup_bulk_data
  run_cli_ok fork myprofile

  [ -f "$(profile_dir myprofile)/projects/my-project/session.jsonl" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/memory/user.md" ]
  [ -f "$(profile_dir myprofile)/agent-memory/my-agent/data.txt" ]
  [ -f "$(profile_dir myprofile)/todos/task1.json" ]
  [ -f "$(profile_dir myprofile)/plans/plan1.json" ]
  [ -f "$(profile_dir myprofile)/tasks/task1.json" ]
  [ -f "$(profile_dir myprofile)/plugins/installed_plugins.json" ]
  [ -f "$(profile_dir myprofile)/history.jsonl" ]
}

@test "use: plugins and history switch between profiles" {
  setup_bulk_data
  run_cli_ok fork alpha
  run_cli_ok fork beta

  # Modify alpha
  run_cli_ok use alpha
  echo '{"alpha_plugin": true}' > "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"
  echo '{"msg": "alpha"}' > "$CLAUDE_CODE_HOME/history.jsonl"

  # Switch to beta — should have original data
  run_cli_ok use beta
  grep -q '"installed"' "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"
  grep -q '"hello"' "$CLAUDE_CODE_HOME/history.jsonl"

  # Switch back to alpha — should have alpha data
  run_cli_ok use alpha
  grep -q '"alpha_plugin"' "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"
  grep -q '"alpha"' "$CLAUDE_CODE_HOME/history.jsonl"
}

@test "use: bulk items switch between profiles" {
  setup_bulk_data
  run_cli_ok fork alpha

  # Modify live bulk data for beta
  echo "alpha memory" > "$CLAUDE_CODE_HOME/projects/my-project/memory/user.md"
  mkdir -p "$CLAUDE_CODE_HOME/projects/beta-only"
  echo "beta project" > "$CLAUDE_CODE_HOME/projects/beta-only/data.txt"
  run_cli_ok fork beta

  # Switch to alpha — should have alpha's data, not beta's
  run_cli_ok use alpha
  [ -f "$CLAUDE_CODE_HOME/projects/my-project/memory/user.md" ]
  ! [ -d "$CLAUDE_CODE_HOME/projects/beta-only" ]

  # Switch to beta — should have beta's extra project
  run_cli_ok use beta
  [ -d "$CLAUDE_CODE_HOME/projects/beta-only" ]
  [[ "$(cat "$CLAUDE_CODE_HOME/projects/beta-only/data.txt")" == "beta project" ]]
}

@test "use: bulk items are moved (not copied) for speed" {
  setup_bulk_data
  run_cli_ok fork alpha
  run_cli_ok fork beta

  run_cli_ok use alpha

  # After move-load: alpha's profile dir should NOT have files
  # (they were moved to live by _load_profile_to_live --move)
  [ ! -f "$(profile_dir alpha)/projects/my-project/session.jsonl" ]
  [ ! -f "$(profile_dir alpha)/settings.json" ]

  # Files SHOULD be in the live location
  [ -f "$CLAUDE_CODE_HOME/projects/my-project/session.jsonl" ]
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]

  # After move-save: beta's profile dir has files
  [ -f "$(profile_dir beta)/projects/my-project/session.jsonl" ]
}

@test "save: bulk items are copied (not moved) so live keeps working" {
  setup_bulk_data
  run_cli_ok fork myprofile

  echo "new data" > "$CLAUDE_CODE_HOME/projects/my-project/memory/extra.md"
  run_cli_ok save -m "Save with bulk"

  # Both live and profile should have the data
  [ -f "$CLAUDE_CODE_HOME/projects/my-project/memory/extra.md" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/memory/extra.md" ]
}

@test "deactivate: restores original bulk items" {
  setup_bulk_data
  run_cli_ok fork myprofile

  # Modify bulk in active profile
  rm "$CLAUDE_CODE_HOME/todos/task1.json"
  echo "new" > "$CLAUDE_CODE_HOME/todos/task2.json"

  run_cli_ok deactivate

  # Original bulk state should be restored
  [ -f "$CLAUDE_CODE_HOME/todos/task1.json" ]
  ! [ -f "$CLAUDE_CODE_HOME/todos/task2.json" ]
}

@test "new: empty profile has no bulk items" {
  setup_bulk_data
  run_cli_ok new clean

  # Live should be clean — no bulk items
  ! [ -d "$CLAUDE_CODE_HOME/projects/my-project" ]
  ! [ -f "$CLAUDE_CODE_HOME/todos/task1.json" ]
}

@test "bulk items are not in git history" {
  setup_bulk_data
  run_cli_ok fork myprofile

  local tracked
  tracked="$(git -C "$(profile_dir myprofile)" ls-files)"
  ! [[ "$tracked" == *"projects/"* ]]
  ! [[ "$tracked" == *"todos/"* ]]
  ! [[ "$tracked" == *"plans/"* ]]
  ! [[ "$tracked" == *"tasks/"* ]]
  ! [[ "$tracked" == *"agent-memory/"* ]]
}

@test "isolation: bulk items are fully independent between profiles" {
  setup_bulk_data
  run_cli_ok fork alpha
  run_cli_ok fork beta

  # Add unique data to alpha
  run_cli_ok use alpha
  echo "only alpha" > "$CLAUDE_CODE_HOME/todos/alpha-task.json"

  # Switch to beta — alpha's task should not be here
  run_cli_ok use beta
  ! [ -f "$CLAUDE_CODE_HOME/todos/alpha-task.json" ]

  # Switch back to alpha — alpha's task should be back
  run_cli_ok use alpha
  [ -f "$CLAUDE_CODE_HOME/todos/alpha-task.json" ]
}

@test "original backup includes bulk items and is never modified" {
  setup_bulk_data
  run_cli_ok fork myprofile

  # Modify live
  rm "$CLAUDE_CODE_HOME/plans/plan1.json"

  # Backup should still have original
  [ -f "$(backup_dir)/plans/plan1.json" ]
  [[ "$(cat "$(backup_dir)/plans/plan1.json")" == '{"plan": 1}' ]]
}
