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

@test "new: accepts valid name with dots and dashes" {
  run_cli_ok fork "my-profile.v2"
  [ -d "$(profile_dir my-profile.v2)" ]
}

@test "new: accepts valid name with underscores" {
  run_cli_ok fork "my_profile"
  [ -d "$(profile_dir my_profile)" ]
}

# ─── Symlink safety ──────────────────────────────────────

@test "fork: does not follow symlinks in managed items" {
  local secret="$BATS_TEST_TMPDIR/secret"
  echo "TOP SECRET" > "$secret"

  # Replace a managed item with a symlink to the secret
  rm "$CLAUDE_CODE_HOME/settings.json"
  ln -s "$secret" "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok fork symtest

  # The profile should NOT contain the secret file's content
  local profile_settings
  profile_settings="$(profile_dir symtest)/settings.json"
  if [[ -f "$profile_settings" ]]; then
    ! grep -q "TOP SECRET" "$profile_settings"
  fi
  # The profile entry should not be a symlink
  [ ! -L "$profile_settings" ]
}

@test "use: does not follow symlinks in profile directories" {
  run_cli_ok fork symusetest

  local secret="$BATS_TEST_TMPDIR/secret"
  echo "TOP SECRET" > "$secret"

  # Replace a file in the profile with a symlink
  rm "$(profile_dir symusetest)/settings.json"
  ln -s "$secret" "$(profile_dir symusetest)/settings.json"

  run_cli_ok use symusetest

  # The live settings.json should not contain the secret
  if [[ -f "$CLAUDE_CODE_HOME/settings.json" ]]; then
    ! grep -q "TOP SECRET" "$CLAUDE_CODE_HOME/settings.json"
  fi
}

# ─── .managed validation ─────────────────────────────────

@test "rejects .managed entries with path traversal" {
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__"
  echo "evil:$HOME/../../etc/passwd" > "$CLAUDE_CODE_HOME/__profiles__/.managed"

  run_cli fork managed-test
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid managed item"* ]]
}

@test "rejects .managed entries with .. component" {
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__"
  echo "evil:../../../etc/shadow" > "$CLAUDE_CODE_HOME/__profiles__/.managed"

  run_cli fork managed-test
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid managed item"* ]]
}

@test "accepts valid .managed entries under HOME" {
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__"
  echo "settings.json" > "$CLAUDE_CODE_HOME/__profiles__/.managed"

  run_cli_ok fork managed-ok
}

@test ".managed storage name cannot escape the profile directory" {
  mkdir -p "$CLAUDE_CODE_HOME/__profiles__"
  echo "../escape:$HOME/.claude.json" > "$CLAUDE_CODE_HOME/__profiles__/.managed"

  run_cli fork managed-name-escape
  [ ! -e "$CLAUDE_CODE_HOME/__profiles__/escape" ]
}

@test "valid custom .managed entry still works when target parent directory is absent" {
  local custom_dir="$HOME/custom-config"
  local custom_file="$custom_dir/settings.override.json"

  mkdir -p "$CLAUDE_CODE_HOME/__profiles__" "$custom_dir"
  echo '{"custom":true}' > "$custom_file"
  echo "custom:$custom_file" > "$CLAUDE_CODE_HOME/__profiles__/.managed"

  run_cli_ok fork managed-custom
  run_cli_ok new other

  rm -rf "$custom_dir"

  run_cli_ok use managed-custom
  [ -f "$custom_file" ]
  grep -q '"custom":true' "$custom_file"
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
