#!/usr/bin/env bats
load test_helper

@test "path: XDG_DATA_HOME used when CLAUDE_PROFILE_HOME unset" {
  local xdg_dir="$HOME/custom-xdg"
  mkdir -p "$xdg_dir"
  run env -u CLAUDE_PROFILE_HOME XDG_DATA_HOME="$xdg_dir" \
    bash "$CLAUDE_PROFILE" fork xdg-test
  [ "$status" -eq 0 ]
  [ -d "$xdg_dir/claude-profile/xdg-test" ]
}

@test "path: default ~/.local/share/claude-profile when both unset" {
  run env -u CLAUDE_PROFILE_HOME -u XDG_DATA_HOME \
    bash "$CLAUDE_PROFILE" fork default-test
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/share/claude-profile/default-test" ]
}

@test "path: CLAUDE_PROFILE_HOME takes precedence over XDG_DATA_HOME" {
  local custom="$HOME/custom" xdg="$HOME/xdg"
  mkdir -p "$custom" "$xdg"
  run env CLAUDE_PROFILE_HOME="$custom" XDG_DATA_HOME="$xdg" \
    bash "$CLAUDE_PROFILE" fork priority-test
  [ "$status" -eq 0 ]
  [ -d "$custom/priority-test" ]
  [ ! -d "$xdg/claude-profile/priority-test" ]
}
