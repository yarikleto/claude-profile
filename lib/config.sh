# config.sh — Constants and path resolution

VERSION="2.0.0"
CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"

# Storage location: CLAUDE_PROFILE_HOME > XDG_DATA_HOME/claude-profile > ~/.local/share/claude-profile
if [[ -n "${CLAUDE_PROFILE_HOME:-}" ]]; then
  PROFILES_DIR="$CLAUDE_PROFILE_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  PROFILES_DIR="$XDG_DATA_HOME/claude-profile"
else
  PROFILES_DIR="$HOME/.local/share/claude-profile"
fi

CURRENT_FILE="$PROFILES_DIR/.current"

# Seed files for new (empty) profiles so Claude Code doesn't complain.
# Parallel arrays: SEED_NAMES[i] is the filename, SEED_CONTENTS[i] is its content.
SEED_NAMES=("settings.json" ".claude.json")
SEED_CONTENTS=(
  '{}'
  '{}'
)

# Static gitignore — keeps git history fast (only small config files tracked)
# while everything is still copied/moved.
GITIGNORE_CONTENT="/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl"

# Match actual parent-directory traversal segments, not ordinary ".." in filenames.
_has_parent_traversal() {
  [[ "$1" =~ (^|/)\.\.(/|$) ]]
}
