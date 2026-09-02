#!/usr/bin/env bats
load test_helper

@test "mutating command refuses to run while another holds the lock" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli save -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress"* ]]
}

@test "stale lock from a dead process is taken over" {
  run_cli_ok fork default
  local dead_pid
  dead_pid="$(bash -c 'echo $$')"
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$dead_pid" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  echo '{"after_stale": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli save -m "stale lock"
  [ "$status" -eq 0 ]
  [ ! -d "$CLAUDE_PROFILE_HOME/.lock" ]
}

@test "a lock with no published pid is never taken over speculatively" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"

  run_cli save -m must-not-steal

  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete"* ]]
  [ -d "$CLAUDE_PROFILE_HOME/.lock" ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock/pid" ]
}

@test "lock is released after a mutating command finishes" {
  run_cli_ok fork default
  [ ! -d "$CLAUDE_PROFILE_HOME/.lock" ]
  run_cli_ok save -m x
  [ ! -d "$CLAUDE_PROFILE_HOME/.lock" ]
}

@test "statusline install refuses to run while another holds the lock" {
  # statusline install mutates both the store and live settings.json, so it
  # must take the same exclusive lock as a switch or it can race one.
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli statusline install
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress"* ]]
}

@test "lock: release only removes a lock this process owns" {
  export PROFILES_DIR="$CLAUDE_PROFILE_HOME"
  mkdir -p "$PROFILES_DIR"
  source "$(dirname "$CLAUDE_PROFILE")/lib/output.sh"
  source "$(dirname "$CLAUDE_PROFILE")/lib/state.sh"

  # A lock owned by another process (token mismatch)
  mkdir -p "$PROFILES_DIR/.lock"
  echo 99999 > "$PROFILES_DIR/.lock/pid"
  echo "someone-elses-token" > "$PROFILES_DIR/.lock/token"

  _LOCK_TOKEN="my-token"
  _release_lock

  # Must not remove a lock we don't own — otherwise a process that lost a
  # takeover race would delete the new owner's lock on EXIT.
  [ -d "$PROFILES_DIR/.lock" ]
  [ "$(cat "$PROFILES_DIR/.lock/token")" = "someone-elses-token" ]
}

@test "lock: release removes a lock whose token matches this process" {
  export PROFILES_DIR="$CLAUDE_PROFILE_HOME"
  mkdir -p "$PROFILES_DIR"
  source "$(dirname "$CLAUDE_PROFILE")/lib/output.sh"
  source "$(dirname "$CLAUDE_PROFILE")/lib/state.sh"

  mkdir -p "$PROFILES_DIR/.lock"
  echo $$ > "$PROFILES_DIR/.lock/pid"
  echo "my-token" > "$PROFILES_DIR/.lock/token"

  _LOCK_TOKEN="my-token"
  _release_lock

  [ ! -d "$PROFILES_DIR/.lock" ]
}

@test "lock: a refused command does not disturb the live lock it failed to take" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "held-by-live-process" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli save -m x
  [ "$status" -ne 0 ]
  [ -d "$CLAUDE_PROFILE_HOME/.lock" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = "held-by-live-process" ]
}

@test "read-only commands run despite the lock" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"* ]]
}

@test "read-only commands skip migration when an unstamped store is locked" {
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "writer-token" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli_ok version
  [[ "$output" == claude-profile* ]]
  run_cli_ok list
  [[ "$output" == *"No profiles yet"* ]]
  run_cli_ok help
  [[ "$output" == *"USAGE"* ]]

  [ ! -e "$CLAUDE_PROFILE_HOME/.format" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/pid")" = "$$" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = "writer-token" ]
}

@test "read-only commands skip a still-pending failed migration behind a live lock" {
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  rm "$dir/.gitignore"
  mkdir "$dir/.gitignore"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  # Establish that the migration itself cannot complete and leaves the old
  # stamp for a future retry.
  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]

  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "writer-token" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli_ok list
  [[ "$output" == *"default"* ]]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
  [ -d "$dir/.gitignore" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = "writer-token" ]
}

@test "legacy active and inactive diffs remain accurate when migration skips a live lock" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  echo baseline > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  run_cli_ok fork alpha
  run_cli_ok fork beta
  local dir active_dir
  dir="$(profile_dir alpha)"
  active_dir="$(profile_dir beta)"
  cat > "$dir/.gitignore" <<'EOF'
/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl
EOF
  git -C "$dir" rm -r --cached --ignore-unmatch -- projects agent-memory >/dev/null
  git -C "$dir" add .gitignore
  git -C "$dir" commit -q -m "Legacy policy"
  cat > "$active_dir/.gitignore" <<'EOF'
/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl
EOF
  git -C "$active_dir" rm -r --cached --ignore-unmatch -- \
    projects agent-memory >/dev/null
  git -C "$active_dir" add .gitignore
  git -C "$active_dir" commit -q -m "Legacy active policy"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"
  echo changed > "$dir/projects/-repo/memory/MEMORY.md"
  echo active-changed > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "writer-token" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli diff alpha

  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/-repo/memory/MEMORY.md"* ]]
  run_cli diff beta
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/-repo/memory/MEMORY.md"* ]]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = writer-token ]
}

