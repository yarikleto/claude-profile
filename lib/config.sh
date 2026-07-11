# config.sh — Constants and path resolution

VERSION_FILE="${CLAUDE_PROFILE_VERSION_FILE:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/VERSION}"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "claude-profile: missing VERSION at $VERSION_FILE" >&2
  exit 1
fi

VERSION="$(sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;}' "$VERSION_FILE")"
if [[ -z "$VERSION" ]]; then
  echo "claude-profile: missing version in $VERSION_FILE" >&2
  exit 1
fi
unset VERSION_FILE

CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"

# Storage location: CLAUDE_PROFILE_HOME > XDG_DATA_HOME/claude-profile > ~/.local/share/claude-profile
if [[ -n "${CLAUDE_PROFILE_HOME:-}" ]]; then
  PROFILES_DIR="$CLAUDE_PROFILE_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  PROFILES_DIR="$XDG_DATA_HOME/claude-profile"
else
  PROFILES_DIR="$HOME/.local/share/claude-profile"
fi

# Canonicalize a path that may not fully exist yet: resolve the deepest
# existing ancestor with `pwd -P` (following symlinks and normalizing `..`,
# trailing slashes, and relative spellings), then re-append the missing tail.
# macOS `realpath`/`readlink -f` aren't dependable, so do it in the shell.
_canonical_path() {
  local path="$1" tail="" dir parent base
  dir="$path"
  while [[ ! -e "$dir" ]]; do
    base="$(basename "$dir")"
    tail="/$base$tail"
    parent="$(dirname "$dir")"
    if [[ "$parent" == "$dir" ]]; then
      break
    fi
    dir="$parent"
  done
  local canon
  if canon="$(cd "$dir" 2>/dev/null && pwd -P)"; then
    [[ "$canon" == "/" ]] && canon=""
    local result="$canon$tail"
    [[ -z "$result" ]] && result="/"
    printf '%s\n' "$result"
  else
    printf '%s\n' "$path"
  fi
}

# Refuse pathological nesting — the switch logic clears/copies whole
# directories, so a store inside the live dir (or the reverse) would let those
# loops destroy the store itself, including the original backup. Compare
# CANONICAL paths so a trailing slash, `..`, a relative spelling, or a symlink
# alias can't smuggle the store inside the live dir past a raw string compare.
_CANON_PROFILES_DIR="$(_canonical_path "$PROFILES_DIR")"
_CANON_CLAUDE_DIR="$(_canonical_path "$CLAUDE_DIR")"
if [[ "$_CANON_PROFILES_DIR" == "$_CANON_CLAUDE_DIR" || "$_CANON_PROFILES_DIR" == "$_CANON_CLAUDE_DIR"/* ]]; then
  err "Profile store ($PROFILES_DIR) must not be inside the live config dir ($CLAUDE_DIR)"
  err "Move it elsewhere and update CLAUDE_PROFILE_HOME"
  exit 1
fi
if [[ "$_CANON_CLAUDE_DIR" == "$_CANON_PROFILES_DIR"/* ]]; then
  err "Live config dir ($CLAUDE_DIR) must not be inside the profile store ($PROFILES_DIR)"
  exit 1
fi

CURRENT_FILE="$PROFILES_DIR/.current"
OP_MARKER_FILE="$PROFILES_DIR/.op-in-progress"
STORE_FORMAT_FILE="$PROFILES_DIR/.format"
STORE_FORMAT=2

# The home-level ~/.claude.json is stored inside a profile under this reserved
# name, keeping it in a namespace disjoint from the live payload — a live file
# literally named ~/.claude/.claude.json is captured as the payload entry
# ".claude.json" and no longer collides with (or is overwritten by) the home
# file. Profiles written before format 2 kept the home file at the root as
# ".claude.json"; startup migration moves it here.
CLAUDE_HOME_JSON=".claude-profile-home.json"

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
