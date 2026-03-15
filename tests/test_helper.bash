# test_helper.bash — Shared setup for all test files
#
# Creates a fully isolated environment per test:
# - Fake $HOME with a fake ~/.claude/ structure
# - Fake ~/.claude.json (MCP config)
# - Real settings.json with realistic content
# - Real skills directory with sample files
# The real ~/.claude/ is NEVER touched.

CLAUDE_PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude-profile"

setup() {
  # Isolated home per test
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CODE_HOME="$HOME/.claude"
  mkdir -p "$CLAUDE_CODE_HOME"

  # Git identity (required for commits in isolated HOME)
  git config --global user.name "test"
  git config --global user.email "test@test"

  # Realistic settings.json
  cat > "$CLAUDE_CODE_HOME/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Read", "Glob", "Grep"],
    "defaultMode": "default"
  },
  "effortLevel": "high"
}
JSON

  # Sample skills directory
  mkdir -p "$CLAUDE_CODE_HOME/skills/my-skill"
  echo "---" > "$CLAUDE_CODE_HOME/skills/my-skill/SKILL.md"

  # Sample agents directory
  mkdir -p "$CLAUDE_CODE_HOME/agents"

  # Fake ~/.claude.json (MCP servers)
  cat > "$HOME/.claude.json" <<'JSON'
{
  "mcpServers": {
    "github": { "type": "http", "url": "https://example.com" }
  }
}
JSON
}

# Run claude-profile in the isolated env
run_cli() {
  run bash "$CLAUDE_PROFILE" "$@"
}

# Shorthand: run and assert success
run_cli_ok() {
  run bash "$CLAUDE_PROFILE" "$@"
  if [[ "$status" -ne 0 ]]; then
    echo "FAILED: claude-profile $*"
    echo "STATUS: $status"
    echo "OUTPUT: $output"
  fi
  [ "$status" -eq 0 ]
}

# Get profile directory path
profile_dir() {
  echo "$CLAUDE_CODE_HOME/__profiles__/$1"
}

# Get backup directory path
backup_dir() {
  echo "$CLAUDE_CODE_HOME/__profiles__/.pre-profiles-backup"
}
