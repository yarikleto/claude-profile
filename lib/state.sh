# state.sh — Profile state: current profile, backup, directory management

ensure_dir() { mkdir -p "$PROFILES_DIR"; }

get_current() {
  if [[ -f "$CURRENT_FILE" ]]; then
    cat "$CURRENT_FILE"
  else
    echo ""
  fi
}

set_current() { echo "$1" > "$CURRENT_FILE"; }
clear_current() { rm -f "$CURRENT_FILE"; }

# Back up original ~/.claude/ state once, before first use.
# The backup is never modified — it's the "main branch".
_backup_raw_state() {
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  [[ -d "$backup_dir" ]] && return
  mkdir -p "$backup_dir"
  info "Backing up original state..."
  _snapshot_current "$backup_dir"
}

_ensure_seed_dir() {
  local seed_dir="$PROFILES_DIR/.seed"
  [[ -d "$seed_dir" ]] && return
  mkdir -p "$seed_dir"
  local i
  for i in "${!SEED_NAMES[@]}"; do
    echo "${SEED_CONTENTS[$i]}" > "$seed_dir/${SEED_NAMES[$i]}"
  done
}

_ensure_original_backup() {
  ensure_dir
  _backup_raw_state
  _ensure_seed_dir
}

# Validate that a profile name is safe (no path traversal, no flag injection).
_validate_profile_name() {
  local name="$1"
  if [[ "$name" =~ [/[:cntrl:]] || "$name" == ..* || "$name" == .* || "$name" == -* ]]; then
    err "Invalid profile name '$name' (must start with alphanumeric, no slashes or dots)"
    exit 1
  fi
}

# Require a profile name, exit with error if empty.
_require_profile_name() {
  local name="$1" usage="$2"
  if [[ -z "$name" ]]; then
    err "Usage: $usage"
    exit 1
  fi
  _validate_profile_name "$name"
}

# Require a profile directory to exist, exit with error if not.
_require_profile_exists() {
  local name="$1"
  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir" ]]; then
    err "Profile '$name' not found"
    exit 1
  fi
}