@test "read-only commands do not disturb a lock when migration is deferred by recovery" {
  run_cli_ok fork default
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"
  printf 'op=use\nphase=saving\nsource=default\ntarget=default\n' > \
    "$CLAUDE_PROFILE_HOME/.op-in-progress"
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "writer-token" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
  [ -f "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/pid")" = "$$" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = "writer-token" ]
}

@test "mutating commands still require a live lock before migrating an unstamped store" {
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "writer-token" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli statusline install
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress"* ]]
  [ ! -e "$CLAUDE_PROFILE_HOME/.format" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = "writer-token" ]
  ! grep -q '"statusLine"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "optional migration lock acquisition is silent and never takes a stale lock" {
  export PROFILES_DIR="$CLAUDE_PROFILE_HOME"
  mkdir -p "$PROFILES_DIR/.lock"
  echo "stale-token" > "$PROFILES_DIR/.lock/token"
  source "$(dirname "$CLAUDE_PROFILE")/lib/output.sh"
  source "$(dirname "$CLAUDE_PROFILE")/lib/state.sh"

  local capture="$BATS_TEST_TMPDIR/optional-lock-output"
  local rc=0
  _try_acquire_lock > "$capture" 2>&1 || rc=$?

  [ "$rc" -ne 0 ]
  [ ! -s "$capture" ]
  [ -z "$_LOCK_TOKEN" ]
  [ -d "$PROFILES_DIR/.lock" ]
  [ "$(cat "$PROFILES_DIR/.lock/token")" = "stale-token" ]
  ! compgen -G "$PROFILES_DIR/.lock.stale.*" >/dev/null
}

@test "optional migration lock cleans up silently when metadata writes fail" {
  export PROFILES_DIR="$CLAUDE_PROFILE_HOME"
  mkdir -p "$PROFILES_DIR"
  source "$(dirname "$CLAUDE_PROFILE")/lib/output.sh"
  source "$(dirname "$CLAUDE_PROFILE")/lib/state.sh"

  local failure_entry bad_tmp capture rc
  for failure_entry in token pid; do
    capture="$BATS_TEST_TMPDIR/optional-lock-write-$failure_entry-output"
    bad_tmp="$BATS_TEST_TMPDIR/read-only-$failure_entry"
    rc=0
    mktemp() {
      if [[ "$1" == *".lock-$failure_entry."* ]]; then
        command touch "$bad_tmp"
        command chmod 400 "$bad_tmp"
        echo "$bad_tmp"
        return 0
      fi
      command mktemp "$@"
    }

    _try_acquire_lock > "$capture" 2>&1 || rc=$?
    unset -f mktemp

    [ "$rc" -ne 0 ]
    [ ! -s "$capture" ]
    [ -z "$_LOCK_TOKEN" ]
    [ ! -e "$PROFILES_DIR/.lock" ]
    ! compgen -G "$PROFILES_DIR/.lock-token.*" >/dev/null
    ! compgen -G "$PROFILES_DIR/.lock-pid.*" >/dev/null
  done
}

@test "lock acquisition sweeps dead PID-named metadata without touching live owners" {
  run_cli_ok fork default
  local dead_pid
  dead_pid="$(bash -c 'echo $$')"
  ! kill -0 "$dead_pid" 2>/dev/null

  # PID-bearing names cover SIGKILL before the first content write.
  : > "$CLAUDE_PROFILE_HOME/.lock-pid.$dead_pid.unwritten"
  : > "$CLAUDE_PROFILE_HOME/.lock-token.$dead_pid.unwritten"

  : > "$CLAUDE_PROFILE_HOME/.lock-pid.$$.unwritten"
  : > "$CLAUDE_PROFILE_HOME/.lock-token.$$.unwritten"
  local canary="$BATS_TEST_TMPDIR/lock-temp-canary"
  echo canary > "$canary"
  ln -s "$canary" "$CLAUDE_PROFILE_HOME/.lock-pid.$dead_pid.symlink"

  # A PID embedded before the first content write still protects a genuinely
  # live initializer from speculative takeover and cleanup.
  mkdir "$CLAUDE_PROFILE_HOME/.lock"
  run_cli save -m must-not-steal-pending-owner
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress (pid $$)"* ]]
  [ -f "$CLAUDE_PROFILE_HOME/.lock-pid.$$.unwritten" ]
  rmdir "$CLAUDE_PROFILE_HOME/.lock"

  echo '{"swept": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m sweep-dead-lock-temps

  [ ! -e "$CLAUDE_PROFILE_HOME/.lock-pid.$dead_pid.unwritten" ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock-token.$dead_pid.unwritten" ]
  [ -f "$CLAUDE_PROFILE_HOME/.lock-pid.$$.unwritten" ]
  [ -f "$CLAUDE_PROFILE_HOME/.lock-token.$$.unwritten" ]
  [ -L "$CLAUDE_PROFILE_HOME/.lock-pid.$dead_pid.symlink" ]
  [ "$(cat "$canary")" = canary ]
}

@test "an idle read migration releases its lock before command dispatch" {
  run_cli_ok fork default
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  local real_git wrapper_dir observation
  real_git="$(command -v git)"
  wrapper_dir="$BATS_TEST_TMPDIR/git-wrapper"
  observation="$BATS_TEST_TMPDIR/lock-observation"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == log ]]; then
    if [[ -e "$CLAUDE_PROFILE_HOME/.lock" ]]; then
      echo locked > "$LOCK_OBSERVATION"
    else
      echo unlocked > "$LOCK_OBSERVATION"
    fi
    break
  fi
