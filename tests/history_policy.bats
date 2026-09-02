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

@test "first-command statusline install stamps a newly created store" {
  [ ! -e "$CLAUDE_PROFILE_HOME" ]

  run_cli_ok statusline install

  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 3 ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock" ]
  [ -x "$CLAUDE_PROFILE_HOME/statusline.sh" ]
  grep -q '"statusLine"' "$CLAUDE_CODE_HOME/settings.json"
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

@test "switch save dereferences symlinked memory roots before recording history" {
  local external="$BATS_TEST_TMPDIR/external-roots"
  mkdir -p "$external/projects/-repo/memory"
  mkdir -p "$external/agent-memory/researcher"
  echo auto-v1 > "$external/projects/-repo/memory/MEMORY.md"
  echo session > "$external/projects/-repo/session.jsonl"
  echo agent-v1 > "$external/agent-memory/researcher/MEMORY.md"
  ln -s "$external/projects" "$CLAUDE_CODE_HOME/projects"
  ln -s "$external/agent-memory" "$CLAUDE_CODE_HOME/agent-memory"

  run_cli_ok fork alpha
  run_cli_ok fork beta
  local dir before_count
  dir="$(profile_dir beta)"
  before_count="$(git -C "$dir" rev-list --count HEAD)"

  echo auto-v2 > "$external/projects/-repo/memory/MEMORY.md"
  echo agent-v2 > "$external/agent-memory/researcher/MEMORY.md"
  run_cli_ok use alpha

  [[ "$output" != *"history skipped"* ]]
  [ ! -L "$dir/projects" ]
  [ ! -L "$dir/agent-memory" ]
  [ "$(git -C "$dir" show HEAD:projects/-repo/memory/MEMORY.md)" = auto-v2 ]
  [ "$(git -C "$dir" show HEAD:agent-memory/researcher/MEMORY.md)" = agent-v2 ]
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq $((before_count + 1)) ]
  [ -z "$(git -C "$dir" status --porcelain=v1)" ]
}

@test "switch save dereferences symlinked project and memory children" {
  local external="$BATS_TEST_TMPDIR/external-children"
  mkdir -p "$external/project/memory"
  mkdir -p "$external/memory"
  mkdir -p "$external/agent"
  echo project-v1 > "$external/project/memory/MEMORY.md"
  echo memory-v1 > "$external/memory/MEMORY.md"
  echo agent-v1 > "$external/agent/MEMORY.md"

  mkdir -p "$CLAUDE_CODE_HOME/projects/-real"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory"
  ln -s "$external/project" "$CLAUDE_CODE_HOME/projects/-linked"
  ln -s "$external/memory" "$CLAUDE_CODE_HOME/projects/-real/memory"
  ln -s "$external/agent" "$CLAUDE_CODE_HOME/agent-memory/researcher"

  run_cli_ok fork alpha
  run_cli_ok fork beta
  local dir
  dir="$(profile_dir beta)"

  echo project-v2 > "$external/project/memory/MEMORY.md"
  echo memory-v2 > "$external/memory/MEMORY.md"
  echo agent-v2 > "$external/agent/MEMORY.md"
  run_cli_ok use alpha

  [[ "$output" != *"history skipped"* ]]
  [ ! -L "$dir/projects/-linked" ]
  [ ! -L "$dir/projects/-real/memory" ]
  [ ! -L "$dir/agent-memory/researcher" ]
  [ "$(git -C "$dir" show HEAD:projects/-linked/memory/MEMORY.md)" = project-v2 ]
  [ "$(git -C "$dir" show HEAD:projects/-real/memory/MEMORY.md)" = memory-v2 ]
  [ "$(git -C "$dir" show HEAD:agent-memory/researcher/MEMORY.md)" = agent-v2 ]
  [ -z "$(git -C "$dir" status --porcelain=v1)" ]
}

