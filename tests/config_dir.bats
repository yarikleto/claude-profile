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
