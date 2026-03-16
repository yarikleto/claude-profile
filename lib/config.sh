# config.sh — Constants and managed items configuration

VERSION="0.3.4"
CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"
PROFILES_DIR="$CLAUDE_DIR/__profiles__"
CURRENT_FILE="$PROFILES_DIR/.current"

# Default managed items. Override via ~/.claude/__profiles__/.managed
_DEFAULT_MANAGED_ITEMS=(
  "settings.json"
  "CLAUDE.md"
  "agents"
  "skills"
  "rules"
  "keybindings.json"
  ".claude.json:$HOME/.claude.json"
)

# Bulk items: large data dirs that are moved (not copied) during switch for speed.
# Not tracked by git. Always use cp for fork/save, mv for switch.
_DEFAULT_BULK_ITEMS=(
  "projects"
  "agent-memory"
  "todos"
  "plans"
  "tasks"
  "plugins"
  "history.jsonl"
)

# Seed files for new (empty) profiles so Claude Code doesn't complain.
# Parallel arrays: SEED_NAMES[i] is the filename, SEED_CONTENTS[i] is its content.
SEED_NAMES=("settings.json" ".claude.json")
SEED_CONTENTS=(
  '{ "statusLine": { "type": "command", "command": "~/.claude/__profiles__/statusline.sh" } }'
  '{}'
)

# Match actual parent-directory traversal segments, not ordinary ".." in filenames.
_has_parent_traversal() {
  [[ "$1" =~ (^|/)\.\.(/|$) ]]
}

# Validate a managed item path is safe (no traversal, under $HOME for custom paths).
_validate_managed_item() {
  local item="$1"
  local name path
  if [[ "$item" == *:* ]]; then
    name="${item%%:*}"
    path="${item#*:}"
  else
    name="$item"
    path="$CLAUDE_DIR/$item"
  fi

  if [[ -z "$name" || "$name" == "." || "$name" == ".." || "$name" == */* || "$name" =~ [[:cntrl:]] ]]; then
    err "Invalid managed item '$item': storage name must be a single file or directory name"
    exit 1
  fi

  if _has_parent_traversal "$path"; then
    err "Invalid managed item '$item': path contains '..'"
    exit 1
  fi

  if [[ "$item" == *:* ]]; then
    if [[ "$path" != /* ]]; then
      err "Invalid managed item '$item': path must be absolute"
      exit 1
    fi
    # Check literal path first
    if [[ "$path" != "$HOME" && "$path" != "$HOME"/* ]]; then
      err "Invalid managed item '$item': path must be under \$HOME"
      exit 1
    fi
    # Resolve symlinks in existing parent dirs to catch escapes via symlinked components
    local parent
    parent="$(dirname "$path")"
    if [[ -d "$parent" ]]; then
      local resolved_parent
      resolved_parent="$(cd "$parent" 2>/dev/null && pwd -P)" || resolved_parent="$parent"
      local resolved_home
      resolved_home="$(cd "$HOME" 2>/dev/null && pwd -P)" || resolved_home="$HOME"
      if [[ "$resolved_parent" != "$resolved_home" && "$resolved_parent" != "$resolved_home"/* ]]; then
        err "Invalid managed item '$item': resolved path escapes \$HOME"
        exit 1
      fi
    fi
  fi
}

# Load managed items from config or use defaults.
# Format: "name" (resolved to CLAUDE_DIR/name) or "name:path" (custom path).
_load_managed_items() {
  local config="$PROFILES_DIR/.managed"
  if [[ -f "$config" ]]; then
    MANAGED_ITEMS=()
    local line
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      _validate_managed_item "$line"
      MANAGED_ITEMS+=("$line")
    done < "$config"
  else
    MANAGED_ITEMS=("${_DEFAULT_MANAGED_ITEMS[@]}")
  fi
}

# Resolve the actual filesystem path for a managed item.
_item_source() {
  local item="$1"
  if [[ "$item" == *:* ]]; then
    echo "${item#*:}"
  else
    echo "$CLAUDE_DIR/$item"
  fi
}

# Get the storage name for an item inside the profile directory.
_item_name() {
  local item="$1"
  if [[ "$item" == *:* ]]; then
    echo "${item%%:*}"
  else
    echo "$item"
  fi
}

_load_managed_items

# Load bulk items (currently hardcoded, no override file).
_load_bulk_items() {
  BULK_ITEMS=("${_DEFAULT_BULK_ITEMS[@]}")
}

_load_bulk_items
