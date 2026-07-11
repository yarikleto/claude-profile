# profile.sh — Core profile operations: new, fork, use, save, deactivate

# A `use` that died mid-load leaves live ~/.claude holding a partial copy of
# the marker's target while .current still names the old profile. Any
# auto-save at that point would absorb the target's files into the wrong
# profile — so first move them back where they came from.
_recover_interrupted_switch() {
  local op target
  op="$(_get_op_marker)"
  if [[ -z "$op" ]]; then
    return 0
  fi
  if [[ "$op" != "use "* ]]; then
    _refuse_if_op_interrupted
  fi
  target="${op#use }"
  if [[ -z "$target" || "$target" =~ [^a-zA-Z0-9._-] || "$target" == .* || "$target" == -* ]]; then
    err "Interrupted-operation marker is corrupt — inspect and remove $OP_MARKER_FILE manually"
    exit 1
  fi
  warn "A previous switch to $(_pname "$target") was interrupted — recovering..."
  _sweep_live_entries_to "$PROFILES_DIR/$target"
  _clear_op_marker
}

# Guard for use/new: when the auto-save will not run — no profile is current
# (detached after deactivate), or .current names a profile dir that no longer
# exists — loading a profile would destroy live config that is not saved in
# any profile. Refuse unless --force was given, the live state is empty, the
# original backup didn't pre-exist (a backup created by this very command
# captures the live state, so first runs proceed without friction), or the
# live state is byte-identical to the original backup (e.g. right after a
# first-command `save` or an untouched deactivate).
_guard_detached_live_state() {
  local current="$1" force="$2" backup_preexisted="$3"
  # Attached counts only when the auto-save will actually run — mirror its
  # condition exactly: a dangling .current saves nothing.
  if [[ -n "$current" && -d "$PROFILES_DIR/$current" ]]; then
    return 0
  fi
  if [[ "$force" == true || "$backup_preexisted" != true ]]; then
    return 0
  fi
  if ! _live_state_nonempty; then
    return 0
  fi
  if _live_state_equals_dir "$PROFILES_DIR/.pre-profiles-backup"; then
    return 0
  fi
  if [[ -n "$current" ]]; then
    err "Active profile '$(_pname "$current")' is missing — your live config is not saved in any profile"
  else
    err "No active profile — your current live config is not saved in any profile"
  fi
  info "Run 'claude-profile fork <name>' to preserve it as a new profile,"
  info "or re-run with --force to discard it."
  exit 1
}

cmd_new() {
  local name="" force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *)
        if [[ -n "$name" ]]; then
          err "Unexpected argument: '$1'"
          err "Usage: claude-profile new <name> [--force]"
          exit 1
        fi
        name="$1"; shift ;;
    esac
  done
  _require_profile_name "$name" "claude-profile new <name> [--force]"
  _refuse_if_op_interrupted

  # Capture before _ensure_original_backup — a pre-existing backup does NOT
  # cover config created later, so it can't justify wiping the live state.
  local backup_preexisted=false
  if [[ -d "$PROFILES_DIR/.pre-profiles-backup" ]]; then
    backup_preexisted=true
  fi
  _ensure_original_backup

  local profile_dir="$PROFILES_DIR/$name"
  if [[ -d "$profile_dir" ]]; then
    err "Profile '$(_pname "$name")' already exists"; exit 1
  fi

  # Auto-save current profile before switching
  local current
  current="$(get_current_validated)"
  _guard_detached_live_state "$current" "$force" "$backup_preexisted"
  if [[ -n "$current" && -d "$PROFILES_DIR/$current" ]]; then
    info "Saving profile $(_pname "$current")..."
    _save_current_to "$PROFILES_DIR/$current" "Auto-save before new '$name'" --move
  fi

  mkdir -p "$profile_dir"

  _seed_profile "$profile_dir"

  _git_init "$profile_dir"

  _set_op_marker "use $name"
  _load_profile_to_live "$profile_dir"
  set_current "$name"
  _clear_op_marker
  ok "Created and activated $(_pname "$name") ${DIM}(clean)${NC}"
}

