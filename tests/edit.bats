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

@test "edit: refuses while a switch is interrupted" {
  run_cli_ok fork default
  echo "use default" > "$CLAUDE_PROFILE_HOME/.op-in-progress"

  run_cli edit default
  [ "$status" -ne 0 ]
  [[ "$output" == *"interrupted"* ]]
}
