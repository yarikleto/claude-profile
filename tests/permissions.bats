#!/usr/bin/env bats
load test_helper

# Portable "octal mode of a path" — macOS stat differs from GNU stat.
_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

@test "permissions: profile store root is not accessible to group/other" {
  run_cli_ok fork default
  local mode
  mode="$(_mode "$CLAUDE_PROFILE_HOME")"
  [ "$mode" = "700" ]
}

@test "permissions: newly created profile dir is private" {
  run_cli_ok fork default
  local mode
  mode="$(_mode "$(profile_dir default)")"
  # No group/other bits — private to the owner
  [[ "$mode" == 7?? ]]
  [[ "$mode" == ?00 ]]
}

@test "permissions: git objects are unreachable behind a 700 store root" {
  run_cli_ok fork default
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "change"
  # Even if inner objects are group/world-readable, a 700 root blocks traversal.
  local mode
  mode="$(_mode "$CLAUDE_PROFILE_HOME")"
  [ "$mode" = "700" ]
}

@test "permissions: an existing group-readable store is tightened on next run" {
  run_cli_ok fork default
  chmod 755 "$CLAUDE_PROFILE_HOME"
  run_cli_ok list
  local mode
  mode="$(_mode "$CLAUDE_PROFILE_HOME")"
  [ "$mode" = "700" ]
}