cmd_fork() {
  local name="${1:-}"
  if [[ $# -gt 1 ]]; then
    err "Unexpected argument: '$2'"
    err "Usage: claude-profile fork <name>"
    exit 1
  fi
  _require_profile_name "$name" "claude-profile fork <name>"
  _refuse_if_op_interrupted
  _ensure_original_backup

  local profile_dir="$PROFILES_DIR/$name"
  if [[ -d "$profile_dir" ]]; then
    err "Profile '$(_pname "$name")' already exists"; exit 1
  fi

  mkdir -p "$profile_dir"

  local current
  current="$(get_current_validated)"

  # Auto-save current profile before switching
  if [[ -n "$current" && -d "$PROFILES_DIR/$current" ]]; then
    info "Saving profile $(_pname "$current")..."
    _save_current_to "$PROFILES_DIR/$current" "Auto-save before fork '$name'"
  fi
  # Note: fork uses _snapshot_current (cp), not --move, because it
  # copies the current live state into the new profile. The live state
  # is preserved since the new profile IS the current state.

  if [[ -n "$current" ]]; then
    info "Forking from $(_pname "$current")..."
  else
    info "Forking from original state..."
  fi
  _snapshot_current "$profile_dir"
  _git_init "$profile_dir"

  set_current "$name"
  ok "Created and activated $(_pname "$name")"
  _show_profile_summary "$name"
}

cmd_use() {
  local name="" force=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *)
        if [[ -n "$name" ]]; then
          err "Unexpected argument: '$1'"
          err "Usage: claude-profile use <name> [--force]"
          exit 1
        fi
        name="$1"; shift ;;
    esac
  done
  _require_profile_name "$name" "claude-profile use <name> [--force]"

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir" ]]; then
    err "Profile '$(_pname "$name")' not found"
    cmd_list
    exit 1
  fi

  _recover_interrupted_switch

  local current
  current="$(get_current_validated)"

  if [[ "$current" == "$name" ]]; then
    if _live_state_nonempty || ! _dir_has_entries "$profile_dir"; then
      ok "$(_pname "$name") is already active"
      return
    fi
    # The live config is gone (e.g. an interrupted switch) but the profile
    # still holds it — reload instead of pretending all is well.
    warn "Live config is empty — reloading $(_pname "$name")"
    _set_op_marker "use $name"
    _load_profile_to_live "$profile_dir" --move
    _clear_op_marker
    ok "Active profile: $(_pname "$name")"
    _show_profile_summary "$name"
    return
  fi

  # Capture before _ensure_original_backup — a pre-existing backup does NOT
  # cover config created later, so it can't justify wiping the live state.
  local backup_preexisted=false
  if [[ -d "$PROFILES_DIR/.pre-profiles-backup" ]]; then
    backup_preexisted=true
  fi
  _ensure_original_backup

  _guard_detached_live_state "$current" "$force" "$backup_preexisted"

  # Pre-validate target profile before any destructive operations
  _validate_profile_for_load "$profile_dir" || exit 1

  # Auto-save current profile before switching
  if [[ -n "$current" && -d "$PROFILES_DIR/$current" ]]; then
    info "Saving $(_pname "$current")..."
    _save_current_to "$PROFILES_DIR/$current" "Auto-save before switch to '$name'" --move
  fi

  info "Switching to $(_pname "$name")..."
  _set_op_marker "use $name"
  _load_profile_to_live "$profile_dir" --move

  set_current "$name"
  _clear_op_marker
  ok "Active profile: $(_pname "$name")"
  _show_profile_summary "$name"
}

cmd_save() {
  local name="" msg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m)
        if [[ $# -lt 2 ]]; then
          err "-m requires a message"
          exit 1
        fi
        msg="$2"; shift 2 ;;
      *)
        if [[ -n "$name" ]]; then
          err "Unexpected argument: '$1'"
          err "Usage: claude-profile save [name] [-m message]"
          exit 1
        fi
        name="$1"; shift ;;
    esac
  done

  name="${name:-$(get_current_validated)}"
  _require_profile_name "$name" "claude-profile save [name] [-m message]"
  _refuse_if_op_interrupted
  _ensure_original_backup

  local profile_dir="$PROFILES_DIR/$name"
  mkdir -p "$profile_dir"
  _save_current_to "$profile_dir" "${msg:-Manual save}"
  ok "Saved $(_pname "$name")"
}

_deactivate_usage() {
  err "Usage: claude-profile deactivate [--keep]"
}

_next_detached_profile_name() {
  local base name i
  base="detached-$(date +%Y%m%d-%H%M%S)"
  name="$base"
  i=2
  while [[ -d "$PROFILES_DIR/$name" ]]; do
    name="$base-$i"
    i=$((i + 1))
  done
  echo "$name"
}

_live_state_saved_in_any_profile() {
  local dir base
  for dir in "$PROFILES_DIR"/*; do
    base="$(basename "$dir")"
    if [[ "$base" == .* || ! -d "$dir" ]]; then
      continue
    fi
    if _live_state_equals_dir "$dir"; then
      return 0
    fi
  done
  return 1
}

_any_profiles_exist() {
  local dir base
  for dir in "$PROFILES_DIR"/*; do
    base="$(basename "$dir")"
    if [[ "$base" == .* || ! -d "$dir" ]]; then
      continue
    fi
    return 0
  done
  return 1
}

cmd_deactivate() {
  local keep=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)
        keep=true
        shift
        ;;
      *)
        _deactivate_usage
        return 1
        ;;
    esac
  done

  # A deactivate that died mid-restore is completed here (skipping the
  # auto-save — live holds a partial backup copy, not user data). Any other
  # interrupted operation must be recovered by its own command first.
  local resume_restore=false op
  op="$(_get_op_marker)"
  if [[ -n "$op" ]]; then
    if [[ "$op" == "deactivate" && "$keep" != true ]]; then
      warn "A previous deactivate was interrupted — completing the restore..."
      resume_restore=true
    else
      _refuse_if_op_interrupted
    fi
  fi

  local current
  current="$(get_current_validated)"
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"

  if [[ "$keep" == true ]]; then
    if [[ -z "$current" ]]; then
      warn "No profile is active"; return
    fi
    # Keep current files in place — save a copy to profile, then detach
    info "Saving $(_pname "$current")..."
    _save_current_to "$PROFILES_DIR/$current" "Auto-save before deactivate --keep"
    clear_current
    ok "Detached from $(_pname "$current") — current config kept as-is"
    info "You can safely remove ${BOLD}$PROFILES_DIR${NC} when ready"
  else
    # Verify backup exists before doing destructive save
    if [[ ! -d "$backup_dir" ]]; then
      if [[ -n "$current" ]]; then
        err "Original backup not found — refusing to restore (would destroy live files)"
        return 1
      fi
      if _any_profiles_exist; then
        err "Original backup not found — nothing to restore"
        return 1
      fi
      warn "No profile is active"; return
    fi

    # Validate the backup BEFORE the destructive auto-save — a backup that
    # cannot be loaded must be discovered while the live files are untouched
    _validate_profile_for_load "$backup_dir" || return 1

    if [[ "$resume_restore" == true ]]; then
      : # live holds a partial restore — nothing of the user's to save
    elif [[ -n "$current" ]]; then
      info "Saving $(_pname "$current")..."
      _save_current_to "$PROFILES_DIR/$current" "Auto-save before deactivate" --move
    elif _live_state_nonempty && ! _live_state_equals_dir "$backup_dir" && ! _live_state_saved_in_any_profile; then
      local detached_name detached_dir
      detached_name="$(_next_detached_profile_name)"
      detached_dir="$PROFILES_DIR/$detached_name"
      mkdir -p "$detached_dir"
      info "Saving detached config as $(_pname "$detached_name")..."
      _snapshot_current "$detached_dir"
      _git_init "$detached_dir"
    fi

    _set_op_marker "deactivate"
    info "Restoring original state..."
    _restore_from_backup
    clear_current
    _clear_op_marker
    if [[ -n "$current" ]]; then
      ok "Deactivated $(_pname "$current"), restored original state"
    else
      ok "Restored original state"
    fi
  fi
}
