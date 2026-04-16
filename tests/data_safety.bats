#!/usr/bin/env bats
load test_helper

# ─── Symlinked user files are preserved ──────────────────

@test "fork: captures symlinked settings.json content" {
  # User symlinks settings.json to an external file (e.g. dotfiles repo)
  local external="$BATS_TEST_TMPDIR/dotfiles/claude-settings.json"
  mkdir -p "$(dirname "$external")"
  echo '{"from": "dotfiles"}' > "$external"

  rm "$CLAUDE_CODE_HOME/settings.json"
  ln -s "$external" "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok fork myprofile

  # Profile should have the actual content, not a symlink
  local saved="$(profile_dir myprofile)/settings.json"
  [ -f "$saved" ]
  [ ! -L "$saved" ]
  grep -q '"from": "dotfiles"' "$saved"
}

@test "save: captures symlinked settings.json content" {
  run_cli_ok fork mysave
  run_cli_ok use mysave

  local external="$BATS_TEST_TMPDIR/dotfiles/claude-settings.json"
  mkdir -p "$(dirname "$external")"
  echo '{"saved_from": "symlink"}' > "$external"

  rm "$CLAUDE_CODE_HOME/settings.json"
  ln -s "$external" "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok save -m "save symlink test"

  local saved="$(profile_dir mysave)/settings.json"
  [ -f "$saved" ]
  [ ! -L "$saved" ]
  grep -q '"saved_from": "symlink"' "$saved"
}

@test "deactivate: restores backup even when original was symlinked" {
  # Simulate: user originally had a symlinked .claude.json
  local external="$BATS_TEST_TMPDIR/external-mcp.json"
  echo '{"mcpServers": {"original": true}}' > "$external"
  rm "$HOME/.claude.json"
  ln -s "$external" "$HOME/.claude.json"

  run_cli_ok fork first
  run_cli_ok use first

  # Modify live state
  echo '{"mcpServers": {"modified": true}}' > "$HOME/.claude.json"

  run_cli_ok deactivate

  # Original content should be restored (as regular file, not symlink)
  [ -f "$HOME/.claude.json" ]
  grep -q '"original"' "$HOME/.claude.json"
}

# ─── No silent data loss on switch ───────────────────────

@test "use: auto-saves all managed files before switching" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  # Make changes to every kind of managed item
  echo '{"alpha_settings": true}' > "$CLAUDE_CODE_HOME/settings.json"
  echo "# Alpha CLAUDE.md" > "$CLAUDE_CODE_HOME/CLAUDE.md"
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  echo "alpha-agent" > "$CLAUDE_CODE_HOME/agents/myagent.md"
  echo '{"alpha": "keys"}' > "$CLAUDE_CODE_HOME/keybindings.json"
  echo '{"mcpServers": {"alpha": true}}' > "$HOME/.claude.json"

  # Switch away
  run_cli_ok use beta

  # All alpha changes should be saved in the profile
  local alpha_dir
  alpha_dir="$(profile_dir alpha)"
  grep -q '"alpha_settings"' "$alpha_dir/settings.json"
  grep -q "Alpha CLAUDE.md" "$alpha_dir/CLAUDE.md"
  grep -q "alpha-agent" "$alpha_dir/agents/myagent.md"
  grep -q '"alpha"' "$alpha_dir/keybindings.json"
  grep -q '"alpha"' "$alpha_dir/.claude.json"
}

@test "use: switching back restores all managed files" {
  run_cli_ok fork profile1
  run_cli_ok fork profile2
  run_cli_ok use profile1

  echo '{"profile1": true}' > "$CLAUDE_CODE_HOME/settings.json"
  echo "# Profile1 notes" > "$CLAUDE_CODE_HOME/CLAUDE.md"
  run_cli_ok save -m "profile1 data"

  run_cli_ok use profile2
  echo '{"profile2": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Switch back to profile1
  run_cli_ok use profile1

  grep -q '"profile1"' "$CLAUDE_CODE_HOME/settings.json"
  grep -q "Profile1 notes" "$CLAUDE_CODE_HOME/CLAUDE.md"
}

