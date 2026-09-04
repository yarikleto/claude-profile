#!/usr/bin/env bats
load test_helper

# ─── Profile name validation ─────────────────────────────

@test "new: rejects name with path traversal (../)" {
  run_cli new "../../evil"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name with slash" {
  run_cli new "foo/bar"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name starting with dash" {
  run_cli new "-rf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name starting with dot" {
  run_cli new ".hidden"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name that is just dots" {
  run_cli new ".."
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "fork: rejects path traversal name" {
  run_cli fork "../../../tmp/pwned"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "use: rejects path traversal name" {
  run_cli use "../../.ssh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "delete: rejects path traversal name" {
  run_cli delete -f "../../.config"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "show: rejects path traversal name" {
  run_cli show "../../../etc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "save: rejects path traversal name" {
  run_cli save "../../evil" -m "test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name with backslash (terminal escape injection)" {
  run_cli fork 'test\033escape'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name with spaces" {
  run_cli fork "my profile"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: rejects name with special characters" {
  run_cli fork 'test$name'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "new: accepts valid name with dots and dashes" {
  run_cli_ok fork "my-profile.v2"
  [ -d "$(profile_dir my-profile.v2)" ]
}

@test "new: accepts valid name with underscores" {
  run_cli_ok fork "my_profile"
  [ -d "$(profile_dir my_profile)" ]
}

@test "new: accepts valid name with alphanumeric, dots, dashes, underscores" {
  run_cli_ok fork "my-profile_v2.0"
  [ -d "$(profile_dir my-profile_v2.0)" ]
}

# ─── Symlink safety ──────────────────────────────────────

@test "fork: follows live symlinks but stores as regular files" {
  local secret="$BATS_TEST_TMPDIR/secret"
  echo "TOP SECRET" > "$secret"

  rm "$CLAUDE_CODE_HOME/settings.json"
  ln -s "$secret" "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok fork symtest

  local profile_settings
  profile_settings="$(profile_dir symtest)/settings.json"
  # Content SHOULD be captured (live symlinks are trusted)
  [ -f "$profile_settings" ]
  grep -q "TOP SECRET" "$profile_settings"
  # But stored as a regular file, not a symlink
  [ ! -L "$profile_settings" ]
}

@test "fork: dereferences nested symlinks inside subdirectories" {
  local target_file="$BATS_TEST_TMPDIR/target.txt"
  echo "LINKED CONTENT" > "$target_file"

  mkdir -p "$CLAUDE_CODE_HOME/plugins/cache"
  ln -s "$target_file" "$CLAUDE_CODE_HOME/plugins/cache/linked.md"

  run_cli_ok fork nesttest

  local stored
  stored="$(profile_dir nesttest)/plugins/cache/linked.md"
  [ -f "$stored" ]
  grep -q "LINKED CONTENT" "$stored"
  [ ! -L "$stored" ]
}

@test "save: dereferences nested symlinks inside subdirectories" {
  run_cli_ok fork savesymtest
  run_cli_ok use savesymtest

  local target_file="$BATS_TEST_TMPDIR/target.txt"
  echo "NESTED LINK" > "$target_file"

  mkdir -p "$CLAUDE_CODE_HOME/plugins/cache"
  ln -s "$target_file" "$CLAUDE_CODE_HOME/plugins/cache/linked.md"

  run_cli_ok save -m "save with nested symlink"

  local stored
  stored="$(profile_dir savesymtest)/plugins/cache/linked.md"
  [ -f "$stored" ]
  grep -q "NESTED LINK" "$stored"
  [ ! -L "$stored" ]
}

@test "save: skips the redundant profile walk after copy materializes symlinks" {
  run_cli_ok fork materialized-save

  local target_file="$BATS_TEST_TMPDIR/materialized-target.txt"
  local profile_dir_path="$(profile_dir materialized-save)"
  local wrapper_dir="$BATS_TEST_TMPDIR/materialized-find-wrapper"
  local profile_walk="$BATS_TEST_TMPDIR/profile-walk-observed"
  local real_find
  real_find="$(command -v find)"
  echo "MATERIALIZED CONTENT" > "$target_file"
  ln -s "$target_file" "$CLAUDE_CODE_HOME/skills/my-skill/linked.md"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/find" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "$PROFILE_DIR_FOR_TEST" ]]; then
  : > "$PROFILE_WALK_FOR_TEST"
fi
exec "$REAL_FIND_FOR_TEST" "$@"
EOF
  chmod +x "$wrapper_dir/find"

  run env PATH="$wrapper_dir:$PATH" \
    REAL_FIND_FOR_TEST="$real_find" \
    PROFILE_DIR_FOR_TEST="$profile_dir_path" \
    PROFILE_WALK_FOR_TEST="$profile_walk" \
    /bin/bash "$CLAUDE_PROFILE" save -m materialized-copy

  [ "$status" -eq 0 ]
  [ ! -e "$profile_walk" ]
  [ ! -L "$profile_dir_path/skills/my-skill/linked.md" ]
  [ "$(git -C "$profile_dir_path" show HEAD:skills/my-skill/linked.md)" = \
    "MATERIALIZED CONTENT" ]
}

@test "use: auto-repairs top-level symlink in profile" {
  run_cli_ok fork symusetest
  run_cli_ok fork other

  local secret="$BATS_TEST_TMPDIR/secret"
  echo "TOP SECRET" > "$secret"

  rm "$(profile_dir symusetest)/settings.json"
  ln -s "$secret" "$(profile_dir symusetest)/settings.json"

  run_cli_ok use symusetest
  [[ "$output" == *"Repaired"* ]]

  [ ! -L "$(profile_dir symusetest)/settings.json" ]

  grep -q "TOP SECRET" "$CLAUDE_CODE_HOME/settings.json"
}

@test "use: auto-repairs nested symlinks inside managed directories" {
  local secret="$BATS_TEST_TMPDIR/secret.txt"
  echo "TOP SECRET" > "$secret"

  mkdir -p "$CLAUDE_PROFILE_HOME/symlinked/skills"
  ln -s "$secret" "$(profile_dir symlinked)/skills/outside"

  git -C "$(profile_dir symlinked)" init -q
  git -C "$(profile_dir symlinked)" add -A
  git -C "$(profile_dir symlinked)" \
    -c user.name=test -c user.email=test@test commit -q -m "init"

  run_cli_ok use symlinked
  [[ "$output" == *"Repaired"* ]]

  [ ! -L "$CLAUDE_CODE_HOME/skills/outside" ]
  grep -q "TOP SECRET" "$CLAUDE_CODE_HOME/skills/outside"
}

@test "use: rejects profile with broken symlink" {
  run_cli_ok fork brokenlink
  run_cli_ok fork other

  ln -s "/nonexistent/path/file.txt" "$(profile_dir brokenlink)/bad"

  run_cli use brokenlink
  [ "$status" -ne 0 ]
  [[ "$output" == *"Broken symlink"* ]]
  # The offending path is named so the user can fix it
  [[ "$output" == *"bad"* ]]
}

@test "use: rejects unreadable regular files in profile" {
  run_cli_ok fork target
  run_cli_ok fork other

  chmod 000 "$(profile_dir target)/settings.json"

  run_cli use target
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unreadable"* ]] || [[ "$output" == *"unreadable"* ]]
}

@test "statusline install: does not overwrite an existing symlink target" {
  mkdir -p "$CLAUDE_PROFILE_HOME"
  echo '{"statusLine":null}' > "$CLAUDE_CODE_HOME/settings.json"

  local target="$BATS_TEST_TMPDIR/target.txt"
  echo "original" > "$target"
  ln -s "$target" "$CLAUDE_PROFILE_HOME/statusline.sh"

  run_cli statusline install
  [ "$status" -ne 0 ]

  local target_contents
  target_contents="$(cat "$target")"
  [ "$target_contents" = "original" ]
}

# ─── Temp file cleanup ───────────────────────────────────

@test "diff: cleans up temp directory even on failure" {
  run_cli_ok fork tmptest
  run_cli_ok use tmptest

  echo "secret" > "$CLAUDE_CODE_HOME/CLAUDE.md"
  chmod 000 "$CLAUDE_CODE_HOME/CLAUDE.md"

  local tmp_before
  tmp_before="$(find "$BATS_TEST_TMPDIR" -mindepth 1 -maxdepth 1 -type d -name 'tmp.*' | wc -l | tr -d ' ')"

  run env TMPDIR="$BATS_TEST_TMPDIR" bash "$CLAUDE_PROFILE" diff tmptest
  [ "$status" -ne 0 ]

  local tmp_after
  tmp_after="$(find "$BATS_TEST_TMPDIR" -mindepth 1 -maxdepth 1 -type d -name 'tmp.*' | wc -l | tr -d ' ')"

  [ "$tmp_after" -eq "$tmp_before" ]
}
