# state.sh — Profile state: current profile, backup, directory management

ensure_dir() {
  mkdir -p "$PROFILES_DIR"
  # Tighten the store root even if an older run (or install) created it with a
  # looser umask — a 0700 root blocks other local users from traversing to the
  # Git objects inside, which git itself writes group/world-readable.
  chmod 700 "$PROFILES_DIR" 2>/dev/null || true
}

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

# A per-process ownership token, written into the lock when we claim it. Only
# a matching token releases the lock — a process that lost a takeover race must
# never delete the new owner's lock on EXIT.
_LOCK_TOKEN=""

_release_lock() {
  local lock="$PROFILES_DIR/.lock"
  if [[ -n "$_LOCK_TOKEN" && "$(cat "$lock/token" 2>/dev/null || true)" == "$_LOCK_TOKEN" ]]; then
    rm -rf "$lock"
  fi
}

_acquire_lock() {
  ensure_dir
  local lock="$PROFILES_DIR/.lock"
  _LOCK_TOKEN="$$-${RANDOM}${RANDOM}"

  local attempt
  for attempt in 1 2 3; do
    if mkdir "$lock" 2>/dev/null; then
      echo "$$" > "$lock/pid"
      printf '%s\n' "$_LOCK_TOKEN" > "$lock/token"
      trap _release_lock EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      return 0
    fi

    # Lock exists — is its owner still alive?
    local pid
    pid="$(cat "$lock/pid" 2>/dev/null || true)"
    if [[ -z "$pid" ]]; then
      # The owner may be between mkdir and writing its pid
      sleep 0.2
      pid="$(cat "$lock/pid" 2>/dev/null || true)"
    fi
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      err "Another claude-profile operation is in progress (pid $pid)"
      err "If that is wrong, remove $lock"
      exit 1
    fi

    # Stale lock from a dead owner. Claim the takeover atomically: rename the
    # exact stale directory aside. `rename` on a single source succeeds for
    # only one racer, so two contenders can't both clear the same lock and
    # proceed. If our rename lost (another racer already took over, or the
    # owner revived and the lock is now a live one), fall through to retry —
    # the next mkdir fails and the liveness check reports "in progress".
    local stash="$lock.stale.$$.$attempt"
    if mv "$lock" "$stash" 2>/dev/null; then
      # Guard the exotic case where we grabbed a *fresh* lock from a racer that
      # already took over: if its owner is alive, restore it and stand down.
      local spid
      spid="$(cat "$stash/pid" 2>/dev/null || true)"
      if [[ "$spid" =~ ^[0-9]+$ ]] && kill -0 "$spid" 2>/dev/null; then
        mv "$stash" "$lock" 2>/dev/null || rm -rf "$stash"
        err "Another claude-profile operation is in progress"
        exit 1
      fi
      rm -rf "$stash"
    fi
    # loop and retry mkdir
  done

  err "Another claude-profile operation is in progress"
  exit 1
}

# ─── Interrupted-operation marker ────────────────────────────
# Bracket the destructive phase of use/new/restore/deactivate. The marker
# records the operation, its PHASE, and the source/target profiles so a crash
# is recovered by sweeping the half-moved live state back to the RIGHT profile:
#   phase=saving   — crashed during the outgoing --move; live holds a partial
#                    copy of SOURCE, so recovery sweeps it back to source.
#   phase=loading  — crashed during the incoming load; live holds a partial
#                    copy of TARGET, so recovery sweeps it back to target.
#   phase=restore  — deactivate crashed mid-restore; live holds a partial copy
#                    of the backup (handled by deactivate itself).
# Written as key=value lines. The old single-line forms ("use X",
# "deactivate") are still parsed so a marker left by an older binary recovers
# instead of crashing.

_mark_op() {
  local op="$1" phase="$2" source="$3" target="$4"
  {
    printf 'op=%s\n' "$op"
    printf 'phase=%s\n' "$phase"
    printf 'source=%s\n' "$source"
    printf 'target=%s\n' "$target"
  } > "$OP_MARKER_FILE"
}

# Back-compat single-arg writer for loading-only callers (edit/restore reload,
# and any old call sites): "use X" → loading phase to X; "deactivate" → restore.
_set_op_marker() {
  case "$1" in
    "use "*)    _mark_op use loading "" "${1#use }" ;;
    deactivate) _mark_op deactivate restore "" "" ;;
    *)          _mark_op "$1" "" "" "" ;;
  esac
}

_clear_op_marker() { rm -f "$OP_MARKER_FILE"; }

_get_op_marker() {
  if [[ -f "$OP_MARKER_FILE" ]]; then
    cat "$OP_MARKER_FILE"
  else
    echo ""
  fi
}

# Parse the marker into globals _OP _OP_PHASE _OP_SOURCE _OP_TARGET, tolerating
# the old single-line forms. Returns 1 (all empty) when no marker exists.
_parse_op_marker() {
  _OP="" _OP_PHASE="" _OP_SOURCE="" _OP_TARGET=""
  [[ -f "$OP_MARKER_FILE" ]] || return 1
  local first line
  first="$(head -1 "$OP_MARKER_FILE" 2>/dev/null || true)"
  if [[ "$first" == op=* ]]; then
    while IFS= read -r line; do
      case "$line" in
        op=*)     _OP="${line#op=}" ;;
        phase=*)  _OP_PHASE="${line#phase=}" ;;
        source=*) _OP_SOURCE="${line#source=}" ;;
        target=*) _OP_TARGET="${line#target=}" ;;
      esac
    done < "$OP_MARKER_FILE"
  elif [[ "$first" == "use "* ]]; then
    _OP="use"; _OP_PHASE="loading"; _OP_TARGET="${first#use }"
  elif [[ "$first" == "deactivate" ]]; then
    _OP="deactivate"; _OP_PHASE="restore"
  else
    _OP="unknown"
  fi
  return 0
}

_refuse_if_op_interrupted() {
  _parse_op_marker || return 0
  case "$_OP" in
    use)
      local t
      if [[ "$_OP_PHASE" == "saving" ]]; then
        t="$_OP_SOURCE"
      else
        t="$_OP_TARGET"
      fi
      [[ -z "$t" ]] && t="${_OP_TARGET:-$_OP_SOURCE}"
      err "A previous switch (to '$t') was interrupted"
      err "Run 'claude-profile use $t' to recover first"
      ;;
    deactivate)
      err "A previous deactivate was interrupted"
      err "Run 'claude-profile deactivate' to complete it first"
      ;;
    *)
      err "An interrupted operation left a marker — inspect and remove $OP_MARKER_FILE manually"
      ;;
  esac
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
