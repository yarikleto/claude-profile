#!/usr/bin/env bats
load test_helper

@test "reverts to initial commit" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"

  run_cli_ok restore "$initial"

  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"changed"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "restore rolls back durable memory and leaves session data current" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory/topics"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo "auto v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "topic v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/one.md"
  echo "agent v1" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  echo "session v1" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork default

  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"

  echo "auto v2" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  rm "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/one.md"
  echo "topic v2" > "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/two.md"
  echo "agent v2" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  echo "agent later" > "$CLAUDE_CODE_HOME/agent-memory/researcher/later.md"
  echo "session v2" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok save -m "Memory v2"

  run_cli_ok restore "$initial"

  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md")" = "auto v1" ]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/one.md")" = "topic v1" ]
  [ ! -e "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/two.md" ]
  [ "$(cat "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md")" = "agent v1" ]
  [ ! -e "$CLAUDE_CODE_HOME/agent-memory/researcher/later.md" ]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl")" = "session v2" ]
}

@test "restore handles git-special and newline path names in memory" {
  local project='-:(repo) [demo]'
  local agent='-:(agent) [demo]'
  local odd_name
  odd_name=$'topic :[x] * ?\nsecond-line.md'
  local auto_dir="$CLAUDE_CODE_HOME/projects/$project/memory"
  local agent_dir="$CLAUDE_CODE_HOME/agent-memory/$agent"
  mkdir -p "$auto_dir" "$agent_dir"
  echo auto-v1 > "$auto_dir/$odd_name"
  echo agent-v1 > "$agent_dir/$odd_name"
  run_cli_ok fork default

  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"
  echo auto-v2 > "$auto_dir/$odd_name"
  rm "$agent_dir/$odd_name"
  echo agent-new > "$agent_dir/--new :[x].md"
  run_cli_ok save -m odd-update

  run_cli_ok restore "$initial"
  [ "$(cat "$auto_dir/$odd_name")" = auto-v1 ]
  [ "$(cat "$agent_dir/$odd_name")" = agent-v1 ]
  [ ! -e "$agent_dir/--new :[x].md" ]
}

@test "restore supports a target whose only tracked file is the history policy" {
  rm -rf "$CLAUDE_CODE_HOME/settings.json" "$CLAUDE_CODE_HOME/skills" "$CLAUDE_CODE_HOME/agents"
  rm -f "$HOME/.claude.json"
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo"
  echo "session" > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork default
  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"
  [ "$(git -C "$dir" ls-tree -r --name-only "$initial")" = ".gitignore" ]

  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  echo "added later" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  run_cli_ok save -m "Added memory"

  run_cli_ok restore "$initial"
  [ ! -e "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md" ]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl")" = "session" ]
  [ "$(git -C "$dir" ls-files)" = ".gitignore" ]
}

@test "restore preserves current memory when the target predates memory history" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo "auto v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent v1" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok fork default

  local dir
  dir="$(profile_dir default)"
  cat > "$dir/.gitignore" <<'EOF'
/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl
EOF
  git -C "$dir" rm -r --cached --ignore-unmatch projects agent-memory >/dev/null
  git -C "$dir" add .gitignore
  git -C "$dir" commit -q -m "Legacy history policy"
  local legacy
  legacy="$(git -C "$dir" rev-parse HEAD)"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  run_cli_ok save -m "Memory tracking baseline"
  echo "auto current" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo "agent current" > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok save -m "Current memory"

  run_cli restore "$legacy"
  [ "$status" -eq 0 ]
  [[ "$output" == *"predates memory history"* ]]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md")" = "auto current" ]
  [ "$(cat "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md")" = "agent current" ]
  ! grep -Fxq '/agent-memory' "$dir/.gitignore"
  ! git -C "$dir" check-ignore -q agent-memory/researcher/MEMORY.md
}

@test "creates a new commit (non-destructive)" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"
  run_cli_ok restore "$initial"

  # History: restore, changed, initial = 3 commits (auto-save is no-op since we just saved)
  local count
  count="$(git -C "$dir" log --oneline | wc -l | tr -d ' ')"
  [ "$count" -eq 3 ]
}