done
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$wrapper_dir/git"

  run env PATH="$wrapper_dir:$PATH" REAL_GIT="$real_git" \
    LOCK_OBSERVATION="$observation" /bin/bash "$CLAUDE_PROFILE" history default

  [ "$status" -eq 0 ]
  [ "$(cat "$observation")" = unlocked ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock" ]
}

@test "a contender cannot steal a lock while its live owner publishes the pid" {
  run_cli_ok fork default
  local wrapper_dir="$BATS_TEST_TMPDIR/lock-publish-wrappers"
  local ready="$BATS_TEST_TMPDIR/pid-publish-ready"
  local gate="$BATS_TEST_TMPDIR/pid-publish-gate"
  local owner_output="$BATS_TEST_TMPDIR/owner-output"
  local real_ln real_mv
  real_ln="$(command -v ln)"
  real_mv="$(command -v mv)"
  mkdir -p "$wrapper_dir"

  cat > "$wrapper_dir/publish-wrapper" <<'EOF'
#!/usr/bin/env bash
tool="$(basename "$0")"
case "$tool" in
  ln) real_tool="$REAL_LN_FOR_TEST" ;;
  mv) real_tool="$REAL_MV_FOR_TEST" ;;
  *) exit 97 ;;
esac
destination=""
for arg in "$@"; do
  destination="$arg"
done
if [[ "${BLOCK_LOCK_PID_PUBLICATION:-}" == true && \
      "$destination" == "$CLAUDE_PROFILE_HOME/.lock/pid" ]]; then
  : > "$LOCK_PUBLISH_READY"
  attempts=0
  while [[ ! -e "$LOCK_PUBLISH_GATE" && "$attempts" -lt 1000 ]]; do
    sleep 0.01
    attempts=$((attempts + 1))
  done
  [[ -e "$LOCK_PUBLISH_GATE" ]] || exit 98
fi
exec "$real_tool" "$@"
EOF
  chmod +x "$wrapper_dir/publish-wrapper"
  cp "$wrapper_dir/publish-wrapper" "$wrapper_dir/ln"
  cp "$wrapper_dir/publish-wrapper" "$wrapper_dir/mv"

  env PATH="$wrapper_dir:$PATH" \
    REAL_LN_FOR_TEST="$real_ln" REAL_MV_FOR_TEST="$real_mv" \
    BLOCK_LOCK_PID_PUBLICATION=true \
    LOCK_PUBLISH_READY="$ready" LOCK_PUBLISH_GATE="$gate" \
    /bin/bash "$CLAUDE_PROFILE" save -m owner > "$owner_output" 2>&1 &
  local owner_pid=$!

  local attempts=0
  while [[ ! -e "$ready" && "$attempts" -lt 500 ]]; do
    sleep 0.01
    attempts=$((attempts + 1))
  done
  if [[ ! -e "$ready" ]]; then
    touch "$gate"
    kill "$owner_pid" 2>/dev/null || true
    wait "$owner_pid" 2>/dev/null || true
    false
  fi

  run env PATH="$wrapper_dir:$PATH" \
    REAL_LN_FOR_TEST="$real_ln" REAL_MV_FOR_TEST="$real_mv" \
    LOCK_PUBLISH_READY="$ready" LOCK_PUBLISH_GATE="$gate" \
    /bin/bash "$CLAUDE_PROFILE" save -m contender
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress"* ]]
  [[ "$output" == *"If that is wrong, remove $CLAUDE_PROFILE_HOME/.lock"* ]]
  kill -0 "$owner_pid"

  touch "$gate"
  wait "$owner_pid"
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock" ]
}

@test "lock acquisition works when the store filesystem has no hard links" {
  run_cli_ok fork default
  local wrapper_dir="$BATS_TEST_TMPDIR/no-hardlinks"
  local real_ln
  real_ln="$(command -v ln)"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/ln" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "-s" ]]; then
  echo "hard links unsupported" >&2
  exit 95
fi
exec "$REAL_LN_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/ln"
  echo '{"hardlinkless": true}' > "$CLAUDE_CODE_HOME/settings.json"

  run env PATH="$wrapper_dir:$PATH" REAL_LN_FOR_TEST="$real_ln" \
    /bin/bash "$CLAUDE_PROFILE" save -m hardlinkless

  [ "$status" -eq 0 ]
  [[ "$output" == *"Saved"* ]]
  grep -q 'hardlinkless' "$(profile_dir default)/settings.json"
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock" ]
}
