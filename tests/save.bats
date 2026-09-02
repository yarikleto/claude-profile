#!/usr/bin/env bats
load test_helper

@test "commits changes to profile git history" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Updated settings"

  local dir="$(profile_dir default)"
  local log
  log="$(git -C "$dir" log --oneline)"
  [[ "$log" == *"Updated settings"* ]]
}

@test "memory-only changes create a history commit" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo "auto v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent v1" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok fork default

  local dir
  dir="$(profile_dir default)"
  local before
  before="$(git -C "$dir" rev-list --count HEAD)"

  echo "auto v2" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent v2" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok save -m "Updated durable memory"

  [ "$(git -C "$dir" rev-list --count HEAD)" -eq $((before + 1)) ]
  [ "$(git -C "$dir" show HEAD:projects/-repo/memory/MEMORY.md)" = "auto v2" ]
  [ "$(git -C "$dir" show HEAD:agent-memory/researcher/MEMORY.md)" = "agent v2" ]
  [[ "$(git -C "$dir" log -1 --format=%s)" == "Updated durable memory" ]]

  run_cli history default
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated durable memory"* ]]
}

@test "memory-only deletions create a history commit" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory/topics"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo "topic" > "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/remove.md"
  echo "agent" > "$CLAUDE_CODE_HOME/agent-memory/researcher/remove.md"
  run_cli_ok fork default
  local dir before
  dir="$(profile_dir default)"
  before="$(git -C "$dir" rev-list --count HEAD)"

  rm "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/remove.md"
  rm -rf "$CLAUDE_CODE_HOME/agent-memory/researcher"
  run_cli_ok save -m "Removed durable memory"

  [ "$(git -C "$dir" rev-list --count HEAD)" -eq $((before + 1)) ]
  git -C "$dir" cat-file -e "HEAD^:projects/-repo/memory/topics/remove.md"
  git -C "$dir" cat-file -e "HEAD^:agent-memory/researcher/remove.md"
  ! git -C "$dir" cat-file -e "HEAD:projects/-repo/memory/topics/remove.md" 2>/dev/null
  ! git -C "$dir" cat-file -e "HEAD:agent-memory/researcher/remove.md" 2>/dev/null
}

@test "transcript-only save copies data without creating history" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo"
  echo "session v1" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork default
  local dir before
  dir="$(profile_dir default)"
  before="$(git -C "$dir" rev-list --count HEAD)"

  echo "session v2" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok save -m "Session churn"

  [ "$(cat "$dir/projects/-repo/session.jsonl")" = "session v2" ]
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq "$before" ]
}

@test "with explicit name" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"explicit": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save default -m "Explicit save"

  local dir="$(profile_dir default)"
  local log
  log="$(git -C "$dir" log --oneline)"
  [[ "$log" == *"Explicit save"* ]]
}

@test "save as first command creates backup so deactivate works" {
  run_cli_ok save myprofile -m "First save"
  [ -d "$(backup_dir)" ]
  [ -f "$(backup_dir)/settings.json" ]

  run_cli_ok use myprofile
  echo '{"modified": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok deactivate

  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"modified"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "save: propagates top-level deletions to the profile" {
  run_cli_ok fork default
  rm -rf "$CLAUDE_CODE_HOME/skills"
  rm -f "$HOME/.claude.json"

  run_cli_ok save -m "removed"
  [ ! -d "$(profile_dir default)/skills" ]
  [ ! -f "$(profile_dir default)/.claude-profile-home.json" ]
}

@test "save: profile keeps its previous copy when copying an entry fails" {
  run_cli_ok fork default
  chmod 000 "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md"

  run_cli save -m "will fail"
  local st="$status"
  chmod 644 "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md"

  [ "$st" -ne 0 ]
  [ -f "$(profile_dir default)/skills/my-skill/SKILL.md" ]
}

@test "save: a live file named .saving.* is captured, not skipped as staging" {
  echo 'SECRET' > "$CLAUDE_CODE_HOME/.saving.credentials"
  run_cli_ok fork default
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "with saving file"

  [ -f "$(profile_dir default)/.saving.credentials" ]
  [ "$(cat "$(profile_dir default)/.saving.credentials")" = "SECRET" ]
}

@test "use: a .saving.* user file survives a switch round-trip" {
  echo 'SECRET' > "$CLAUDE_CODE_HOME/.saving.data"
  run_cli_ok fork p1
  run_cli_ok new p2
  run_cli_ok use p1

  [ -f "$CLAUDE_CODE_HOME/.saving.data" ]
  [ "$(cat "$CLAUDE_CODE_HOME/.saving.data")" = "SECRET" ]
}

@test "save: staging lives outside the profile payload" {
  run_cli_ok fork default
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "copy save"
  # No staging artifacts left inside the profile directory
  run bash -c "ls -a '$(profile_dir default)' | grep -c '^\.saving'"
  [ "$output" -eq 0 ]
}

@test "save: refuses while a switch is interrupted" {
  run_cli_ok fork default
  echo "use default" > "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli save -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted"* ]]
}

@test "save: rejects unexpected extra argument" {
  run_cli_ok fork default
  run_cli save default extra -m "msg"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected argument"* ]]
  [ ! -d "$(profile_dir extra)" ]
}

@test "save: -m without a message fails cleanly" {
  run_cli_ok fork default
  run_cli save -m
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗"* ]]
  [[ "$output" == *"-m requires a message"* ]]
}

@test "save: warns but succeeds when git history cannot be recorded" {
  run_cli_ok fork default
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  chmod -R a-w "$(profile_dir default)/.git"

  run_cli save -m "history blocked"
  local st="$status" out="$output"
  chmod -R u+w "$(profile_dir default)/.git"

  [ "$st" -eq 0 ]
  [[ "$out" == *"history"* ]]
  grep -q '"changed"' "$(profile_dir default)/settings.json"
}

@test "no-op when nothing changed" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli_ok save -m "No changes"

  local dir="$(profile_dir default)"
  local count
  count="$(git -C "$dir" log --oneline | wc -l | tr -d ' ')"
  # Only initial commit — "No changes" was skipped
  [ "$count" -eq 1 ]
}
