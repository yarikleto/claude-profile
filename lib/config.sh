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

CLAUDE_DIR="${CLAUDE_CODE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
CLAUDE_JSON_FILE="$HOME/.claude.json"
CLAUDE_JSON_IN_CONFIG_DIR=false
if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  CLAUDE_JSON_FILE="$CLAUDE_DIR/.claude.json"
  CLAUDE_JSON_IN_CONFIG_DIR=true
fi

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
    # A missing ancestor can leave '..' in the tail. Normalize it, then resolve
    # again so a revealed symlink cannot bypass the HOME/ancestor guard.
    local rest="$result/" normalized="" component
    while [[ "$rest" == */* ]]; do
      component="${rest%%/*}"
      rest="${rest#*/}"
      case "$component" in
        ''|.) ;;
        ..) normalized="${normalized%/*}" ;;
        *) normalized="$normalized/$component" ;;
      esac
    done
    normalized="${normalized:-/}"
    if [[ "$normalized" != "$result" ]]; then
      _canonical_path "$normalized"
      return
    fi
    printf '%s\n' "$result"
  else
    printf '%s\n' "$path"
  fi
}

# Refuse nesting: the switch loops clear/copy whole directories, so a store
# inside the live dir (or the reverse) would destroy the store and the original
# backup. Compare _canonical_path output — a raw string compare misses aliases.
_CANON_PROFILES_DIR="$(_canonical_path "$PROFILES_DIR")"
_CANON_CLAUDE_DIR="$(_canonical_path "$CLAUDE_DIR")"
_CANON_HOME="$(_canonical_path "$HOME")"
# Compare the JSON's parent, not its target: saves replace a live JSON symlink
# with a regular file without changing which configuration this store owns.
_CANON_CLAUDE_JSON_FILE="$(_canonical_path "$(dirname "$CLAUDE_JSON_FILE")")/.claude.json"
if [[ -n "${CLAUDE_CONFIG_DIR:-}" && "$CLAUDE_CONFIG_DIR" != /* ]]; then
  err "CLAUDE_CONFIG_DIR must be an absolute path to a dedicated configuration directory"
  exit 1
fi
if [[ "$_CANON_CLAUDE_DIR" == / || "$_CANON_CLAUDE_DIR" == "$_CANON_HOME" ||
      "$_CANON_HOME" == "$_CANON_CLAUDE_DIR"/* ]]; then
  err "Unsafe live config directory ($CLAUDE_DIR): use a dedicated directory, not HOME or an ancestor of HOME"
  exit 1
fi
if [[ -n "${CLAUDE_CODE_HOME:-}" && -n "${CLAUDE_CONFIG_DIR:-}" &&
      "$_CANON_CLAUDE_DIR" != "$(_canonical_path "$CLAUDE_CONFIG_DIR")" ]]; then
  err "CLAUDE_CODE_HOME ($CLAUDE_CODE_HOME) conflicts with CLAUDE_CONFIG_DIR ($CLAUDE_CONFIG_DIR)
Run 'unset CLAUDE_CODE_HOME' to use Claude Code's config directory, or set both to the same directory"
  exit 1
fi
if [[ "$_CANON_PROFILES_DIR" == "$_CANON_CLAUDE_DIR" || "$_CANON_PROFILES_DIR" == "$_CANON_CLAUDE_DIR"/* ]]; then
  err "Profile store ($PROFILES_DIR) must not be inside the live config dir ($CLAUDE_DIR)
Move it elsewhere and update CLAUDE_PROFILE_HOME"
  exit 1
fi
if [[ "$_CANON_CLAUDE_DIR" == "$_CANON_PROFILES_DIR"/* ]]; then
  err "Live config dir ($CLAUDE_DIR) must not be inside the profile store ($PROFILES_DIR)"
  exit 1
fi

CURRENT_FILE="$PROFILES_DIR/.current"
OP_MARKER_FILE="$PROFILES_DIR/.op-in-progress"
STORE_FORMAT_FILE="$PROFILES_DIR/.format"
STORE_LIVE_PATHS_FILE="$PROFILES_DIR/.live-paths"
STORE_FORMAT=3

# Capture this before locking or command setup can create the store directory.
# A truly new store is already in the current format; a pre-existing stamp-less
# store is legacy and must not be marked current if migration is deferred.
STORE_EXISTED_AT_STARTUP=false
if [[ -d "$PROFILES_DIR" ]]; then
  STORE_EXISTED_AT_STARTUP=true
fi

# Store the managed JSON under one reserved name in either live layout. With
# the default layout this keeps a separate ~/.claude/.claude.json payload from
# colliding with the home file. Pre-format-2 migration moves the old root file.
CLAUDE_HOME_JSON=".claude-profile-home.json"

# Seed files for new (empty) profiles so Claude Code doesn't complain.
# Parallel arrays: SEED_NAMES[i] is the filename, SEED_CONTENTS[i] is its content.
SEED_NAMES=("settings.json" ".claude.json")
SEED_CONTENTS=(
  '{}'
  '{}'
)

# Managed gitignore — keeps disposable/session data out of history while
# explicitly versioning Claude Code's durable auto-memory and subagent memory.
# The marker lets restore distinguish commits made before memory was covered:
# absence in those legacy commits means "unknown", not "memory was empty".
GITIGNORE_MANAGED_BEGIN_PREFIX="# BEGIN claude-profile managed: history-policy="
GITIGNORE_MANAGED_VERSION="3"
GITIGNORE_MANAGED_BEGIN="${GITIGNORE_MANAGED_BEGIN_PREFIX}${GITIGNORE_MANAGED_VERSION}"
GITIGNORE_MANAGED_END="# END claude-profile managed"
GITIGNORE_MEMORY_MARKER="# claude-profile-history: persistent-memory-v1"
# Keep path-heavy Git operations fast without approaching ARG_MAX. The byte
# ceiling protects unusually long filenames; the count ceiling avoids hundreds
# of tiny Git subprocesses for ordinary config-heavy profiles.
GIT_PATH_BATCH_MAX=512
GIT_PATH_BATCH_MAX_BYTES=131072
# Root-relative patterns shared by ignore generation, staging, diff and restore.
# Keep legacy runtime roots excluded: upgrading must not start versioning them.
HISTORY_EXCLUDED_PATHS=(
  todos statsig logs plans tasks plugins history.jsonl
  file-history shell-snapshots sessions session-env paste-cache image-cache
  uploads usage-data debug backups cache downloads chrome
  feedback-bundles feedback/drafts skills/.trash
  stats-cache.json remote-settings.json policy-limits.json policy-limits.json.stamp.json
  jobs daemon .last-cleanup .last-update-result.json
  settings.json.bak 'settings.json.bak.*'
  .credentials.json '.credentials.json.*'
)
GITIGNORE_CONTENT="$GITIGNORE_MANAGED_BEGIN
$GITIGNORE_MEMORY_MARKER
!/projects/
/projects/**
!/projects/*/
!/projects/*/memory/
!/projects/*/memory/**
!/agent-memory/
!/agent-memory/**"
for _history_excluded_path in "${HISTORY_EXCLUDED_PATHS[@]}"; do
  GITIGNORE_CONTENT+=$'\n'"/$_history_excluded_path"
done
unset _history_excluded_path
GITIGNORE_CONTENT+=$'\n'"$GITIGNORE_MANAGED_END"

# The exact policy generated by releases before store format 3. During the
# upgrade it is replaced, while lines users appended after this prefix survive.
LEGACY_GITIGNORE_CONTENT="/projects
/agent-memory
/todos
/plans
/tasks
/plugins
/history.jsonl"
