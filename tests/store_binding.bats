#!/usr/bin/env bats
load test_helper

create_work_store() {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/work-config"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  echo work-settings > "$CLAUDE_CONFIG_DIR/settings.json"
  echo work-account > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok fork work
  run_cli_ok new clean
}

@test "store binding: mutating commands reject a different live directory before changes" {
  create_work_store
  unset CLAUDE_CONFIG_DIR
  local command
  for command in 'use work' 'deactivate' 'save clean' 'new another' 'fork another' 'edit work' 'delete work -f' 'restore work HEAD' 'statusline install'; do
    run_cli $command
    [ "$status" -ne 0 ]
    [[ "$output" == *"different live configuration"* ]]
    [[ "$output" == *"CLAUDE_PROFILE_HOME"* ]]
    grep -q effortLevel "$HOME/.claude/settings.json"
    grep -q github "$HOME/.claude.json"
    [ "$(cat "$(profile_dir work)/settings.json")" = work-settings ]
    [ "$(cat "$(backup_dir)/.claude-profile-home.json")" = work-account ]
    [ "$(cat "$CLAUDE_PROFILE_HOME/.current")" = clean ]
    [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  done
}

@test "store binding: changing only the managed JSON location is refused" {
  run_cli_ok fork default
  export CLAUDE_CONFIG_DIR="$CLAUDE_CODE_HOME"
  run_cli new rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"different live configuration"* ]]
  [ ! -e "$(profile_dir rejected)" ]
  grep -q github "$HOME/.claude.json"
}

@test "store binding: equivalent aliases remain usable" {
  create_work_store
  ln -s "$CLAUDE_CONFIG_DIR" "$HOME/work-alias"
  export CLAUDE_CONFIG_DIR="$HOME/work-alias/"
  run_cli_ok use work
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = work-account ]
}

@test "store binding: settings and JSON can be restored after their directory disappears" {
  create_work_store
  rm -rf "${CLAUDE_CONFIG_DIR:?}"
  run_cli_ok use work
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = work-account ]
}

@test "store binding: normal saves replace JSON symlinks without changing the binding" {
  create_work_store
  run_cli_ok use work
  mv "$CLAUDE_CONFIG_DIR/.claude.json" "$HOME/external-json"
  ln -s "$HOME/external-json" "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok use clean
  run_cli_ok use work
  [ ! -L "$CLAUDE_CONFIG_DIR/.claude.json" ]
  [ "$(cat "$HOME/external-json")" = work-account ]
}

@test "store binding: read-only history stays accessible but live diff refuses a mismatch" {
  create_work_store
  unset CLAUDE_CONFIG_DIR
  run_cli_ok list
  run_cli_ok history work
  run_cli diff clean
  [ "$status" -ne 0 ]
  [[ "$output" == *"different live configuration"* ]]
}

@test "store binding: a mismatch does not run store format migration" {
  create_work_store
  echo 2 > "$CLAUDE_PROFILE_HOME/.format"
  unset CLAUDE_CONFIG_DIR
  run_cli new rejected
  [ "$status" -ne 0 ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
  run_cli_ok list
  [ "$(cat "$CLAUDE_PROFILE_HOME/.format")" = 2 ]
}

@test "store binding: existing unbound stores adopt the configured paths on the first write" {
  run_cli_ok fork default
  rm -f "$CLAUDE_PROFILE_HOME/.live-paths"
  local before
  before="$(cat "$(backup_dir)/settings.json")"
  run_cli_ok save
  [ -f "$CLAUDE_PROFILE_HOME/.live-paths" ]
  [ "$(cat "$(backup_dir)/settings.json")" = "$before" ]
  export CLAUDE_CODE_HOME="$HOME/different"
  run_cli new rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"different live configuration"* ]]
}

@test "store binding: symlinked or malformed binding metadata is never overwritten" {
  create_work_store
  rm -f "$CLAUDE_PROFILE_HOME/.live-paths"
  echo canary > "$HOME/external-binding"
  ln -s "$HOME/external-binding" "$CLAUDE_PROFILE_HOME/.live-paths"
  run_cli save
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/external-binding")" = canary ]
  [ -L "$CLAUDE_PROFILE_HOME/.live-paths" ]
  rm "$CLAUDE_PROFILE_HOME/.live-paths"
  echo malformed > "$CLAUDE_PROFILE_HOME/.live-paths"
  run_cli save
  [ "$status" -ne 0 ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.live-paths")" = malformed ]
}
