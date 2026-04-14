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

@test "use: rejects profile with symlink in profile directory" {
  run_cli_ok fork symusetest
  run_cli_ok fork other

  local secret="$BATS_TEST_TMPDIR/secret"
  echo "TOP SECRET" > "$secret"

  # Replace a file in the profile with a symlink
  rm "$(profile_dir symusetest)/settings.json"
  ln -s "$secret" "$(profile_dir symusetest)/settings.json"

  # Validation should reject the profile entirely
  run_cli use symusetest
  [ "$status" -ne 0 ]
  [[ "$output" == *"Symlink"* ]]

  # The live settings.json should not contain the secret
  if [[ -f "$CLAUDE_CODE_HOME/settings.json" ]]; then
    ! grep -q "TOP SECRET" "$CLAUDE_CODE_HOME/settings.json"
  fi
}

@test "use: rejects nested symlinks inside managed directories" {
  local secret="$BATS_TEST_TMPDIR/secret.txt"
  echo "TOP SECRET" > "$secret"

  mkdir -p "$CLAUDE_PROFILE_HOME/symlinked/skills"
  ln -s "$secret" "$(profile_dir symlinked)/skills/outside"

  git -C "$(profile_dir symlinked)" init -q
  git -C "$(profile_dir symlinked)" add -A
  git -C "$(profile_dir symlinked)" \
    -c user.name=test -c user.email=test@test commit -q -m "init"

  run_cli use symlinked
  [ "$status" -ne 0 ]
  [ ! -L "$CLAUDE_CODE_HOME/skills/outside" ]
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
