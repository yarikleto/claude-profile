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

@test "path: refuses profile store nested inside ~/.claude" {
  export CLAUDE_PROFILE_HOME="$CLAUDE_CODE_HOME/__profiles__"
  run_cli list
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be inside"* ]]
}

@test "path: refuses ~/.claude nested inside the profile store" {
  export CLAUDE_CODE_HOME="$CLAUDE_PROFILE_HOME/live"
  run_cli list
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be inside"* ]]
}

@test "path: refuses a store nested in the live dir spelled with a relative path" {
  mkdir -p "$CLAUDE_CODE_HOME/sub"
  cd "$CLAUDE_CODE_HOME/sub"
  export CLAUDE_PROFILE_HOME="../store"   # canonically inside the live dir
  run_cli list
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be inside"* ]]
}

@test "path: refuses a store nested in the live dir via a symlink alias" {
  ln -s "$CLAUDE_CODE_HOME" "$HOME/alias"
  export CLAUDE_PROFILE_HOME="$HOME/alias/store"   # alias resolves into the live dir
  run_cli list
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be inside"* ]]
}

@test "path: accepts a legitimately symlinked store root" {
  # A symlinked store ROOT that points somewhere outside the live dir is fine —
  # only symlinked individual profile dirs are refused (see save test below).
  local real="$BATS_TEST_TMPDIR/real-store"
  mkdir -p "$real"
  ln -s "$real" "$HOME/store-link"
  export CLAUDE_PROFILE_HOME="$HOME/store-link"
  run_cli_ok fork default
  [ -d "$real/default" ]
}

@test "path: save refuses a symlinked profile root and never touches its target" {
  run_cli_ok fork real
  local ext="$BATS_TEST_TMPDIR/external"
  mkdir -p "$ext"
  echo 'CANARY' > "$ext/canary.txt"
  ln -s "$ext" "$CLAUDE_PROFILE_HOME/evil"

  run_cli save evil
  [ "$status" -ne 0 ]
  [ -f "$ext/canary.txt" ]      # external file survives — no rm -rf through the symlink
}
