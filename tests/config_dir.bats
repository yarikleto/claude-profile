#!/usr/bin/env bats
load test_helper

use_config_dir() {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/custom config"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/custom"
  echo '{"config":"original"}' > "$CLAUDE_CONFIG_DIR/settings.json"
  echo '{"mcpServers":{"relocated":{}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  echo custom-skill > "$CLAUDE_CONFIG_DIR/skills/custom/SKILL.md"
  cp "$HOME/.claude.json" "$HOME/outer-canary.json"
  cp "$HOME/.claude/settings.json" "$HOME/default-canary.json"
}

assert_default_untouched() {
  cmp "$HOME/.claude.json" "$HOME/outer-canary.json"
  cmp "$HOME/.claude/settings.json" "$HOME/default-canary.json"
}

prepare_dangling_json_recovery() {
  local live_dir="${CLAUDE_CONFIG_DIR:-$CLAUDE_CODE_HOME}"
  local json_file="$HOME/.claude.json" f
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    json_file="$CLAUDE_CONFIG_DIR/.claude.json"
  fi
  mkdir -p "$live_dir/projects/proj"
  echo transcript > "$live_dir/projects/proj/session.jsonl"
  run_cli_ok fork P
  run_cli_ok new Q
  run_cli_ok use P
  for f in "$live_dir"/* "$live_dir"/.[!.]*; do
    if [[ "$f" != "$json_file" && -e "$f" ]]; then
      mv "$f" "$(profile_dir P)/"
    fi
  done
  rm "$json_file"
  ln -s "$HOME/missing-json" "$json_file"
}

assert_swept_profile_preserved() {
  printf 'op=use\nphase=saving\nsource=P\ntarget=Q\n' > "$CLAUDE_PROFILE_HOME/.op-in-progress"
  local before
  before="$(git -C "$(profile_dir P)" rev-parse HEAD)"
  run_cli_ok use Q
  [ "$(cat "$(profile_dir P)/projects/proj/session.jsonl")" = transcript ]
  [ -f "$(profile_dir P)/settings.json" ]
  [ -f "$(profile_dir P)/.claude-profile-home.json" ]
  [ "$(git -C "$(profile_dir P)" rev-parse HEAD)" = "$before" ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
}

@test "recovery: dangling home JSON does not erase the swept-back profile" {
  prepare_dangling_json_recovery
  assert_swept_profile_preserved
}

@test "recovery: dangling relocated JSON does not erase the swept-back profile" {
  use_config_dir
  prepare_dangling_json_recovery
  assert_swept_profile_preserved
  assert_default_untouched
}

@test "recovery: dangling home JSON still allows reloading lost live files" {
  prepare_dangling_json_recovery
  run_cli_ok use P
  [ "$(cat "$CLAUDE_CODE_HOME/projects/proj/session.jsonl")" = transcript ]
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  [ -f "$HOME/.claude.json" ]
  [ ! -L "$HOME/.claude.json" ]
}

@test "recovery: dangling relocated JSON still allows reloading lost live files" {
  use_config_dir
  prepare_dangling_json_recovery
  run_cli_ok use P
  [ "$(cat "$CLAUDE_CONFIG_DIR/projects/proj/session.jsonl")" = transcript ]
  [ -f "$CLAUDE_CONFIG_DIR/settings.json" ]
  [ -f "$CLAUDE_CONFIG_DIR/.claude.json" ]
  [ ! -L "$CLAUDE_CONFIG_DIR/.claude.json" ]
  assert_default_untouched
}

@test "config dir: collision advice names both JSON sources and the live destination" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new other
  echo work-account > "$(profile_dir original)/.claude.json"
  echo personal-account > "$(profile_dir original)/.claude-profile-home.json"
  run_cli use original
  [ "$status" -ne 0 ]
  [[ "$output" == *"$(profile_dir original)/.claude.json"* ]]
  [[ "$output" == *"$(profile_dir original)/.claude-profile-home.json"* ]]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/.claude.json"* ]]
  [[ "$output" == *"JSON that would be loaded"* ]]
  [[ "$output" == *"migrating-stores-with-two-json-files"* ]]
  [[ "$output" != *"rename its payload"* ]]
  [ "$(cat "$(profile_dir original)/.claude.json")" = work-account ]
  [ "$(cat "$(profile_dir original)/.claude-profile-home.json")" = personal-account ]
}

@test "config dir: saving an incompatible profile preserves both stored JSON files" {
  use_config_dir
  run_cli_ok fork original
  echo old-account > "$(profile_dir original)/.claude.json"
  echo live-edit > "$CLAUDE_CONFIG_DIR/settings.json"
  local before
  before="$(git -C "$(profile_dir original)" rev-parse HEAD)"
  run_cli save
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude.json"*"conflict"* ]]
  [ "$(cat "$(profile_dir original)/.claude.json")" = old-account ]
  grep -q original "$(profile_dir original)/settings.json"
  [ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = live-edit ]
  [ "$(git -C "$(profile_dir original)" rev-parse HEAD)" = "$before" ]
}

@test "config dir: auto-save refuses an incompatible source before moving live files" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new other
  run_cli_ok use original
  echo old-account > "$(profile_dir original)/.claude.json"
  local command
  for command in 'new clean' 'use other' 'deactivate'; do
    run_cli $command
    [ "$status" -ne 0 ]
    [[ "$output" == *".claude.json"*"conflict"* ]]
    [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
    [ "$(cat "$CLAUDE_PROFILE_HOME/.current")" = original ]
    grep -q original "$CLAUDE_CONFIG_DIR/settings.json"
    [ "$(cat "$(profile_dir original)/.claude.json")" = old-account ]
  done
}

@test "config dir: inactive restore refuses a revision that would make the profile unloadable" {
  use_config_dir
  run_cli_ok fork original
  local dir ref before
  dir="$(profile_dir original)"
  echo old-account > "$dir/.claude.json"
  git -C "$dir" add .claude.json
  git -C "$dir" commit -q -m old-layout
  ref="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" rm -q .claude.json
  git -C "$dir" commit -q -m current-layout
  run_cli_ok new other
  before="$(git -C "$dir" rev-parse HEAD)"
  run_cli restore original "$ref"
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude.json"*"conflict"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$before" ]
  [ ! -e "$dir/.claude.json" ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
}

@test "config dir: test helper clears inherited official config paths" {
  run env CLAUDE_CONFIG_DIR="$HOME/outside-test" bash -c '
    source "$1"
    [[ -z "${CLAUDE_CONFIG_DIR+x}" ]]
  ' bash "$BATS_TEST_DIRNAME/test_helper.bash"
  [ "$status" -eq 0 ]
}

@test "config dir: fork captures relocated files and backs up JSON exactly once" {
  use_config_dir
  run_cli_ok fork original

  local dir
  for dir in "$(profile_dir original)" "$(backup_dir)"; do
    cmp "$CLAUDE_CONFIG_DIR/settings.json" "$dir/settings.json"
    cmp "$CLAUDE_CONFIG_DIR/.claude.json" "$dir/.claude-profile-home.json"
    cmp "$CLAUDE_CONFIG_DIR/skills/custom/SKILL.md" "$dir/skills/custom/SKILL.md"
    [ ! -e "$dir/.claude.json" ]
  done
  [ "$(printf '%s\n' "$output" | grep -c '✓.*\.claude.json')" -eq 1 ]
  assert_default_untouched
}

@test "config dir: new and repeated switches round-trip edits and deletions" {
  use_config_dir
  run_cli_ok fork original
  echo '{"mcpServers":{"edited":{}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok new clean
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = '{}' ]
  [ ! -e "$CLAUDE_CONFIG_DIR/skills/custom" ]
  run_cli_ok use original
  grep -q edited "$CLAUDE_CONFIG_DIR/.claude.json"
  [ -f "$CLAUDE_CONFIG_DIR/skills/custom/SKILL.md" ]
  rm "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok use clean
  run_cli_ok use original
  [ ! -e "$CLAUDE_CONFIG_DIR/.claude.json" ]
  [ ! -e "$(profile_dir original)/.claude-profile-home.json" ]
  assert_default_untouched
}

@test "config dir: save and diff track the relocated JSON without duplicate payload" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok diff
  [[ "$output" == *"(no changes)"* ]]
  echo '{"mcpServers":{"changed":{}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok diff
  [[ "$output" == *".claude-profile-home.json"* ]]
  [[ "$output" != *"?? .claude.json"* ]]
  run_cli_ok save -m changed-json
  cmp "$CLAUDE_CONFIG_DIR/.claude.json" "$(profile_dir original)/.claude-profile-home.json"
  [ ! -e "$(profile_dir original)/.claude.json" ]
  run_cli_ok diff
  [[ "$output" == *"(no changes)"* ]]
  rm "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok save
  [ ! -e "$(profile_dir original)/.claude-profile-home.json" ]
  assert_default_untouched
}

@test "config dir: restore reloads relocated JSON and settings from history" {
  use_config_dir
  run_cli_ok fork original
  local ref
  ref="$(git -C "$(profile_dir original)" rev-parse HEAD)"
  echo changed > "$CLAUDE_CONFIG_DIR/settings.json"
  echo changed > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok save
  run_cli_ok restore "$ref"
  grep -q original "$CLAUDE_CONFIG_DIR/settings.json"
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  assert_default_untouched
}

@test "config dir: deactivate restores original relocated files and preserves backup" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new clean
  run_cli_ok deactivate
  cmp "$CLAUDE_CONFIG_DIR/settings.json" "$(backup_dir)/settings.json"
  cmp "$CLAUDE_CONFIG_DIR/.claude.json" "$(backup_dir)/.claude-profile-home.json"
  grep -q relocated "$(backup_dir)/.claude-profile-home.json"
  [ ! -e "$(backup_dir)/.claude.json" ]
  assert_default_untouched
}

@test "config dir: detached checks compare relocated JSON with the original backup" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok deactivate --keep
  run_cli_ok use original
  run_cli_ok deactivate --keep
  echo detached-change > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli use original
  [ "$status" -ne 0 ]
  [[ "$output" == *"not saved in any profile"* ]]
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = detached-change ]
  run_cli_ok deactivate
  local saved=("$CLAUDE_PROFILE_HOME"/detached-*)
  [ "${#saved[@]}" -eq 1 ]
  [ "$(cat "${saved[0]}/.claude-profile-home.json")" = detached-change ]
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  assert_default_untouched
}

@test "config dir: new creates a missing relocated directory" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/missing/claude"
  run_cli_ok new clean
  [ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = '{}' ]
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = '{}' ]
  grep -q github "$HOME/.claude.json"
}

@test "config dir: configuration containing only JSON is saved" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/json-only"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  echo original > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok fork original
  echo changed > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok new clean
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = '{}' ]
  [ "$(cat "$(profile_dir original)/.claude-profile-home.json")" = changed ]
  run_cli_ok use original
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = changed ]
  [ ! -e "$CLAUDE_CONFIG_DIR/settings.json" ]
}

@test "config dir: reload recovers a JSON-only profile into a missing live directory" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/json-only"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  echo original > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok fork original
  rm -rf "${CLAUDE_CONFIG_DIR:?}"
  run_cli_ok use original
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = original ]
}

@test "config dir: restoring an incompatible revision fails before applying it" {
  use_config_dir
  run_cli_ok fork original
  local dir ref current
  dir="$(profile_dir original)"
  echo payload-json > "$dir/.claude.json"
  git -C "$dir" add .claude.json
  git -C "$dir" commit -q -m default-layout
  ref="$(git -C "$dir" rev-parse HEAD)"
  git -C "$dir" rm -q .claude.json
  git -C "$dir" commit -q -m relocated-layout
  current="$(git -C "$dir" rev-parse HEAD)"

  run_cli restore "$ref"

  [ "$status" -ne 0 ]
  [[ "$output" == *".claude.json"*"conflict"* ]]
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  [ ! -e "$dir/.claude.json" ]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$current" ]
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  assert_default_untouched
}

@test "config dir: incompatible edits leave live files intact without recovery marker" {
  use_config_dir
  run_cli_ok fork original
  cat > "$HOME/edit-profile" <<'SH'
#!/bin/sh
echo payload-json > "$1/.claude.json"
SH
  chmod +x "$HOME/edit-profile"
  export EDITOR="$HOME/edit-profile"
  run_cli edit original
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude.json"*"conflict"* ]]
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  [ "$(cat "$(profile_dir original)/.claude.json")" = payload-json ]
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  assert_default_untouched
}

@test "config dir: legacy stored home JSON migrates into the relocated layout" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new target
  mv "$(profile_dir original)/.claude-profile-home.json" "$(profile_dir original)/.claude.json"
  rm "$CLAUDE_PROFILE_HOME/.format"
  run_cli_ok use original
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  [ ! -e "$(profile_dir original)/.claude.json" ]
  assert_default_untouched
}

@test "config dir: interrupted loading returns relocated JSON to its target" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new target
  echo target-json > "$CLAUDE_CONFIG_DIR/.claude.json"
  echo original > "$CLAUDE_PROFILE_HOME/.current"
  echo 'use target' > "$CLAUDE_PROFILE_HOME/.op-in-progress"
  run_cli_ok use target
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = target-json ]
  grep -q relocated "$(profile_dir original)/.claude-profile-home.json"
  [ ! -e "$(profile_dir target)/.claude.json" ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  assert_default_untouched
}

@test "config dir: conflicting overrides fail before any store or live changes" {
  export CLAUDE_CONFIG_DIR="$HOME/official"
  run_cli fork rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLAUDE_CODE_HOME"*"CLAUDE_CONFIG_DIR"* ]]
  [[ "$output" == *"unset CLAUDE_CODE_HOME"* ]]
  [ ! -e "$CLAUDE_PROFILE_HOME" ]
  [ ! -e "$CLAUDE_CONFIG_DIR" ]
  grep -q github "$HOME/.claude.json"
}

@test "config dir: equivalent relative and symlink overrides use relocated JSON" {
  use_config_dir
  ln -s "$CLAUDE_CONFIG_DIR" "$HOME/alias"
  cd "$HOME"
  export CLAUDE_CODE_HOME='./alias/'
  run_cli_ok fork original
  cmp "$CLAUDE_CONFIG_DIR/.claude.json" "$(profile_dir original)/.claude-profile-home.json"
  assert_default_untouched
}

@test "config dir: nesting guards apply to the official config directory" {
  use_config_dir
  export CLAUDE_PROFILE_HOME="$CLAUDE_CONFIG_DIR/store"
  run_cli fork rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"must not be inside"* ]]
  [ ! -e "$CLAUDE_PROFILE_HOME" ]
  assert_default_untouched
}

@test "config dir: empty official variable preserves legacy override behavior" {
  export CLAUDE_CONFIG_DIR=''
  export CLAUDE_CODE_HOME="$HOME/legacy"
  mkdir -p "$CLAUDE_CODE_HOME"
  echo legacy-payload > "$CLAUDE_CODE_HOME/.claude.json"
  run_cli_ok fork original
  [ "$(cat "$(profile_dir original)/.claude.json")" = legacy-payload ]
  cmp "$HOME/.claude.json" "$(profile_dir original)/.claude-profile-home.json"
}

@test "config dir: refuses a profile whose two JSON files would collide" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new target
  run_cli_ok use original
  echo payload-json > "$(profile_dir target)/.claude.json"
  run_cli use target
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude.json"*"conflict"* ]]
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  [ "$(cat "$(profile_dir target)/.claude.json")" = payload-json ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.current")" = original ]
  [ ! -e "$CLAUDE_PROFILE_HOME/.op-in-progress" ]
  assert_default_untouched
}

@test "config dir: refuses a modern payload-only JSON before switching" {
  use_config_dir
  run_cli_ok fork original
  run_cli_ok new target
  run_cli_ok use original
  rm "$(profile_dir target)/.claude-profile-home.json"
  echo payload-json > "$(profile_dir target)/.claude.json"
  run_cli use target
  [ "$status" -ne 0 ]
  [[ "$output" == *".claude.json"*"conflict"* ]]
  grep -q relocated "$CLAUDE_CONFIG_DIR/.claude.json"
  [ "$(cat "$(profile_dir target)/.claude.json")" = payload-json ]
}

@test "config dir: broken relocated JSON symlink refuses a snapshot" {
  use_config_dir
  rm "$CLAUDE_CONFIG_DIR/.claude.json"
  ln -s "$HOME/missing-json" "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli fork rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"Broken symlink"* ]]
  [ -L "$CLAUDE_CONFIG_DIR/.claude.json" ]
  [ ! -e "$(backup_dir)" ]
  assert_default_untouched
}

@test "config dir: save reports a broken JSON symlink in an otherwise empty live directory" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/json-only"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  echo original > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok fork original
  rm "$CLAUDE_CONFIG_DIR/.claude.json"
  ln -s "$HOME/missing-json" "$CLAUDE_CONFIG_DIR/.claude.json"

  run_cli save

  [ "$status" -ne 0 ]
  [[ "$output" == *"Broken symlink"* ]]
  [ -L "$CLAUDE_CONFIG_DIR/.claude.json" ]
  [ "$(cat "$(profile_dir original)/.claude-profile-home.json")" = original ]
}

@test "config dir: help displays the resolved live paths" {
  use_config_dir
  run_cli_ok help
  [[ "$output" == *"$CLAUDE_CONFIG_DIR"* ]]
  [[ "$output" == *"$CLAUDE_CONFIG_DIR/.claude.json"* ]]
}

@test "config dir: refuses the home directory and its ancestors before creating a store" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_PROFILE_HOME="$BATS_TEST_TMPDIR/store"
  local path
  for path in "$HOME" "$HOME/.." "$HOME/not-created/.." /; do
    export CLAUDE_CONFIG_DIR="$path"
    run_cli new rejected
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsafe live config directory"* ]]
    [ ! -e "$CLAUDE_PROFILE_HOME" ]
    grep -q github "$HOME/.claude.json"
  done
}

@test "config dir: refuses a symlink to the home directory" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_PROFILE_HOME="$BATS_TEST_TMPDIR/store"
  ln -s "$HOME" "$BATS_TEST_TMPDIR/home-alias"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/home-alias"
  run_cli new rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsafe live config directory"* ]]
  [ ! -e "$CLAUDE_PROFILE_HOME" ]
}

@test "config dir: relative official paths cannot switch the current project" {
  unset CLAUDE_CODE_HOME
  mkdir -p "$HOME/project"
  echo project-source > "$HOME/project/main.go"
  cd "$HOME/project"
  export CLAUDE_CONFIG_DIR=.
  run_cli new rejected
  [ "$status" -ne 0 ]
  [[ "$output" == *"CLAUDE_CONFIG_DIR must be an absolute path"* ]]
  [ "$(cat main.go)" = project-source ]
  [ ! -e "$CLAUDE_PROFILE_HOME" ]
}