@test "failed history staging leaves the real index byte-for-byte unchanged" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo auto > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo agent > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok fork default

  local dir before_index before_head
  dir="$(profile_dir default)"
  before_index="$BATS_TEST_TMPDIR/index.before"
  cp "$dir/.git/index" "$before_index"
  before_head="$(git -C "$dir" rev-parse HEAD)"

  echo 'blocked.txt filter=reject-history-test' > "$CLAUDE_CODE_HOME/.gitattributes"
  echo blocked > "$CLAUDE_CODE_HOME/blocked.txt"
  git -C "$dir" config filter.reject-history-test.clean false
  git -C "$dir" config filter.reject-history-test.required true

  run_cli save -m rejected
  [ "$status" -eq 0 ]
  [[ "$output" == *"history skipped"* ]]
  cmp -s "$before_index" "$dir/.git/index"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$before_head" ]
  git -C "$dir" diff --cached --quiet
}

@test "save does not replace a corrupt HEAD with new root history" {
  run_cli_ok fork default

  local dir before_index head_ref corrupt_oid
  dir="$(profile_dir default)"
  before_index="$BATS_TEST_TMPDIR/index-before-corrupt-head"
  cp "$dir/.git/index" "$before_index"
  head_ref="$(git -C "$dir" symbolic-ref HEAD)"
  corrupt_oid=1111111111111111111111111111111111111111
  printf '%s\n' "$corrupt_oid" > "$dir/.git/$head_ref"

  echo '{"saved_despite_corrupt_history": true}' > \
    "$CLAUDE_CODE_HOME/settings.json"
  run_cli save -m corrupt-head

  [ "$status" -eq 0 ]
  [[ "$output" == *"history skipped"* ]]
  [ "$(git -C "$dir" symbolic-ref HEAD)" = "$head_ref" ]
  [ "$(tr -d '\n' < "$dir/.git/$head_ref")" = "$corrupt_oid" ]
  ! git -C "$dir" rev-parse --verify 'HEAD^{commit}' >/dev/null 2>&1
  cmp -s "$before_index" "$dir/.git/index"
  grep -q saved_despite_corrupt_history "$dir/settings.json"
}

@test "successful no-change staging repairs an already polluted real index" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/-repo/memory"
  mkdir -p "$CLAUDE_CODE_HOME/agent-memory/researcher"
  echo auto > "$CLAUDE_CODE_HOME/projects/-repo/memory/MEMORY.md"
  echo agent > "$CLAUDE_CODE_HOME/agent-memory/researcher/MEMORY.md"
  run_cli_ok fork default

  local dir before_count
  dir="$(profile_dir default)"
  before_count="$(git -C "$dir" rev-list --count HEAD)"
  git -C "$dir" rm -r -f --cached -- projects agent-memory >/dev/null
  ! git -C "$dir" diff --cached --quiet

  run_cli_ok save -m no-change
  git -C "$dir" diff --cached --quiet
  [ "$(git -C "$dir" rev-list --count HEAD)" -eq "$before_count" ]
  git -C "$dir" ls-files --error-unmatch -- \
    projects/-repo/memory/MEMORY.md >/dev/null
  git -C "$dir" ls-files --error-unmatch -- \
    agent-memory/researcher/MEMORY.md >/dev/null
}

