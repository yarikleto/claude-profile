# config.sh — Constants and managed items configuration

VERSION="0.2.0"
CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"
PROFILES_DIR="$CLAUDE_DIR/profiles"
CURRENT_FILE="$PROFILES_DIR/.current"

# Default managed items. Override via ~/.claude/profiles/.managed
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
)

# Validate a managed item path is safe (no traversal, under $HOME for custom paths).
_validate_managed_item() {
  local item="$1"
  local path
  if [[ "$item" == *:* ]]; then
    path="${item#*:}"
  else
    path="$CLAUDE_DIR/$item"
  fi
  # Reject path traversal components
  if [[ "$path" == *..* ]]; then
    err "Invalid managed item '$item': path contains '..'"
    exit 1
  fi
  # Resolve and verify custom paths are under $HOME
  if [[ "$item" == *:* ]]; then
    local resolved
    resolved="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" 2>/dev/null || resolved="$path"
    if [[ "$resolved" != "$HOME"/* ]]; then
      err "Invalid managed item '$item': path must be under \$HOME"
      exit 1
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
