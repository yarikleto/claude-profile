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
  [ "$status" -eq 0 ]
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

# ─── Zsh completion auto-detection ───────────────────────────

@test "zsh completions: installs to oh-my-zsh when available" {
  unset CLAUDE_PROFILE_COMPLETIONS_DIR
  export SHELL="/bin/zsh"
  mkdir -p "$HOME/.oh-my-zsh/completions"

  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.oh-my-zsh/completions/_claude-profile" ]
  # Should NOT also install to ~/.zfunc
  [ ! -f "$HOME/.zfunc/_claude-profile" ]
}

@test "zsh completions: oh-my-zsh file has correct content" {
  unset CLAUDE_PROFILE_COMPLETIONS_DIR
  export SHELL="/bin/zsh"
  mkdir -p "$HOME/.oh-my-zsh/completions"

  bash "$REPO_DIR/install.sh" >/dev/null 2>&1
  # Installed file should match the source
  diff "$REPO_DIR/completions/claude-profile.zsh" "$HOME/.oh-my-zsh/completions/_claude-profile"
}

@test "zsh completions: falls back to ~/.zfunc without oh-my-zsh" {
  unset CLAUDE_PROFILE_COMPLETIONS_DIR
  export SHELL="/bin/zsh"

  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.zfunc/_claude-profile" ]
  # Verify content matches source
  diff "$REPO_DIR/completions/claude-profile.zsh" "$HOME/.zfunc/_claude-profile"
}

@test "zsh completions: prints fpath instructions when .zshrc missing .zfunc" {
  unset CLAUDE_PROFILE_COMPLETIONS_DIR
  export SHELL="/bin/zsh"
  echo 'export PATH="/usr/bin:$PATH"' > "$HOME/.zshrc"

  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fpath="* ]]
  [[ "$output" == *".zfunc"* ]]
  [[ "$output" == *"compinit"* ]]
}

@test "zsh completions: prints fpath instructions when no .zshrc exists" {
  unset CLAUDE_PROFILE_COMPLETIONS_DIR
  export SHELL="/bin/zsh"
  # No .zshrc at all

  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enable tab completions (zsh)"* ]]
  [[ "$output" == *"fpath="* ]]
}

@test "zsh completions: no fpath instructions when .zshrc already has .zfunc" {
  unset CLAUDE_PROFILE_COMPLETIONS_DIR
  export SHELL="/bin/zsh"
  echo 'fpath=(~/.zfunc $fpath)' > "$HOME/.zshrc"

  run bash "$REPO_DIR/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Enable tab completions (zsh)"* ]]
}
