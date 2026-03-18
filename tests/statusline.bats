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

@test "statusline install respects custom CLAUDE_PROFILE_HOME in script path" {
  export CLAUDE_PROFILE_HOME="$HOME/custom-profiles"
  mkdir -p "$CLAUDE_PROFILE_HOME"
  echo '{"existing":true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok statusline install

  grep -Fq "\"command\": \"$CLAUDE_PROFILE_HOME/statusline.sh\"" \
    "$CLAUDE_CODE_HOME/settings.json"
}
