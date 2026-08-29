#!/usr/bin/env bats
load test_helper

write_legacy_history_policy() {
  local dir="$1"
  cat > "$dir/.gitignore" <<'EOF'
/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl
EOF
}

@test "fresh profiles stamp format 3 and selectively track durable memory" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory/nested"
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/session/tool-results"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher/nested"
  echo auto > "$CLAUDE_CODE_HOME/projects/-repo/memory/nested/topic.md"
  echo transcript > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  echo tool-result > "$CLAUDE_CODE_HOME/projects/-repo/session/tool-results/result.txt"
  echo agent > "$CLAUDE_CODE_HOME/agent-memory/researcher/nested/topic.md"

  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"

  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
  git -C "$dir" ls-files --error-unmatch -- \
    projects/-repo/memory/nested/topic.md >/dev/null
  git -C "$dir" ls-files --error-unmatch -- \
    agent-memory/researcher/nested/topic.md >/dev/null
  git -C "$dir" check-ignore -q -- projects/-repo/session.jsonl
  git -C "$dir" check-ignore -q -- \
    projects/-repo/session/tool-results/result.txt
  git -C "$dir" show HEAD:.gitignore | \
    grep -Fqx '# claude-profile-history: persistent-memory-v1'
}

@test "first-command new and named save also stamp format 3" {
  run_cli_ok new clean
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]

  local second_home="$BATS_TEST_TMPDIR/second-home"
  mkdir -p "$second_home/.claude/projects/-repo/memory"
  echo '{}' > "$second_home/.claude/settings.json"
  echo durable > "$second_home/.claude/projects/-repo/memory/MEMORY.md"

  run env HOME="$second_home" \
    CLAUDE_CODE_HOME="$second_home/.claude" \
    CLAUDE_PROFILE_HOME="$second_home/store" \
    GIT_CONFIG_GLOBAL="$HOME/.gitconfig" \
    /bin/bash "$CLAUDE_PROFILE" save named -m first
  [ "$status" -eq 0 ]
  [ "$(cat "$second_home/store/.format")" = 3 ]
  git -C "$second_home/store/named" ls-files --error-unmatch -- \
    projects/-repo/memory/MEMORY.md >/dev/null
}

@test "history policy handles nested and git-special memory path names" {
  local project='-:(repo) [demo]'
  local agent='-:(agent) [demo]'
  local odd_name
  odd_name=$'topic :[x] * ?\nsecond-line.md'
  mkdir -p "$CLAUDE_CODE_HOME/projects/$project/memory/nested"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/$agent/nested"
  echo auto > "$CLAUDE_CODE_HOME/projects/$project/memory/nested/$odd_name"
  echo agent > "$CLAUDE_CODE_HOME/agent-memory/$agent/nested/$odd_name"
  echo session > "$CLAUDE_CODE_HOME/projects/$project/session.jsonl"

  run_cli_ok fork special
  local dir
  dir="$(profile_dir special)"
  git -C "$dir" ls-files --error-unmatch -- \
    "projects/$project/memory/nested/$odd_name" >/dev/null
  git -C "$dir" ls-files --error-unmatch -- \
    "agent-memory/$agent/nested/$odd_name" >/dev/null
  git -C "$dir" check-ignore -q -- "projects/$project/session.jsonl"
}

