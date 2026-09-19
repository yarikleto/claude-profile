#!/usr/bin/env bats
load test_helper

@test "docs: explain the official config directory and safe test isolation" {
  local repo_root
  repo_root="$(dirname "$CLAUDE_PROFILE")"

  grep -F '| `CLAUDE_CONFIG_DIR` |' "$repo_root/docs/configuration.md"
  grep -F '$CLAUDE_CONFIG_DIR/.claude.json' "$repo_root/docs/configuration.md"
  grep -F 'unset CLAUDE_CODE_HOME' "$repo_root/docs/configuration.md"
  grep -F 'export CLAUDE_CONFIG_DIR=' "$repo_root/README.md"
  grep -F 'unset CLAUDE_CONFIG_DIR' "$repo_root/CLAUDE.md"
  ! grep -F 'which `claude-profile` does not read' "$repo_root/docs/configuration.md"
}

@test "docs: custom config upgrades preserve the original backup" {
  local repo_root
  repo_root="$(dirname "$CLAUDE_PROFILE")"

  grep -F '### Upgrading with a custom config directory' "$repo_root/docs/configuration.md"
  grep -F 'one stable live directory per profile store' "$repo_root/docs/configuration.md"
  grep -F 'export CLAUDE_PROFILE_HOME="$HOME/.local/share/claude-profile-work"' "$repo_root/README.md"
  grep -F 'fresh `CLAUDE_PROFILE_HOME`' "$repo_root/docs/configuration.md"
}

@test "docs: home-file recovery matches the current store format" {
  local repo_root stored_name
  repo_root="$(dirname "$CLAUDE_PROFILE")"
  stored_name="$(sed -n 's/^CLAUDE_HOME_JSON="\([^"]*\)"/\1/p' "$repo_root/lib/config.sh")"

  [ -n "$stored_name" ]
  grep -F 'live_json="$live_dir/.claude.json"' "$repo_root/docs/migration.md"
  grep -F '"$saved_dir/.claude-profile-home.json" "$live_json"' "$repo_root/docs/migration.md"
  grep -F "$stored_name" "$repo_root/docs/configuration.md" \
    | grep -F 'stored copy of ~/.claude.json'
  grep -F "$stored_name" "$repo_root/docs/configuration.md" \
    | grep -F '**Git-tracked**'
  [ "$(grep -F "$stored_name" "$repo_root/docs/architecture.md" \
    | grep -Fc 'stored copy of ~/.claude.json')" -eq 2 ]
  grep -F '.claude.json                        # template for ~/.claude.json' \
    "$repo_root/docs/architecture.md"
  grep -F 'migration.md#manual-file-recovery' "$repo_root/docs/uninstall.md"
  ! grep -F 'rm -f ~/.claude.json' "$repo_root/docs/uninstall.md"

  ! grep -F "YOUR_PROFILE/.claude.json ~/.claude.json" "$repo_root/docs/migration.md"
  ! grep -F 'stored as `.claude.json` inside each profile directory' "$repo_root/docs/architecture.md"
  ! grep -E '^[[:space:]]*mv -f ~/\.claude/\.claude\.json ~/\.claude\.json' "$repo_root/docs/uninstall.md"
}

run_documented_recovery() {
  local repo_root script="$BATS_TEST_TMPDIR/manual-recovery.sh"
  repo_root="$(dirname "$CLAUDE_PROFILE")"
  awk '/<!-- BEGIN manual-file-recovery -->/{copy=1;next} /<!-- END manual-file-recovery -->/{copy=0} copy && !/^```/{print}' \
    "$repo_root/docs/migration.md" | sed 's/YOUR_PROFILE/original/g' > "$script"
  [ -s "$script" ]
  run env TMPDIR="$BATS_TEST_TMPDIR" bash "$script"
  [ "$status" -eq 0 ]
}

@test "docs: manual recovery restores default settings and account JSON" {
  run_cli_ok fork original
  run_cli_ok new clean
  run_documented_recovery
  cmp "$CLAUDE_CODE_HOME/settings.json" "$(profile_dir original)/settings.json"
  cmp "$HOME/.claude.json" "$(profile_dir original)/.claude-profile-home.json"
}

@test "docs: manual recovery preserves current files in a private persistent directory" {
  run_cli_ok fork original
  echo current-settings > "$CLAUDE_CODE_HOME/settings.json"
  echo current-account > "$HOME/.claude.json"
  run_documented_recovery
  local recovery_dir
  recovery_dir="$(printf '%s\n' "$output" | sed -n 's/^Current files preserved in //p')"
  [[ "$recovery_dir" == "$HOME/"* ]]
  [ "$(cat "$recovery_dir/live/settings.json")" = current-settings ]
  [ "$(cat "$recovery_dir/account.json")" = current-account ]
  [ "$(LC_ALL=C ls -ld "$recovery_dir" | cut -c1-10)" = drwx------ ]
}

@test "docs: manual recovery uses relocated paths without touching the default account" {
  unset CLAUDE_CODE_HOME
  export CLAUDE_CONFIG_DIR="$HOME/work"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  echo work-settings > "$CLAUDE_CONFIG_DIR/settings.json"
  echo work-account > "$CLAUDE_CONFIG_DIR/.claude.json"
  run_cli_ok fork original
  run_cli_ok new clean
  run_documented_recovery
  [ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = work-settings ]
  [ "$(cat "$CLAUDE_CONFIG_DIR/.claude.json")" = work-account ]
  grep -q github "$HOME/.claude.json"
  grep -q effortLevel "$HOME/.claude/settings.json"
}

@test "docs: ambiguous legacy JSON migration preserves both source files" {
  local doc="$(dirname "$CLAUDE_PROFILE")/docs/configuration.md"
  grep -F '### Migrating stores with two JSON files' "$doc"
  grep -F 'real account JSON' "$doc"
  grep -F 'fresh store' "$doc"
  grep -F 'original store and its backup' "$doc"
  ! grep -F 'rename the' "$doc"
}
