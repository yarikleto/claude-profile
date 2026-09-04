#!/usr/bin/env bats
load test_helper

setup_bulk_data() {
  mkdir -p "$CLAUDE_CODE_HOME/projects/my-project"
  echo '{"transcript": true}' > "$CLAUDE_CODE_HOME/projects/my-project/session.jsonl"
  mkdir -p "$CLAUDE_CODE_HOME/projects/my-project/memory"
  echo "user likes TDD" > "$CLAUDE_CODE_HOME/projects/my-project/memory/user.md"
  mkdir -p "$CLAUDE_CODE_HOME/projects/my-project/memory/topics/nested"
  echo "nested durable memory" > "$CLAUDE_CODE_HOME/projects/my-project/memory/topics/nested/detail.md"
  mkdir -p "$CLAUDE_CODE_HOME/projects/my-project/session/tool-results"
  echo "large disposable output" > "$CLAUDE_CODE_HOME/projects/my-project/session/tool-results/result.txt"

  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/my-agent"
  echo "remembered" > "$CLAUDE_CODE_HOME/agent-memory/my-agent/data.txt"

  mkdir -p "$CLAUDE_CODE_HOME/todos"
  echo '{"todo": 1}' > "$CLAUDE_CODE_HOME/todos/task1.json"

  mkdir -p "$CLAUDE_CODE_HOME/plans"
  echo '{"plan": 1}' > "$CLAUDE_CODE_HOME/plans/plan1.json"

  mkdir -p "$CLAUDE_CODE_HOME/tasks"
  echo '{"task": 1}' > "$CLAUDE_CODE_HOME/tasks/task1.json"

  mkdir -p "$CLAUDE_CODE_HOME/plugins"
  echo '{"installed": true}' > "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"

  echo '{"msg": "hello"}' > "$CLAUDE_CODE_HOME/history.jsonl"
}

@test "fork: captures bulk items (all types)" {
  setup_bulk_data
  run_cli_ok fork myprofile

  [ -f "$(profile_dir myprofile)/projects/my-project/session.jsonl" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/memory/user.md" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/memory/topics/nested/detail.md" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/session/tool-results/result.txt" ]
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

  run_cli_ok use alpha
  echo '{"alpha_plugin": true}' > "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"
  echo '{"msg": "alpha"}' > "$CLAUDE_CODE_HOME/history.jsonl"

  run_cli_ok use beta
  grep -q '"installed"' "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"
  grep -q '"hello"' "$CLAUDE_CODE_HOME/history.jsonl"

  run_cli_ok use alpha
  grep -q '"alpha_plugin"' "$CLAUDE_CODE_HOME/plugins/installed_plugins.json"
  grep -q '"alpha"' "$CLAUDE_CODE_HOME/history.jsonl"
}

@test "use: bulk items switch between profiles" {
  setup_bulk_data
  run_cli_ok fork alpha

  echo "alpha memory" > "$CLAUDE_CODE_HOME/projects/my-project/memory/user.md"
  mkdir -p "$CLAUDE_CODE_HOME/projects/beta-only"
  echo "beta project" > "$CLAUDE_CODE_HOME/projects/beta-only/data.txt"
  run_cli_ok fork beta

  run_cli_ok use alpha
  [ -f "$CLAUDE_CODE_HOME/projects/my-project/memory/user.md" ]
  ! [ -d "$CLAUDE_CODE_HOME/projects/beta-only" ]

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

  [ -f "$CLAUDE_CODE_HOME/projects/my-project/memory/extra.md" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/memory/extra.md" ]
}

@test "deactivate: restores original bulk items" {
  setup_bulk_data
  run_cli_ok fork myprofile

  rm "$CLAUDE_CODE_HOME/todos/task1.json"
  echo "new" > "$CLAUDE_CODE_HOME/todos/task2.json"

  run_cli_ok deactivate

  [ -f "$CLAUDE_CODE_HOME/todos/task1.json" ]
  ! [ -f "$CLAUDE_CODE_HOME/todos/task2.json" ]
}

@test "new: empty profile has no bulk items" {
  setup_bulk_data
  run_cli_ok new clean

  ! [ -d "$CLAUDE_CODE_HOME/projects/my-project" ]
  ! [ -f "$CLAUDE_CODE_HOME/todos/task1.json" ]
}

@test "durable memory is tracked while disposable bulk items stay ignored" {
  setup_bulk_data
  run_cli_ok fork myprofile

  local tracked
  tracked="$(git -C "$(profile_dir myprofile)" ls-files)"
  [[ "$tracked" == *"projects/my-project/memory/user.md"* ]]
  [[ "$tracked" == *"projects/my-project/memory/topics/nested/detail.md"* ]]
  [[ "$tracked" == *"agent-memory/my-agent/data.txt"* ]]
  ! [[ "$tracked" == *"projects/my-project/session.jsonl"* ]]
  ! [[ "$tracked" == *"projects/my-project/session/tool-results/result.txt"* ]]
  ! [[ "$tracked" == *"todos/"* ]]
  ! [[ "$tracked" == *"plans/"* ]]
  ! [[ "$tracked" == *"tasks/"* ]]
}

@test "isolation: bulk items are fully independent between profiles" {
  setup_bulk_data
  run_cli_ok fork alpha
  run_cli_ok fork beta

  run_cli_ok use alpha
  echo "only alpha" > "$CLAUDE_CODE_HOME/todos/alpha-task.json"

  run_cli_ok use beta
  ! [ -f "$CLAUDE_CODE_HOME/todos/alpha-task.json" ]

  run_cli_ok use alpha
  [ -f "$CLAUDE_CODE_HOME/todos/alpha-task.json" ]
}

@test "original backup includes bulk items and is never modified" {
  setup_bulk_data
  run_cli_ok fork myprofile

  rm "$CLAUDE_CODE_HOME/plans/plan1.json"

  [ -f "$(backup_dir)/plans/plan1.json" ]
  [[ "$(cat "$(backup_dir)/plans/plan1.json")" == '{"plan": 1}' ]]
}
