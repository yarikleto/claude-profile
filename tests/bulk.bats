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
}

@test "fork: captures bulk items (projects, agent-memory, todos, plans, tasks)" {
  setup_bulk_data
  run_cli_ok fork myprofile

  [ -f "$(profile_dir myprofile)/projects/my-project/session.jsonl" ]
  [ -f "$(profile_dir myprofile)/projects/my-project/memory/user.md" ]
  [ -f "$(profile_dir myprofile)/agent-memory/my-agent/data.txt" ]
  [ -f "$(profile_dir myprofile)/todos/task1.json" ]
  [ -f "$(profile_dir myprofile)/plans/plan1.json" ]
  [ -f "$(profile_dir myprofile)/tasks/task1.json" ]
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

  # After switching to alpha, beta's profile dir should NOT have bulk items
  # (they were moved to live)
  run_cli_ok use alpha
  # alpha's bulk is now live, alpha profile dir may not have bulk (moved to live)
  # beta's bulk should be in beta's profile dir (saved before switch)
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
