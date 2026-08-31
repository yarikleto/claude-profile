#!/usr/bin/env bats
load test_helper

install_partial_restore_failure_git() {
  export REAL_GIT_FOR_TEST
  REAL_GIT_FOR_TEST="$(command -v git)"
  export RESTORE_FAILURE_MARKER_FOR_TEST="$BATS_TEST_TMPDIR/restore-apply-failed"
  local wrapper_dir="$BATS_TEST_TMPDIR/failing-git"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
repo=""
command_name=""
previous=""
has_cached=false
for arg in "$@"; do
  if [[ "$previous" == "-C" ]]; then
    repo="$arg"
    previous=""
    continue
  fi
  if [[ "$arg" == "-C" ]]; then
    previous="-C"
    continue
  fi
  if [[ -z "$command_name" && "$arg" != -* ]]; then
    command_name="$arg"
  fi
  if [[ "$arg" == "--cached" ]]; then
    has_cached=true
  fi
done

if [[ "$command_name" == "rm" && \
      "$has_cached" != true && \
      "${FAIL_RESTORE_REMOVE_FOR_TEST:-}" == "true" && \
      ! -e "$RESTORE_FAILURE_MARKER_FOR_TEST" ]]; then
  "$REAL_GIT_FOR_TEST" -C "$repo" rm -f -- settings.json >/dev/null 2>&1 || true
  touch "$RESTORE_FAILURE_MARKER_FOR_TEST"
  echo "simulated partial tracked-path removal failure" >&2
  exit 91
fi

if [[ "$command_name" == "checkout-index" ]]; then
  if [[ -e "$RESTORE_FAILURE_MARKER_FOR_TEST" && \
        "${FAIL_RESTORE_ROLLBACK_FOR_TEST:-}" == "true" ]]; then
    echo "simulated rollback checkout-index failure" >&2
    exit 93
  fi
  if [[ ! -e "$RESTORE_FAILURE_MARKER_FOR_TEST" ]]; then
    touch "$RESTORE_FAILURE_MARKER_FOR_TEST"
    echo "partially introduced target path" > "$repo/target-only.txt"
    "$REAL_GIT_FOR_TEST" -C "$repo" add -f -- target-only.txt
    echo "simulated partial target checkout failure" >&2
    exit 92
  fi
fi

exec "$REAL_GIT_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/git"
  export PATH="$wrapper_dir:$PATH"
}

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

  [[ "$output" == *"Durable memory will be restored to the selected revision"* ]]
  [[ "$output" == *"session data is preserved"* ]]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md")" = "auto v1" ]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/one.md")" = "topic v1" ]
  [ ! -e "$CLAUDE_CODE_HOME/projects/-repo/memory/topics/two.md" ]
  [ "$(cat "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md")" = "agent v1" ]
  [ ! -e "$CLAUDE_CODE_HOME/agent-memory/researcher/later.md" ]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl")" = "session v2" ]
}

@test "restore preserves every disposable root even if the target tracked it" {
  local project session
  project=$'-odd project\nsecond-line'
  session=$'session odd\nsecond-line.jsonl'
  mkdir -p "$CLAUDE_CODE_HOME/projects/$project/memory"
  mkdir -p "$CLAUDE_CODE_HOME/todos" "$CLAUDE_CODE_HOME/plans"
  mkdir -p "$CLAUDE_CODE_HOME/tasks" "$CLAUDE_CODE_HOME/plugins"
  echo memory-target > "$CLAUDE_CODE_HOME/projects/$project/memory/MEMORY.md"
  echo session-target > "$CLAUDE_CODE_HOME/projects/$project/$session"
  echo session-target-only > "$CLAUDE_CODE_HOME/projects/$project/target-only.jsonl"
  echo todos-target > "$CLAUDE_CODE_HOME/todos/current.json"
  echo todos-target-only > "$CLAUDE_CODE_HOME/todos/target-only.json"
  echo plans-target > "$CLAUDE_CODE_HOME/plans/current.md"
  echo tasks-target > "$CLAUDE_CODE_HOME/tasks/current.json"
  echo plugins-target > "$CLAUDE_CODE_HOME/plugins/current.txt"
  echo history-target > "$CLAUDE_CODE_HOME/history.jsonl"
  run_cli_ok fork default

  local dir polluted
  dir="$(profile_dir default)"
  git -C "$dir" add -f -- \
    "projects/$project/$session" \
    "projects/$project/target-only.jsonl" \
    todos/current.json todos/target-only.json \
    plans/current.md tasks/current.json plugins/current.txt history.jsonl
  git -C "$dir" commit -q -m "Polluted disposable history"
  polluted="$(git -C "$dir" rev-parse HEAD)"

  echo memory-current > "$CLAUDE_CODE_HOME/projects/$project/memory/MEMORY.md"
  echo session-current > "$CLAUDE_CODE_HOME/projects/$project/$session"
  rm "$CLAUDE_CODE_HOME/projects/$project/target-only.jsonl"
  echo todos-current > "$CLAUDE_CODE_HOME/todos/current.json"
  rm "$CLAUDE_CODE_HOME/todos/target-only.json"
  echo plans-current > "$CLAUDE_CODE_HOME/plans/current.md"
  echo tasks-current > "$CLAUDE_CODE_HOME/tasks/current.json"
  echo plugins-current > "$CLAUDE_CODE_HOME/plugins/current.txt"
  echo history-current > "$CLAUDE_CODE_HOME/history.jsonl"
  run_cli_ok save -m "Current state"

  run_cli_ok restore "$polluted"

  [ "$(cat "$CLAUDE_CODE_HOME/projects/$project/memory/MEMORY.md")" = memory-target ]
  [ "$(cat "$CLAUDE_CODE_HOME/projects/$project/$session")" = session-current ]
  [ ! -e "$CLAUDE_CODE_HOME/projects/$project/target-only.jsonl" ]
  [ "$(cat "$CLAUDE_CODE_HOME/todos/current.json")" = todos-current ]
  [ ! -e "$CLAUDE_CODE_HOME/todos/target-only.json" ]
  [ "$(cat "$CLAUDE_CODE_HOME/plans/current.md")" = plans-current ]
  [ "$(cat "$CLAUDE_CODE_HOME/tasks/current.json")" = tasks-current ]
  [ "$(cat "$CLAUDE_CODE_HOME/plugins/current.txt")" = plugins-current ]
  [ "$(cat "$CLAUDE_CODE_HOME/history.jsonl")" = history-current ]
}