@test "nested gitignore files cannot hide durable memory from history or diff" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  cat > "$CLAUDE_CODE_HOME/projects/-repo/.gitignore" <<'EOF'
memory/
!session.jsonl
EOF
  echo '*' > "$CLAUDE_CODE_HOME/projects/-repo/memory/.gitignore"
  echo '*' > "$CLAUDE_CODE_HOME/agent-memory/.gitignore"
  echo auto-v1 > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo agent-v1 > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  echo private-transcript > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"

  run_cli_ok fork default
  local dir initial before_count
  dir="$(profile_dir default)"
  initial="$(git -C "$dir" rev-parse HEAD)"
  before_count="$(git -C "$dir" rev-list --count HEAD)"
  git -C "$dir" ls-files --error-unmatch -- \
    projects/-repo/memory/MEMORY.md >/dev/null
  git -C "$dir" ls-files --error-unmatch -- \
    agent-memory/researcher/MEMORY.md >/dev/null
  ! git -C "$dir" ls-files --error-unmatch -- \
    projects/-repo/session.jsonl >/dev/null 2>&1

  echo auto-new > "$CLAUDE_CODE_HOME/projects/-repo/memory/new-topic.md"
  echo agent-new > "$CLAUDE_CODE_HOME/agent-memory/researcher/new-topic.md"
  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"projects/-repo/memory/new-topic.md"* ]]
  [[ "$output" == *"agent-memory/researcher/new-topic.md"* ]]

  run_cli_ok save -m nested-ignore-memory
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq $((before_count + 1)) ]
  git -C "$dir" cat-file -e HEAD:projects/-repo/memory/new-topic.md
  git -C "$dir" cat-file -e HEAD:agent-memory/researcher/new-topic.md
  ! git -C "$dir" cat-file -e HEAD:projects/-repo/session.jsonl 2>/dev/null

  run_cli_ok restore "$initial"
  [ ! -e "$CLAUDE_CODE_HOME/projects/-repo/memory/new-topic.md" ]
  [ ! -e "$CLAUDE_CODE_HOME/agent-memory/researcher/new-topic.md" ]
}

@test "legacy migration waits for save before committing a memory baseline" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo auto > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo agent > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok fork default

  local dir legacy before_count
  dir="$(profile_dir default)"
  write_legacy_history_policy "$dir"
  git -C "$dir" rm -r --cached --ignore-unmatch -- \
    projects agent-memory >/dev/null
  git -C "$dir" add .gitignore
  git -C "$dir" commit -q -m "Legacy history policy"
  legacy="$(git -C "$dir" rev-parse HEAD)"
  before_count="$(git -C "$dir" rev-list --count HEAD)"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$legacy" ]
  ! git -C "$dir" show HEAD:.gitignore | \
    grep -Fqx '# claude-profile-history: persistent-memory-v1'

  run_cli_ok save -m "Memory tracking baseline"
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq $((before_count + 1)) ]
  git -C "$dir" show HEAD:.gitignore | \
    grep -Fqx '# claude-profile-history: persistent-memory-v1'
  git -C "$dir" cat-file -e HEAD:projects/-repo/memory/MEMORY.md
  git -C "$dir" cat-file -e HEAD:agent-memory/researcher/MEMORY.md
}

@test "migration preserves custom rules outside the old generated policy" {
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  write_legacy_history_policy "$dir"
  cat >> "$dir/.gitignore" <<'EOF'
/custom-cache
*.local-only
EOF
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  grep -Fxq /custom-cache "$dir/.gitignore"
  grep -Fxq '*.local-only' "$dir/.gitignore"
  [ "$(grep -Fc '# claude-profile-history: persistent-memory-v1' "$dir/.gitignore")" -eq 1 ]
  [ "$(tail -1 "$dir/.gitignore")" = '# END claude-profile managed' ]
}

@test "malformed managed blocks never consume custom rules on repeated refresh" {
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  cat > "$dir/.gitignore" <<'EOF'
/custom-before
# BEGIN claude-profile managed: history-policy=2
/custom-after-malformed-begin
EOF
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  grep -Fxq /custom-before "$dir/.gitignore"
  grep -Fxq /custom-after-malformed-begin "$dir/.gitignore"

  echo changed > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m refresh-again
  grep -Fxq /custom-before "$dir/.gitignore"
  grep -Fxq /custom-after-malformed-begin "$dir/.gitignore"
  [ "$(grep -Fc '# claude-profile-history: persistent-memory-v1' "$dir/.gitignore")" -eq 1 ]
}

@test "migration replaces a symlinked gitignore without touching its target" {
  run_cli_ok fork default
  local dir canary
  dir="$(profile_dir default)"
  canary="$BATS_TEST_TMPDIR/canary-dir"
  mkdir "$canary"
  echo safe > "$canary/keep"
  rm "$dir/.gitignore"
  ln -s "$canary" "$dir/.gitignore"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  [ "$(cat "$canary/keep")" = safe ]
  [ ! -L "$dir/.gitignore" ]
  [ -f "$dir/.gitignore" ]
  grep -Fqx '# claude-profile-history: persistent-memory-v1' "$dir/.gitignore"
}