@test "use: MCP config (.claude.json) is not lost on switch" {
  run_cli_ok fork mcp1
  run_cli_ok fork mcp2

  run_cli_ok use mcp1
  echo '{"mcpServers": {"server-a": {"url": "http://a"}}}' > "$HOME/.claude.json"
  run_cli_ok save -m "mcp1 servers"

  run_cli_ok use mcp2
  echo '{"mcpServers": {"server-b": {"url": "http://b"}}}' > "$HOME/.claude.json"
  run_cli_ok save -m "mcp2 servers"

  # Switch back — mcp1's config should be restored
  run_cli_ok use mcp1
  grep -q "server-a" "$HOME/.claude.json"
  ! grep -q "server-b" "$HOME/.claude.json"
}

# ─── Directory contents preserved through cycles ─────────

@test "skills directory contents survive fork-use-save-switch-use cycle" {
  # Start with realistic skills
  mkdir -p "$CLAUDE_CODE_HOME/skills/my-skill"
  echo "---" > "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md"
  echo "skill content" >> "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md"
  mkdir -p "$CLAUDE_CODE_HOME/skills/another-skill"
  echo "second skill" > "$CLAUDE_CODE_HOME/skills/another-skill/SKILL.md"

  run_cli_ok fork with-skills
  run_cli_ok use with-skills

  # Add a new skill while active
  mkdir -p "$CLAUDE_CODE_HOME/skills/new-skill"
  echo "brand new" > "$CLAUDE_CODE_HOME/skills/new-skill/SKILL.md"
  run_cli_ok save -m "added new skill"

  # Switch away and back
  run_cli_ok fork empty
  run_cli_ok use empty
  run_cli_ok use with-skills

  # All 3 skills should be present
  [ -f "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md" ]
  [ -f "$CLAUDE_CODE_HOME/skills/another-skill/SKILL.md" ]
  [ -f "$CLAUDE_CODE_HOME/skills/new-skill/SKILL.md" ]
  grep -q "brand new" "$CLAUDE_CODE_HOME/skills/new-skill/SKILL.md"
}

@test "agents directory contents survive switching" {
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  echo "agent config" > "$CLAUDE_CODE_HOME/agents/my-agent.md"

  run_cli_ok fork with-agents
  run_cli_ok use with-agents

  run_cli_ok new no-agents
  run_cli_ok use no-agents

  # Agents should be gone in the clean (new) profile
  [ ! -f "$CLAUDE_CODE_HOME/agents/my-agent.md" ]

  # Switch back — agents should return
  run_cli_ok use with-agents
  [ -f "$CLAUDE_CODE_HOME/agents/my-agent.md" ]
  grep -q "agent config" "$CLAUDE_CODE_HOME/agents/my-agent.md"
}

# ─── Original backup is never modified ───────────────────

@test "original backup is never modified after creation" {
  # Capture initial state
  local original_settings
  original_settings="$(cat "$CLAUDE_CODE_HOME/settings.json")"
  local original_mcp
  original_mcp="$(cat "$HOME/.claude.json")"

  run_cli_ok fork first
  run_cli_ok use first

  # Modify everything
  echo '{"completely": "different"}' > "$CLAUDE_CODE_HOME/settings.json"
  echo '{"mcpServers": {"new": true}}' > "$HOME/.claude.json"
  run_cli_ok save -m "changed everything"

  run_cli_ok fork second
  run_cli_ok use second
  echo '{"second": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Backup should still have the original content
  local backup
  backup="$(backup_dir)"
  [ -d "$backup" ]

  local backed_settings
  backed_settings="$(cat "$backup/settings.json")"
  [ "$backed_settings" = "$original_settings" ]

  local backed_mcp
  backed_mcp="$(cat "$backup/.claude.json")"
  [ "$backed_mcp" = "$original_mcp" ]
}

# ─── Failed operations don't corrupt state ────────────────