@test "auto-saves unsaved live changes before restoring active profile" {
  run_cli_ok fork default
  run_cli_ok use default
  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  echo '{"saved_change": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Saved change"
  echo '{"unsaved_change": true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok restore "$initial"

  local log
  log="$(git -C "$dir" log --oneline)"
  [[ "$log" == *"Auto-save before restore"* ]]
}

@test "profile dir not left empty if checkout target is invalid" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"

  # Date before any commit exists — _git_resolve_ref will fail
  run_cli restore "1970-01-01"
  [ "$status" -ne 0 ]
  [ -f "$(profile_dir default)/settings.json" ]
}

@test "restore accepts bare YYYY-MM-DD date" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"

  # Make unsaved change so restore has visible effect
  echo '{"unsaved": true}' > "$CLAUDE_CODE_HOME/settings.json"

  local commit_date
  commit_date="$(git -C "$dir" log --format='%cs' -1)"

  run_cli_ok restore "$commit_date"

  # Date resolves to end-of-day → matches "Changed" commit
  # Live state should reflect "Changed", NOT the unsaved state
  grep -q '"changed"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"unsaved"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "restore removes files added after target commit" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  # Add a new file and save
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  echo "extra agent" > "$CLAUDE_CODE_HOME/agents/extra.md"
  run_cli_ok save -m "Added extra agent"

  # Restore to initial commit — the extra file should be gone
  run_cli_ok restore "$initial"

  [ ! -f "$(profile_dir default)/agents/extra.md" ]
  [ ! -f "$CLAUDE_CODE_HOME/agents/extra.md" ]
}

@test "requires a ref" {
  run_cli_ok fork default
  run_cli restore
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "restore: aborts when the auto-save cannot be committed" {
  run_cli_ok fork default
  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%H' -1)"
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"
  echo '{"unsaved": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Make every commit in this repo fail
  git -C "$dir" config commit.gpgsign true
  git -C "$dir" config gpg.program /nonexistent-gpg

  run_cli restore "$initial"
  [ "$status" -ne 0 ]
  # unsaved live change still present
  grep -q '"unsaved"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "restore aborts when a memory-only safety commit cannot be recorded" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  echo "memory v1" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  run_cli_ok fork default
  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"

  echo "memory v2" > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  git -C "$dir" config commit.gpgsign true
  git -C "$dir" config gpg.program /nonexistent-gpg

  run_cli restore "$initial"
  [ "$status" -ne 0 ]
  [[ "$output" == *"aborting restore"* ]]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md")" = "memory v2" ]
  [ "$(cat "$dir/projects/-repo/memory/MEMORY.md")" = "memory v2" ]
  [[ "$output" != *"✓ Restored"* ]]
}

@test "restore: two-arg form fails on nonexistent profile name" {
  run_cli_ok fork default
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m v2

  run_cli restore nonexistent HEAD
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  grep -q '"v2"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "restore: failed checkout does not leave the profile tree empty" {
  run_cli_ok fork default
  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%H' -1)"

  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"

  # Remove the initial commit's root tree object so its checkout must fail
  local tree
  tree="$(git -C "$dir" rev-parse "$initial^{tree}")"
  rm -f "$dir/.git/objects/${tree:0:2}/${tree:2}"

  run_cli restore default "$initial"
  [ "$status" -ne 0 ]
  [ -f "$dir/settings.json" ]
  grep -q '"v2"' "$dir/settings.json"
}

@test "restore: refuses a symlinked profile root and never touches its target" {
  run_cli_ok fork real

  # An external git repo standing in for a symlinked profile's target
  local ext="$BATS_TEST_TMPDIR/external"
  mkdir -p "$ext"
  echo 'CANARY' > "$ext/canary.txt"
  git -C "$ext" init -q
  git -C "$ext" add -A
  git -C "$ext" commit -q -m "external"

  ln -s "$ext" "$CLAUDE_PROFILE_HOME/evil"

  run_cli restore evil HEAD
  [ "$status" -ne 0 ]
  # git rm -rf . must not have run against the symlink's target
  [ -f "$ext/canary.txt" ]
}