@test "format 3 migration never modifies the original backup" {
  run_cli_ok fork default
  local backup_policy
  backup_policy="$(backup_dir)/.gitignore"
  echo original-backup-canary > "$backup_policy"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  [ "$(cat "$backup_policy")" = original-backup-canary ]
}

@test "migration defers while an operation marker exists" {
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  write_legacy_history_policy "$dir"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"
  printf 'op=use\nphase=saving\nsource=default\ntarget=default\n' > \
    "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
  grep -Fxq /agent-memory "$dir/.gitignore"
  [ -f "$CLAUDE_PROFILE_HOME/.op-in-progress" ]

  rm "$CLAUDE_PROFILE_HOME/.op-in-progress"
  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
  grep -Fqx '# claude-profile-history: persistent-memory-v1' "$dir/.gitignore"
}

@test "a failed profile refresh keeps the old format stamp for retry" {
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  rm "$dir/.gitignore"
  mkdir "$dir/.gitignore"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
  [ -d "$dir/.gitignore" ]
}

@test "save removes accidentally tracked transcripts without deleting their copy" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo"
  echo private > "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl"
  run_cli_ok fork default
  local dir before
  dir="$(profile_dir default)"
  git -C "$dir" add -f -- projects/-repo/session.jsonl
  git -C "$dir" commit -q -m accidentally-tracked
  before="$(git -C "$dir" rev-list --count HEAD)"

  run_cli_ok save -m enforce-history-policy
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq $((before + 1)) ]
  [ -f "$dir/projects/-repo/session.jsonl" ]
  [ -f "$CLAUDE_CODE_HOME/projects/-repo/session.jsonl" ]
  ! git -C "$dir" ls-files --error-unmatch -- \
    projects/-repo/session.jsonl >/dev/null 2>&1
}

@test "migration replaces a symlinked format stamp without touching its target" {
  run_cli_ok fork default
  local canary="$BATS_TEST_TMPDIR/format-canary"
  echo safe > "$canary"
  rm "$CLAUDE_PROFILE_HOME/.format"
  ln -s "$canary" "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  [ "$(cat "$canary")" = safe ]
  [ ! -L "$CLAUDE_PROFILE_HOME/.format" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
}

@test "mutating commands refuse a store from a newer format" {
  run_cli_ok fork default
  local dir before
  dir="$(profile_dir default)"
  before="$(git -C "$dir" rev-parse HEAD)"
  echo 4 > "$CLAUDE_PROFILE_HOME/.format"
  echo future-unsafe > "$CLAUDE_CODE_HOME/settings.json"

  run_cli save -m downgrade
  [ "$status" -ne 0 ]
  [[ "$output" == *"newer store format"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$before" ]
  [ "$(cat "$CLAUDE_CODE_HOME/settings.json")" = future-unsafe ]

  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"* ]]
}

@test "switch recovery cannot stamp a migration that startup deferred" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha
  rm "$CLAUDE_PROFILE_HOME/.format"
  printf 'op=use\nphase=saving\nsource=alpha\ntarget=beta\n' > \
    "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli_ok use beta
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.format" ]

  run_cli_ok version
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
}

@test "moved-thin migration does not commit false profile deletions" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  echo memory > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  local dir before before_count
  dir="$(profile_dir alpha)"
  write_legacy_history_policy "$dir"
  git -C "$dir" add .gitignore
  git -C "$dir" commit -q -m "Legacy history policy"
  before="$(git -C "$dir" rev-parse HEAD)"
  before_count="$(git -C "$dir" rev-list --count HEAD)"
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"

  run_cli_ok version
  [ "$(git -C "$dir" rev-parse HEAD)" = "$before" ]
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq "$before_count" ]
  git -C "$dir" cat-file -e "$before:settings.json"

  run_cli_ok save -m baseline
  git -C "$dir" cat-file -e HEAD:settings.json
  git -C "$dir" cat-file -e HEAD:projects/-repo/memory/MEMORY.md
}
