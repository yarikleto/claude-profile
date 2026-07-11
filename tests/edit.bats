#!/usr/bin/env bats
load test_helper

@test "edit: honors EDITOR including arguments" {
  run_cli_ok fork default

  # Neutralize any real `code` on PATH; the fake editor records its args
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/code"
  chmod +x "$BATS_TEST_TMPDIR/bin/code"
  cat > "$BATS_TEST_TMPDIR/bin/fakeed" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$FAKEED_OUT"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/fakeed"
  export FAKEED_OUT="$BATS_TEST_TMPDIR/fakeed.out"

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" EDITOR="fakeed --flag" run_cli edit default
  [ "$status" -eq 0 ]
  [ -f "$FAKEED_OUT" ]
  grep -qx -- '--flag' "$FAKEED_OUT"
  grep -q "$(profile_dir default)" "$FAKEED_OUT"
}

@test "edit: a blocking editor's change to the active profile lands in live and survives a save" {
  run_cli_ok fork default

  # A blocking editor that rewrites the profile dir's settings.json
  local ed="$BATS_TEST_TMPDIR/ed.sh"
  cat > "$ed" <<'EOF'
#!/bin/bash
echo '{"edited":"by-editor"}' > "$1/settings.json"
EOF
  chmod +x "$ed"

  EDITOR="$ed" run_cli_ok edit default

  # The edit is now the authoritative live state, not stranded in the profile dir
  grep -q '"edited"' "$CLAUDE_CODE_HOME/settings.json"

  # A later save keeps it — it is not overwritten from a stale live copy
  run_cli_ok save -m "after edit"
  grep -q '"edited"' "$(profile_dir default)/settings.json"
}

@test "edit: editing a non-active profile does not disturb live config" {
  run_cli_ok fork active
  run_cli_ok fork other
  run_cli_ok use active
  echo '{"live":"active-state"}' > "$CLAUDE_CODE_HOME/settings.json"

  local ed="$BATS_TEST_TMPDIR/ed.sh"
  cat > "$ed" <<'EOF'
#!/bin/bash
echo '{"edited":"other"}' > "$1/settings.json"
EOF
  chmod +x "$ed"

  EDITOR="$ed" run_cli_ok edit other

  # Live still belongs to the active profile — editing 'other' left it alone
  grep -q '"active-state"' "$CLAUDE_CODE_HOME/settings.json"
  grep -q '"edited"' "$(profile_dir other)/settings.json"
}

@test "edit: refuses while a switch is interrupted" {
  run_cli_ok fork default
  echo "use default" > "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli edit default
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted"* ]]
}
