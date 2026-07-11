#!/usr/bin/env bats
load test_helper

@test "copies profile files into live location" {
  run_cli_ok fork default
  run_cli_ok new clean
  run_cli_ok use clean

  # New profile has minimal seeded config
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  [ -f "$HOME/.claude.json" ]
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]
}

@test "switches back restores files" {
  run_cli_ok fork default
  run_cli_ok new clean
  run_cli_ok use clean
  run_cli_ok use default

  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "auto-saves current profile before switching" {
  run_cli_ok fork default
  # fork auto-activates default
  echo '{"changed_while_active": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok new other
  # new auto-saves default before activating other

  local dir="$(profile_dir default)"
  grep -q '"changed_while_active"' "$dir/settings.json"
}

@test "sets current profile marker" {
  run_cli_ok fork default
  run_cli_ok use default

  [ -f "$CLAUDE_PROFILE_HOME/.current" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.current")" = "default" ]
}

@test "no-op when already active" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli use default
  [ "$status" -eq 0 ]
  [[ "$output" == *"already active"* ]]
}

@test "fails on nonexistent profile" {
  run_cli use nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "use: clears .claude.json when target profile has none" {
  run_cli_ok fork with-mcp
  run_cli_ok new no-mcp
  # Switch away so auto-save of no-mcp is done
  run_cli_ok use with-mcp
  [ -f "$HOME/.claude.json" ]

  # Remove the stored home file from no-mcp AFTER auto-save has run
  rm -f "$(profile_dir no-mcp)/.claude-profile-home.json"

  run_cli_ok use no-mcp
  # .claude.json should be gone since no-mcp profile doesn't have it
  [ ! -f "$HOME/.claude.json" ]
}

@test "MCP config switches correctly" {
  run_cli_ok fork default
  run_cli_ok new nomcp
  run_cli_ok use nomcp
  # New profile has minimal seeded .claude.json (no MCP servers)
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]

  run_cli_ok use default
  [ -f "$HOME/.claude.json" ]
  grep -q '"mcpServers"' "$HOME/.claude.json"
}

@test "use: reloads active profile when live config was lost" {
  run_cli_ok fork default

  # Simulate an interrupted switch: live state gone, .current still set
  rm -rf "$CLAUDE_CODE_HOME"
  mkdir -p "$CLAUDE_CODE_HOME"
  rm -f "$HOME/.claude.json"

  run_cli use default
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  [ -f "$HOME/.claude.json" ]
}

@test "use: recovers an interrupted switch without corrupting the previous profile" {
  # Two profiles with distinct content, work active
  echo '{"who": "home"}' > "$CLAUDE_CODE_HOME/settings.json"
  mkdir -p "$CLAUDE_CODE_HOME/todos"
  echo "home todo" > "$CLAUDE_CODE_HOME/todos/t.md"
  run_cli_ok fork home
  run_cli_ok new work
  echo '{"who": "work"}' > "$CLAUDE_CODE_HOME/settings.json"
  mkdir -p "$CLAUDE_CODE_HOME/todos"
  echo "work todo" > "$CLAUDE_CODE_HOME/todos/t.md"

  # Simulate `use home` dying mid-load: auto-save of work completed...
  mv "$CLAUDE_CODE_HOME/settings.json" "$(profile_dir work)/settings.json"
  rm -rf "$(profile_dir work)/todos"
  mv "$CLAUDE_CODE_HOME/todos" "$(profile_dir work)/todos"
  cp "$HOME/.claude.json" "$(profile_dir work)/.claude.json"
  # ...then home's load moved only settings.json before the crash
  rm -f "$HOME/.claude.json"
  mv "$(profile_dir home)/settings.json" "$CLAUDE_CODE_HOME/settings.json"
  echo "use home" > "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli use home
  [ "$status" -eq 0 ]
  [[ "$output" == *"interrupted"* ]]

  # home fully live
  grep -q '"who": "home"' "$CLAUDE_CODE_HOME/settings.json"
  grep -q "home todo" "$CLAUDE_CODE_HOME/todos/t.md"
  [ -f "$HOME/.claude.json" ]
  # work profile intact — not polluted by home's partial files
  grep -q '"who": "work"' "$(profile_dir work)/settings.json"
  grep -q "work todo" "$(profile_dir work)/todos/t.md"
}

@test "use: deleted ~/.claude.json does not resurrect after a switch round-trip" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  rm -f "$HOME/.claude.json"
  run_cli_ok use beta
  run_cli_ok use alpha

  [ ! -f "$HOME/.claude.json" ]
}

@test "use: rejects unexpected extra argument" {
  run_cli_ok fork alpha
  run_cli_ok fork beta

  run_cli use alpha beta
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected argument"* ]]
}

@test "use: recovers a switch interrupted during the outgoing save without deleting the source's data" {
  echo '{"who":"A"}' > "$CLAUDE_CODE_HOME/settings.json"
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  echo 'AGENT-A' > "$CLAUDE_CODE_HOME/agents/a.md"
  run_cli_ok fork A
  run_cli_ok new B
  run_cli_ok use A

  # Simulate `use B` dying mid outgoing-save of A: settings.json already moved
  # into A's profile dir and gone from live, agents/ not yet moved. The
  # saving-phase marker is written BEFORE the first destructive move.
  mv "$CLAUDE_CODE_HOME/settings.json" "$(profile_dir A)/settings.json"
  printf 'op=use\nphase=saving\nsource=A\ntarget=B\n' > "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli use B
  [ "$status" -eq 0 ]
  [[ "$output" == *"interrupted"* ]]

  # A's sole copy of settings.json survived — not deleted by an exact-sync save
  grep -q '"who":"A"' "$(profile_dir A)/settings.json"
  grep -q 'AGENT-A' "$(profile_dir A)/agents/a.md"
  # The switch to B completed
  [ "$(cat "$CLAUDE_PROFILE_HOME/.current")" = "B" ]
}

@test "use: recovery at the save/load boundary keeps the target profile's .claude.json intact" {
  echo '{"mcp":"SRC"}' > "$HOME/.claude.json"
  run_cli_ok fork src
  run_cli_ok new dst
  echo '{"mcp":"DST"}' > "$HOME/.claude.json"
  run_cli_ok save dst
  run_cli_ok use src        # dst locked with DST config, src active with SRC

  # Simulate `use dst` interrupted at the save->load boundary. The fix leaves
  # live fully empty at that point (the outgoing --move clears ~/.claude.json
  # too), so recovery has nothing of src's to leak into dst.
  find "$CLAUDE_CODE_HOME" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  rm -f "$HOME/.claude.json"
  printf 'op=use\nphase=loading\nsource=src\ntarget=dst\n' > "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli use dst
  [ "$status" -eq 0 ]
  # dst's stored MCP config was never overwritten by src's
  grep -q '"mcp":"DST"' "$(profile_dir dst)/.claude-profile-home.json"
  grep -q '"mcp":"DST"' "$HOME/.claude.json"
}

@test "use: summary shows live contents after target profile is moved thin" {
  run_cli_ok fork alpha
  run_cli_ok fork beta

  run_cli use alpha
  [[ "$status" -eq 0 \
    && "$output" == *"Active profile: alpha"* \
    && "$output" == *"settings.json"* \
    && "$output" == *"skills"* \
    && "$output" == *".claude.json"* ]]
}
