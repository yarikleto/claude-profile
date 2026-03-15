#!/usr/bin/env bats
load test_helper

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # Isolated HOME
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # Install to isolated location
  export CLAUDE_PROFILE_INSTALL_DIR="$BATS_TEST_TMPDIR/bin"
  export CLAUDE_PROFILE_COMPLETIONS_DIR="$BATS_TEST_TMPDIR/completions"
  mkdir -p "$CLAUDE_PROFILE_COMPLETIONS_DIR"
}

@test "installs binary to INSTALL_DIR" {
  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_PROFILE_INSTALL_DIR/claude-profile" ]
  [ -x "$CLAUDE_PROFILE_INSTALL_DIR/claude-profile" ]
}

@test "installs lib and commands modules" {
  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]

  local lib="$CLAUDE_PROFILE_INSTALL_DIR/claude-profile-lib"
  [ -f "$lib/lib/config.sh" ]
  [ -f "$lib/lib/output.sh" ]
  [ -f "$lib/lib/state.sh" ]
  [ -f "$lib/lib/files.sh" ]
  [ -f "$lib/lib/git.sh" ]
  [ -f "$lib/commands/profile.sh" ]
  [ -f "$lib/commands/info.sh" ]
  [ -f "$lib/commands/history.sh" ]
  [ -f "$lib/commands/ui.sh" ]
}

@test "installed binary works" {
  bash "$REPO_DIR/install.sh" >/dev/null 2>&1
  export CLAUDE_CODE_HOME="$HOME/.claude"
  mkdir -p "$CLAUDE_CODE_HOME"
  git config --global user.name "test"
  git config --global user.email "test@test"

  run bash "$CLAUDE_PROFILE_INSTALL_DIR/claude-profile" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-profile"* ]]
}

@test "installed binary can create and use profiles" {
  bash "$REPO_DIR/install.sh" >/dev/null 2>&1
  export CLAUDE_CODE_HOME="$HOME/.claude"
  mkdir -p "$CLAUDE_CODE_HOME"
  git config --global user.name "test"
  git config --global user.email "test@test"
  echo '{"test": true}' > "$CLAUDE_CODE_HOME/settings.json"

  local cp="$CLAUDE_PROFILE_INSTALL_DIR/claude-profile"
  run bash "$cp" fork default
  [ "$status" -eq 0 ]
  run bash "$cp" use default
  [ "$status" -eq 0 ]
  run bash "$cp" list
  [[ "$output" == *"default"* ]]
}

@test "installs completions to COMPLETIONS_DIR" {
  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  # At least one completion file should exist
  local count
  count="$(find "$CLAUDE_PROFILE_COMPLETIONS_DIR" -type f | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ]
}

@test "prints success message" {
  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installation complete"* ]]
}
