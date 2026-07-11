#!/usr/bin/env bats
load test_helper

@test "statusline install bootstraps profiles dir when missing" {
  rm -rf "$CLAUDE_PROFILE_HOME"

  run_cli_ok statusline install

  [ -f "$CLAUDE_PROFILE_HOME/statusline.sh" ]
  grep -q '"statusLine"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "statusline install: does not corrupt minified settings.json" {
  echo '{"permissions":{"allow":["Read"],"defaultMode":"default"},"effortLevel":"high"}' \
    > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok statusline install
  grep -q '"statusLine"' "$CLAUDE_CODE_HOME/settings.json"
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  local open close
  open="$(tr -cd '{' < "$CLAUDE_CODE_HOME/settings.json" | wc -c | tr -d ' ')"
  close="$(tr -cd '}' < "$CLAUDE_CODE_HOME/settings.json" | wc -c | tr -d ' ')"
  [ "$open" -eq "$close" ]
}

@test "statusline install: works with pretty-printed settings.json" {
  run_cli_ok statusline install
  grep -q '"statusLine"' "$CLAUDE_CODE_HOME/settings.json"
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "statusline install: skips if already configured" {
  echo '{"statusLine": {"type": "command", "command": "test"}}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli statusline install
  [ "$status" -eq 0 ]
  [[ "$output" == *"already configured"* ]]
}

@test "statusline: bare invocation shows usage instead of installing" {
  run_cli statusline
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
  [ ! -f "$CLAUDE_PROFILE_HOME/statusline.sh" ]
}

@test "statusline install: preserves a symlinked settings.json" {
  command -v jq &>/dev/null || skip "test targets the jq code path"
  local real="$BATS_TEST_TMPDIR/dotfiles-settings.json"
  mv "$CLAUDE_CODE_HOME/settings.json" "$real"
  ln -s "$real" "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok statusline install
  [ -L "$CLAUDE_CODE_HOME/settings.json" ]
  grep -q '"statusLine"' "$real"
}

@test "statusline install: invalid settings.json reported as such" {
  command -v jq &>/dev/null || command -v python3 &>/dev/null || command -v node &>/dev/null \
    || skip "no JSON tool available"
  echo '{"broken":' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli statusline install
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
  [[ "$output" != *"no jq"* ]]
}

@test "statusline install: unwritable settings dir fails honestly, preserves the file" {
  command -v jq &>/dev/null || skip "test targets the jq code path"
  local before
  before="$(cat "$CLAUDE_CODE_HOME/settings.json")"

  chmod 555 "$CLAUDE_CODE_HOME"
  run_cli statusline install
  chmod 755 "$CLAUDE_CODE_HOME"

  [ "$status" -ne 0 ]
  [[ "$output" != *"configured"* ]]
  # The original file is untouched — never truncated — and still valid JSON
  [ "$(cat "$CLAUDE_CODE_HOME/settings.json")" = "$before" ]
  jq -e . "$CLAUDE_CODE_HOME/settings.json" >/dev/null
}

@test "statusline install respects custom CLAUDE_PROFILE_HOME in script path" {
  export CLAUDE_PROFILE_HOME="$HOME/custom-profiles"
  mkdir -p "$CLAUDE_PROFILE_HOME"
  echo '{"existing":true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok statusline install

  grep -Fq "\"command\": \"$CLAUDE_PROFILE_HOME/statusline.sh\"" \
    "$CLAUDE_CODE_HOME/settings.json"
}