@test "save keeps git subprocess fanout bounded for config-heavy profiles" {
  mkdir -p "$CLAUDE_CODE_HOME/skills/heavy"
  local i
  for ((i = 0; i < 600; i++)); do
    printf 'skill %s\n' "$i" > \
      "$CLAUDE_CODE_HOME/skills/heavy/skill-$i.md"
  done
  run_cli_ok fork default

  local wrapper_dir real_git counter
  wrapper_dir="$BATS_TEST_TMPDIR/bounded-git-fanout"
  counter="$BATS_TEST_TMPDIR/git-add-count"
  mkdir "$wrapper_dir"
  real_git="$(command -v git)"
  echo 0 > "$counter"
  cat > "$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
is_add=false
for arg in "$@"; do
  if [[ "$arg" == add ]]; then
    is_add=true
    break
  fi
done
if [[ "$is_add" == true ]]; then
  count="$(cat "$GIT_ADD_COUNTER_FOR_TEST")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$GIT_ADD_COUNTER_FOR_TEST"
  if [[ "$count" -gt 8 ]]; then
    echo "excessive git add subprocess fanout" >&2
    exit 98
  fi
fi
exec "$REAL_GIT_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/git"

  echo '{"bounded_fanout": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run env PATH="$wrapper_dir:$PATH" REAL_GIT_FOR_TEST="$real_git" \
    GIT_ADD_COUNTER_FOR_TEST="$counter" \
    /bin/bash "$CLAUDE_PROFILE" save -m bounded-fanout

  [ "$status" -eq 0 ]
  [[ "$output" != *"history skipped"* ]]
  [ "$(cat "$counter")" -le 8 ]
  git -C "$(profile_dir default)" show HEAD:settings.json | \
    grep -q bounded_fanout
}