@test "restore refuses to overwrite a target-only file excluded from current history" {
  echo target-value > "$CLAUDE_CODE_HOME/local-secret.txt"
  run_cli_ok fork default
  local dir target
  dir="$(profile_dir default)"
  target="$(git -C "$dir" rev-parse HEAD)"

  printf '\n/local-secret.txt\n' >> "$dir/.gitignore"
  git -C "$dir" rm --cached -- local-secret.txt >/dev/null
  git -C "$dir" add .gitignore
  git -C "$dir" commit -q -m "Exclude local secret"
  echo current-private-value > "$CLAUDE_CODE_HOME/local-secret.txt"
  run_cli_ok save -m "Keep local secret outside history"
  ! git -C "$dir" ls-files --error-unmatch -- local-secret.txt >/dev/null 2>&1

  run_cli restore "$target"

  [ "$status" -ne 0 ]
  [[ "$output" == *"untracked path would be overwritten"* ]]
  [ "$(cat "$CLAUDE_CODE_HOME/local-secret.txt")" = current-private-value ]
  [ "$(cat "$dir/local-secret.txt")" = current-private-value ]
}

@test "restore refuses a target file that would replace a directory with ignored content" {
  echo target-file > "$CLAUDE_CODE_HOME/config-node"
  run_cli_ok fork default
  local dir target
  dir="$(profile_dir default)"
  target="$(git -C "$dir" rev-parse HEAD)"

  rm "$CLAUDE_CODE_HOME/config-node"
  mkdir "$CLAUDE_CODE_HOME/config-node"
  echo tracked-current > "$CLAUDE_CODE_HOME/config-node/tracked.txt"
  echo precious-current > "$CLAUDE_CODE_HOME/config-node/precious.txt"
  printf '\n/config-node/precious.txt\n' >> "$dir/.gitignore"
  run_cli_ok save -m "Current directory shape"
  ! git -C "$dir" ls-files --error-unmatch -- \
    config-node/precious.txt >/dev/null 2>&1

  run_cli restore "$target"

  [ "$status" -ne 0 ]
  [[ "$output" == *"untracked path would be overwritten"* ]]
  [ "$(cat "$CLAUDE_CODE_HOME/config-node/precious.txt")" = precious-current ]
  [ "$(cat "$CLAUDE_CODE_HOME/config-node/tracked.txt")" = tracked-current ]
  [ -z "$(git -C "$dir" status --porcelain=v1)" ]
}

