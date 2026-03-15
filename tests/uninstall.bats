#!/usr/bin/env bats
load test_helper

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # Isolated HOME
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # Install to isolated location first
  export CLAUDE_PROFILE_INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
  export CLAUDE_PROFILE_COMPLETIONS_DIR="$BATS_TEST_TMPDIR/completions"
  mkdir -p "$CLAUDE_PROFILE_COMPLETIONS_DIR"
  bash "$REPO_DIR/install.sh" >/dev/null 2>&1
}

@test "removes binary" {
  [ -f "$CLAUDE_PROFILE_INSTALL_DIR/claude-profile" ]
  run bash "$REPO_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$CLAUDE_PROFILE_INSTALL_DIR/claude-profile" ]
}

@test "removes lib modules" {
  local lib="$CLAUDE_PROFILE_INSTALL_DIR/claude-profile-lib"
  [ -d "$lib" ]
  run bash "$REPO_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -d "$lib" ]
}

@test "removes completions" {
  # Place a completion file where uninstall looks for it
  mkdir -p "$HOME/.local/share/zsh/site-functions"
  cp "$REPO_DIR/completions/claude-profile.zsh" "$HOME/.local/share/zsh/site-functions/_claude-profile"

  run bash "$REPO_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/share/zsh/site-functions/_claude-profile" ]
}

@test "preserves profiles directory" {
  export CLAUDE_CODE_HOME="$HOME/.claude"
  mkdir -p "$CLAUDE_CODE_HOME/profiles/myprofile"
  echo "data" > "$CLAUDE_CODE_HOME/profiles/myprofile/settings.json"

  run bash "$REPO_DIR/uninstall.sh"
  [ "$status" -eq 0 ]

  # Profiles must still exist
  [ -d "$CLAUDE_CODE_HOME/profiles/myprofile" ]
  [ -f "$CLAUDE_CODE_HOME/profiles/myprofile/settings.json" ]
}

@test "prints success message" {
  run bash "$REPO_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uninstall complete"* ]]
}

@test "hints about manual profile cleanup" {
  run bash "$REPO_DIR/uninstall.sh"
  [[ "$output" == *"Profiles are kept"* ]]
  [[ "$output" == *"delete manually"* ]]
}

@test "idempotent — running twice doesn't fail" {
  bash "$REPO_DIR/uninstall.sh" >/dev/null 2>&1
  run bash "$REPO_DIR/uninstall.sh"
  [ "$status" -eq 0 ]
}
