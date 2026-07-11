# state.sh — Profile state: current profile, backup, directory management

ensure_dir() { mkdir -p "$PROFILES_DIR"; }

get_current() {
  if [[ -f "$CURRENT_FILE" ]]; then
    cat "$CURRENT_FILE"
  else
    echo ""
  fi
}

# Like get_current, but validates the stored name and exits with a clear error
# if it fails validation (e.g. path traversal planted by an attacker or
# filesystem corruption). Only call this when the result will be used in a
# path — comparisons and empty-checks don't need it.
get_current_validated() {
  local name
  name="$(get_current)"
  if [[ -z "$name" ]]; then
    echo ""
    return
  fi
  if [[ "$name" =~ [^a-zA-Z0-9._-] || "$name" == ..* || "$name" == .* || "$name" == -* ]]; then
    local display
    display="$(printf '%s' "$name" | tr -d '[:cntrl:]')"
    err ".current file is corrupt (invalid profile name: '$display')."
    err "Run 'claude-profile list' to see available profiles, then 'claude-profile use <name>' to recover."
    exit 1
  fi
  echo "$name"
}

set_current() { echo "$1" > "$CURRENT_FILE"; }
clear_current() { rm -f "$CURRENT_FILE"; }

# ─── Exclusive lock for mutating commands ───────────────────
# Concurrent invocations interleave rm/mv on the same live files; with --move
# semantics that can destroy the sole copy of a profile's data.

_release_lock() { rm -rf "$PROFILES_DIR/.lock"; }

_acquire_lock() {
  ensure_dir
  local lock="$PROFILES_DIR/.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    local pid
    pid="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ -z "$pid" ]]; then
      # The other process may be between mkdir and writing its pid
      sleep 0.2
      pid="$(cat "$lock/pid" 2>/dev/null || true)"
    fi
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      err "Another claude-profile operation is in progress (pid $pid)"
      err "If that is wrong, remove $lock"
      exit 1
    fi
    # Stale lock from a dead process — take it over
    rm -rf "$lock"
    if ! mkdir "$lock" 2>/dev/null; then
      err "Another claude-profile operation is in progress"
      exit 1
    fi
  fi
  echo "$$" > "$lock/pid"
  trap _release_lock EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# ─── Interrupted-operation marker ────────────────────────────
# Written around the destructive phase of use/deactivate and removed only on
# success — a crash leaves it behind so the next run can recover instead of
# auto-saving a half-switched live state into the wrong profile.

_set_op_marker()   { echo "$1" > "$OP_MARKER_FILE"; }
_clear_op_marker() { rm -f "$OP_MARKER_FILE"; }
_get_op_marker() {
  if [[ -f "$OP_MARKER_FILE" ]]; then
    cat "$OP_MARKER_FILE"
  else
    echo ""
  fi
}

_refuse_if_op_interrupted() {
  local op
  op="$(_get_op_marker)"
  if [[ -z "$op" ]]; then
    return 0
  fi
  if [[ "$op" == "use "* ]]; then
    err "A previous switch to '${op#use }' was interrupted"
    err "Run 'claude-profile use ${op#use }' to recover first"
  elif [[ "$op" == "deactivate" ]]; then
    err "A previous deactivate was interrupted"
    err "Run 'claude-profile deactivate' to complete it first"
  else
    err "An interrupted operation left a marker — inspect and remove $OP_MARKER_FILE manually"
  fi
  exit 1
}

# Back up original ~/.claude/ state once, before first use.
# The backup is never modified — it's the "main branch".
# The snapshot lands in a temp dir first: a snapshot that dies partway must
# never leave a half-written directory that later runs accept as the backup.
_backup_raw_state() {
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  if [[ -d "$backup_dir" ]]; then
    return 0
  fi
  local tmp="$backup_dir.tmp"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  info "Backing up original state..."
  _snapshot_current "$tmp"
  mv "$tmp" "$backup_dir"
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

# Validate that a profile name is safe (whitelist approach).
# Allowed: [a-zA-Z0-9._-], must not start with dot or dash.
_validate_profile_name() {
  local name="$1"
  if [[ "$name" =~ [^a-zA-Z0-9._-] || "$name" == ..* || "$name" == .* || "$name" == -* ]]; then
    err "Invalid profile name '$name' (use only letters, numbers, dots, dashes, underscores)"
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