@test "restore refuses to remove an embedded git repository with untracked data" {
  echo target-state > "$CLAUDE_CODE_HOME/target.txt"
  run_cli_ok fork default
  local dir target current
  dir="$(profile_dir default)"
  target="$(git -C "$dir" rev-parse HEAD)"

  mkdir "$CLAUDE_CODE_HOME/nested"
  git -C "$CLAUDE_CODE_HOME/nested" init -q
  echo inner-tracked > "$CLAUDE_CODE_HOME/nested/tracked.txt"
  git -C "$CLAUDE_CODE_HOME/nested" add tracked.txt
  git -C "$CLAUDE_CODE_HOME/nested" commit -q -m inner
  cat > "$CLAUDE_CODE_HOME/.gitmodules" <<'EOF'
[submodule "nested"]
  path = nested
  url = ../nested
EOF
  echo precious-untracked > "$CLAUDE_CODE_HOME/nested/untracked.txt"
  run_cli_ok save -m "Current embedded repository"
  current="$(git -C "$dir" rev-parse HEAD)"
  [ "$(git -C "$dir" ls-files --stage nested | cut -d ' ' -f 1)" = 160000 ]

  run_cli restore "$target"

  [ "$status" -ne 0 ]
  [[ "$output" == *"embedded Git repository"* ]]
  [ "$(cat "$CLAUDE_CODE_HOME/nested/untracked.txt")" = precious-untracked ]
  [ "$(cat "$dir/nested/untracked.txt")" = precious-untracked ]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$current" ]
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

@test "restore rolls back when its final history commit cannot be recorded" {
  run_cli_ok fork default
  local dir initial current wrapper_dir real_git
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"
  current="$(git -C "$dir" rev-parse HEAD)"

  wrapper_dir="$BATS_TEST_TMPDIR/fail-final-restore-commit"
  mkdir "$wrapper_dir"
  real_git="$(command -v git)"
  cat > "$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
previous=""
for arg in "$@"; do
  if [[ "$previous" == "-m" && "$arg" == "Restored to "* ]]; then
    echo "simulated final restore commit failure" >&2
    exit 97
  fi
  previous="$arg"
done
exec "$REAL_GIT_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/git"

  run env PATH="$wrapper_dir:$PATH" REAL_GIT_FOR_TEST="$real_git" \
    /bin/bash "$CLAUDE_PROFILE" restore "$initial"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not record restored state"* ]]
  [[ "$output" == *"restored to its last saved state"* ]]
  grep -q '"v2"' "$CLAUDE_CODE_HOME/settings.json"
  grep -q '"v2"' "$dir/settings.json"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$current" ]
  git -C "$dir" diff --quiet --
  git -C "$dir" diff --cached --quiet --
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

@test "restore: a partial target application removes target-only paths when rolling back" {
  echo "target version" > "$CLAUDE_CODE_HOME/target-only.txt"
  run_cli_ok fork default
  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"

  rm "$CLAUDE_CODE_HOME/target-only.txt"
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"
  install_partial_restore_failure_git

  run_cli restore "$initial"

  [ "$status" -ne 0 ]
  [[ "$output" == *"simulated partial target checkout failure"* ]]
  [[ "$output" == *"restored to its last saved state"* ]]
  [[ "$output" != *"profile unchanged"* ]]
  [ ! -e "$dir/target-only.txt" ]
  grep -q '"v2"' "$dir/settings.json"
  grep -q '"v2"' "$CLAUDE_CODE_HOME/settings.json"
  git -C "$dir" diff --quiet --
  git -C "$dir" diff --cached --quiet --
}

@test "restore: a partial tracked-path removal rolls the profile back to HEAD" {
  run_cli_ok fork default
  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"

  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"
  install_partial_restore_failure_git
  export FAIL_RESTORE_REMOVE_FOR_TEST=true

  run_cli restore "$initial"

  [ "$status" -ne 0 ]
  [[ "$output" == *"simulated partial tracked-path removal failure"* ]]
  [[ "$output" == *"restored to its last saved state"* ]]
  grep -q '"v2"' "$dir/settings.json"
  grep -q '"v2"' "$CLAUDE_CODE_HOME/settings.json"
  git -C "$dir" diff --quiet --
  git -C "$dir" diff --cached --quiet --
}

@test "restore: reports a possibly partial profile when target rollback also fails" {
  echo "target version" > "$CLAUDE_CODE_HOME/target-only.txt"
  run_cli_ok fork default
  local dir initial
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"

  rm "$CLAUDE_CODE_HOME/target-only.txt"
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"
  install_partial_restore_failure_git
  export FAIL_RESTORE_ROLLBACK_FOR_TEST=true

  run_cli restore "$initial"

  [ "$status" -ne 0 ]
  [[ "$output" == *"simulated partial target checkout failure"* ]]
  [[ "$output" == *"simulated rollback checkout-index failure"* ]]
  [[ "$output" == *"may be partially changed"* ]]
  [[ "$output" == *"recoverable at HEAD"* ]]
  [[ "$output" != *"restored to its last saved state"* ]]
  [ ! -e "$dir/settings.json" ]
  grep -q '"v2"' "$CLAUDE_CODE_HOME/settings.json"
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