@test "use: nonexistent profile doesn't corrupt current state" {
  run_cli_ok fork safe
  run_cli_ok use safe

  echo '{"my": "data"}' > "$CLAUDE_CODE_HOME/settings.json"

  # Try to switch to nonexistent — should fail
  run_cli use nonexistent
  [ "$status" -ne 0 ]

  # Current state should be untouched
  grep -q '"my": "data"' "$CLAUDE_CODE_HOME/settings.json"

  # Still on the same profile
  run_cli_ok current
  [[ "$output" == *"safe"* ]]
}

@test "fork: duplicate name doesn't corrupt existing profile" {
  run_cli_ok fork original
  run_cli_ok use original
  echo '{"original": "data"}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "original data"

  run_cli_ok use original
  echo '{"modified": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Try to fork with same name — should fail
  run_cli fork original
  [ "$status" -ne 0 ]

  # Saved profile data should be intact (should have the saved version)
  local profile_settings
  profile_settings="$(profile_dir original)/settings.json"
  [ -f "$profile_settings" ]
}

@test "delete: cannot delete active profile" {
  run_cli_ok fork protected
  run_cli_ok use protected
  echo '{"important": "data"}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli delete -f protected
  [ "$status" -ne 0 ]

  # Profile and live data should be intact
  [ -d "$(profile_dir protected)" ]
  grep -q '"important"' "$CLAUDE_CODE_HOME/settings.json"
}

# ─── Edge cases with file content ─────────────────────────

@test "binary-like content in settings survives round-trip" {
  # Settings with special characters, unicode, escapes
  cat > "$CLAUDE_CODE_HOME/settings.json" <<'JSON'
{
  "prompt": "Use emoji: \ud83d\ude00",
  "path": "C:\\Users\\test",
  "multiline": "line1\nline2\ttab"
}
JSON

  run_cli_ok fork special-chars
  run_cli_ok use special-chars

  run_cli_ok fork other
  run_cli_ok use other
  run_cli_ok use special-chars

  # Content should be byte-identical
  grep -q 'emoji' "$CLAUDE_CODE_HOME/settings.json"
  grep -q 'C:\\\\Users' "$CLAUDE_CODE_HOME/settings.json"
}

@test "empty managed directories are preserved" {
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  mkdir -p "$CLAUDE_CODE_HOME/rules"
  # agents/ and rules/ exist but are empty

  run_cli_ok fork with-empty-dirs
  run_cli_ok use with-empty-dirs

  run_cli_ok fork other
  run_cli_ok use other
  run_cli_ok use with-empty-dirs

  [ -d "$CLAUDE_CODE_HOME/agents" ]
  [ -d "$CLAUDE_CODE_HOME/rules" ]
}

@test "files with spaces in names inside managed dirs are preserved" {
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  echo "agent with spaces" > "$CLAUDE_CODE_HOME/agents/my agent file.md"

  run_cli_ok fork spaced
  run_cli_ok use spaced

  run_cli_ok fork other
  run_cli_ok use other
  run_cli_ok use spaced

  [ -f "$CLAUDE_CODE_HOME/agents/my agent file.md" ]
  grep -q "agent with spaces" "$CLAUDE_CODE_HOME/agents/my agent file.md"
}

# ─── Profile name edge cases ─────────────────────────────

@test "profile name with multiple dots is valid" {
  run_cli_ok fork "v1.2.3"
  [ -d "$(profile_dir v1.2.3)" ]
}

@test "profile name with mixed dashes and underscores is valid" {
  run_cli_ok fork "my_profile-v2"
  [ -d "$(profile_dir my_profile-v2)" ]
}

@test "single character profile name is valid" {
  run_cli_ok fork "a"
  [ -d "$(profile_dir a)" ]
}

@test "numeric profile name is valid" {
  run_cli_ok fork "123"
  [ -d "$(profile_dir 123)" ]
}

# ─── Deactivate fully restores original ──────────────────