@test "failed index publication cannot advance HEAD or replace the real index" {
  run_cli_ok fork default
  local dir before_index before_head wrapper_dir real_mv
  dir="$(profile_dir default)"
  before_index="$BATS_TEST_TMPDIR/index-before-publication"
  cp "$dir/.git/index" "$before_index"
  before_head="$(git -C "$dir" rev-parse HEAD)"
  wrapper_dir="$BATS_TEST_TMPDIR/fail-index-publication"
  real_mv="$(command -v mv)"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/mv" <<'EOF'
#!/usr/bin/env bash
source_path="${@: -2:1}"
destination="${@: -1}"
if [[ "$source_path" == *'/.git/.claude-profile-index.'* && \
      "$destination" == */.git/index ]]; then
  echo "simulated index publication failure" >&2
  exit 94
fi
exec "$REAL_MV_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/mv"

  echo '{"publication": "must-be-atomic"}' > "$CLAUDE_CODE_HOME/settings.json"
  run env PATH="$wrapper_dir:$PATH" REAL_MV_FOR_TEST="$real_mv" \
    /bin/bash "$CLAUDE_PROFILE" save -m publication-failure

  [ "$status" -eq 0 ]
  [[ "$output" == *"history skipped"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$before_head" ]
  cmp -s "$before_index" "$dir/.git/index"
  git -C "$dir" diff --cached --quiet --
}

@test "failed ref publication restores the original real index" {
  run_cli_ok fork default
  local dir before_index before_head wrapper_dir real_git
  dir="$(profile_dir default)"
  before_index="$BATS_TEST_TMPDIR/index-before-ref-publication"
  cp "$dir/.git/index" "$before_index"
  before_head="$(git -C "$dir" rev-parse HEAD)"
  wrapper_dir="$BATS_TEST_TMPDIR/fail-ref-publication"
  real_git="$(command -v git)"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == update-ref ]]; then
    echo "simulated ref publication failure" >&2
    exit 96
  fi
done
exec "$REAL_GIT_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/git"

  echo '{"ref_publication": "must-roll-back-index"}' > \
    "$CLAUDE_CODE_HOME/settings.json"
  run env PATH="$wrapper_dir:$PATH" REAL_GIT_FOR_TEST="$real_git" \
    /bin/bash "$CLAUDE_PROFILE" save -m ref-publication-failure

  [ "$status" -eq 0 ]
  [[ "$output" == *"original index restored"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$before_head" ]
  cmp -s "$before_index" "$dir/.git/index"
  git -C "$dir" diff --cached --quiet --
}

@test "failed symlink replacement never writes through the external target" {
  local external wrapper_dir real_rm real_mv
  external="$BATS_TEST_TMPDIR/external-symlink-target"
  wrapper_dir="$BATS_TEST_TMPDIR/fail-symlink-replacement"
  mkdir -p "$external/-repo/memory" "$wrapper_dir"
  echo external-memory > "$external/-repo/memory/MEMORY.md"
  ln -s "$external" "$CLAUDE_CODE_HOME/projects"
  run_cli_ok fork alpha
  run_cli_ok fork beta

  real_rm="$(command -v rm)"
  real_mv="$(command -v mv)"
cat > "$wrapper_dir/rm" <<'EOF'
#!/usr/bin/env bash
recursive=false
for arg in "$@"; do
  if [[ "$arg" == -*r* ]]; then
    recursive=true
  fi
  if [[ "$arg" == "$CLAUDE_PROFILE_HOME/beta/projects" ]]; then
    if [[ "$recursive" != true ]]; then
      echo "simulated symlink unlink failure" >&2
      exit 95
    fi
  fi
done
exec "$REAL_RM_FOR_TEST" "$@"
EOF
  cat > "$wrapper_dir/mv" <<'EOF'
#!/usr/bin/env bash
source_path="${@: -2:1}"
if [[ "$source_path" == "$CLAUDE_PROFILE_HOME/beta/projects" ]]; then
  echo "simulated symlink quarantine failure" >&2
  exit 95
fi
exec "$REAL_MV_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/rm" "$wrapper_dir/mv"

  run env PATH="$wrapper_dir:$PATH" REAL_RM_FOR_TEST="$real_rm" \
    REAL_MV_FOR_TEST="$real_mv" /bin/bash "$CLAUDE_PROFILE" use alpha

  [ "$status" -ne 0 ]
  [ -L "$(profile_dir beta)/projects" ]
  [ "$(cat "$external/-repo/memory/MEMORY.md")" = external-memory ]
  [ -z "$(find "$external" -name '*.repair.*' -print -quit)" ]
}

@test "interrupted symlink replacement restores the quarantined profile link" {
  local external wrapper_dir real_mv
  external="$BATS_TEST_TMPDIR/interrupted-symlink-target"
  wrapper_dir="$BATS_TEST_TMPDIR/interrupt-symlink-replacement"
  mkdir -p "$external/-repo/memory" "$wrapper_dir"
  echo external-memory > "$external/-repo/memory/MEMORY.md"
  ln -s "$external" "$CLAUDE_CODE_HOME/projects"
  run_cli_ok fork alpha
  run_cli_ok fork beta

  real_mv="$(command -v mv)"
  cat > "$wrapper_dir/mv" <<'EOF'
#!/usr/bin/env bash
source_path="${@: -2:1}"
target_path="${@: -1}"
if [[ "$source_path" == */replacement &&
      "$target_path" == "$CLAUDE_PROFILE_HOME/beta/projects" ]]; then
  kill -TERM "$PPID"
  exit 143
fi
exec "$REAL_MV_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/mv"

  run env PATH="$wrapper_dir:$PATH" REAL_MV_FOR_TEST="$real_mv" \
    /bin/bash "$CLAUDE_PROFILE" use alpha

  [ "$status" -ne 0 ]
  [ -L "$(profile_dir beta)/projects" ]
  [ "$(readlink "$(profile_dir beta)/projects")" = "$external" ]
  [ "$(cat "$external/-repo/memory/MEMORY.md")" = external-memory ]
  [ -z "$(find "$CLAUDE_PROFILE_HOME" -maxdepth 1 \
    -name '.symlink-repair.*' -print -quit)" ]
}

@test "save rejects a profile git directory redirected to another repository" {
  run_cli_ok fork default
  local dir external original_git before
  dir="$(profile_dir default)"
  external="$BATS_TEST_TMPDIR/external-repository"
  original_git="$BATS_TEST_TMPDIR/original-profile-git"
  mkdir -p "$external"
  git -C "$external" init -q
  echo canary > "$external/canary.txt"
  git -C "$external" add canary.txt
  git -C "$external" commit -q -m canary
  before="$(git -C "$external" rev-parse HEAD)"
  mv "$dir/.git" "$original_git"
  ln -s "$external/.git" "$dir/.git"
  echo '{"must_not_commit_externally": true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli save -m redirected

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe Git metadata"* ]]
  [ "$(git -C "$external" rev-parse HEAD)" = "$before" ]
  [ "$(cat "$external/canary.txt")" = canary ]
  [ -z "$(git -C "$external" status --porcelain=v1)" ]
}

@test "save rejects a profile git common directory redirected to another repository" {
  run_cli_ok fork default
  local dir external before
  dir="$(profile_dir default)"
  external="$BATS_TEST_TMPDIR/external-common-repository"
  mkdir -p "$external"
  git -C "$external" init -q
  echo canary > "$external/canary.txt"
  git -C "$external" add canary.txt
  git -C "$external" commit -q -m canary
  before="$(git -C "$external" rev-parse HEAD)"
  printf '%s\n' "$external/.git" > "$dir/.git/commondir"
  echo '{"must_not_commit_to_common_dir": true}' > \
    "$CLAUDE_CODE_HOME/settings.json"

  run_cli save -m redirected-common-dir

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe Git metadata"* ]]
  [ "$(git -C "$external" rev-parse HEAD)" = "$before" ]
  [ "$(cat "$external/canary.txt")" = canary ]
  [ -z "$(git -C "$external" status --porcelain=v1)" ]
}

@test "read-only history rejects redirected profile git metadata" {
  run_cli_ok fork default
  local dir external original_git
  dir="$(profile_dir default)"
  external="$BATS_TEST_TMPDIR/external-history-repository"
  original_git="$BATS_TEST_TMPDIR/original-history-git"
  mkdir -p "$external"
  git -C "$external" init -q
  echo canary > "$external/canary.txt"
  git -C "$external" add canary.txt
  git -C "$external" commit -q -m canary
  mv "$dir/.git" "$original_git"
  ln -s "$external/.git" "$dir/.git"

  run_cli history default

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe Git metadata"* ]]
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

@test "custom ignore rules allow deleting a previously tracked ordinary path" {
  mkdir "$CLAUDE_CODE_HOME/local-cache"
  echo secret-v1 > "$CLAUDE_CODE_HOME/local-cache/secret.txt"
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  git -C "$dir" ls-files --error-unmatch -- \
    local-cache/secret.txt >/dev/null

  printf '\n/local-cache\n' >> "$dir/.gitignore"
  rm "$CLAUDE_CODE_HOME/local-cache/secret.txt"
  rmdir "$CLAUDE_CODE_HOME/local-cache"
  run_cli_ok save -m "Ignore local secret"

  [[ "$output" != *"history skipped"* ]]
  [ ! -e "$CLAUDE_CODE_HOME/local-cache" ]
  [ ! -e "$dir/local-cache" ]
  ! git -C "$dir" ls-files --error-unmatch -- \
    local-cache/secret.txt >/dev/null 2>&1
  grep -Fxq /local-cache "$dir/.gitignore"
  [ -z "$(git -C "$dir" status --porcelain=v1)" ]
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
  [ ! -e "$CLAUDE_PROFILE_HOME/.lock" ]
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

@test "refresh replaces managed blocks written by older policy versions" {
  run_cli_ok fork default
  local dir
  dir="$(profile_dir default)"
  cat > "$dir/.gitignore" <<'EOF'
/custom-before
# BEGIN claude-profile managed: history-policy=1
/obsolete-managed-rule
# END claude-profile managed
/custom-after
EOF

  echo changed > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m refresh-policy-version

  grep -Fxq /custom-before "$dir/.gitignore"
  grep -Fxq /custom-after "$dir/.gitignore"
  ! grep -Fxq /obsolete-managed-rule "$dir/.gitignore"
  [ "$(grep -Ec '^# BEGIN claude-profile managed: history-policy=' "$dir/.gitignore")" -eq 1 ]
  grep -Fxq '# BEGIN claude-profile managed: history-policy=2' "$dir/.gitignore"
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