@test "deactivate: full round-trip preserves original state exactly" {
  # Capture byte-exact original state
  local orig_settings orig_mcp orig_skill
  orig_settings="$(cat "$CLAUDE_CODE_HOME/settings.json")"
  orig_mcp="$(cat "$HOME/.claude.json")"
  orig_skill="$(cat "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md")"

  # Create profiles, switch around, modify things
  run_cli_ok fork profileA
  run_cli_ok use profileA
  echo '{"different": true}' > "$CLAUDE_CODE_HOME/settings.json"
  echo '{"mcpServers": {"new": true}}' > "$HOME/.claude.json"
  rm -rf "$CLAUDE_CODE_HOME/skills/my-skill"
  run_cli_ok save -m "changed"

  run_cli_ok fork profileB
  run_cli_ok use profileB
  echo '{"another": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Deactivate — should restore exact original state
  run_cli_ok deactivate

  local restored_settings restored_mcp restored_skill
  restored_settings="$(cat "$CLAUDE_CODE_HOME/settings.json")"
  restored_mcp="$(cat "$HOME/.claude.json")"
  restored_skill="$(cat "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md")"

  [ "$restored_settings" = "$orig_settings" ]
  [ "$restored_mcp" = "$orig_mcp" ]
  [ "$restored_skill" = "$orig_skill" ]
}

# ─── Symlink in profile dir is safely ignored on load ─────

@test "use: switching to profile with unreadable dir does not destroy live state" {
  run_cli_ok fork source
  run_cli_ok fork target
  run_cli_ok use source
  echo '{"important": "data"}' > "$CLAUDE_CODE_HOME/settings.json"

  # Now make target profile's skills dir unreadable
  mkdir -p "$(profile_dir target)/skills/locked-skill"
  echo "data" > "$(profile_dir target)/skills/locked-skill/SKILL.md"
  chmod 000 "$(profile_dir target)/skills/locked-skill"

  run_cli use target
  # Live settings should still have source's content (switch should be aborted)
  grep -q '"important"' "$CLAUDE_CODE_HOME/settings.json"
  # Skills from test setup should still be present
  [ -d "$CLAUDE_CODE_HOME/skills" ]

  chmod 755 "$(profile_dir target)/skills/locked-skill" 2>/dev/null || true
}

@test "edit: auto-saves active profile before opening" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"unsaved_edit": true}' > "$CLAUDE_CODE_HOME/settings.json"

  EDITOR=true run_cli_ok edit default
  grep -q '"unsaved_edit"' "$(profile_dir default)/settings.json"
}

@test "use: symlink in profile dir is auto-repaired, no symlink in live" {
  run_cli_ok fork legit
  run_cli_ok fork other

  local target_file="$BATS_TEST_TMPDIR/external-content"
  echo "external data" > "$target_file"

  # Plant a symlink in the profile directory
  rm -f "$(profile_dir legit)/settings.json"
  ln -s "$target_file" "$(profile_dir legit)/settings.json"

  # Auto-repair dereferences the symlink, then loads normally
  run_cli_ok use legit
  [[ "$output" == *"Repaired"* ]]

  # Profile symlink should now be a regular file
  [ ! -L "$(profile_dir legit)/settings.json" ]

  # Live settings must be a regular file with the dereferenced content
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  [ ! -L "$CLAUDE_CODE_HOME/settings.json" ]
  grep -q "external data" "$CLAUDE_CODE_HOME/settings.json"
}

@test "use: symlinked directory in profile dir is auto-repaired" {
  run_cli_ok fork safe-profile
  run_cli_ok fork other

  local ext_dir="$BATS_TEST_TMPDIR/ext-agents"
  mkdir -p "$ext_dir"
  echo "agent content" > "$ext_dir/payload.md"

  # Replace agents dir with a symlink in the profile
  rm -rf "$(profile_dir safe-profile)/agents"
  ln -s "$ext_dir" "$(profile_dir safe-profile)/agents"

  # Auto-repair dereferences the directory symlink
  run_cli_ok use safe-profile
  [[ "$output" == *"Repaired"* ]]

  # Live agents should be a regular directory with the content (not a symlink)
  [ -d "$CLAUDE_CODE_HOME/agents" ]
  [ ! -L "$CLAUDE_CODE_HOME/agents" ]
  grep -q "agent content" "$CLAUDE_CODE_HOME/agents/payload.md"
}
