# info.sh — Read-only profile operations: list, current, show, edit, delete

cmd_list() {
  ensure_dir
  local current has_profiles=0
  current="$(get_current)"

  for dir in "$PROFILES_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    has_profiles=1
    local name
    name="$(basename "$dir")"
    if [[ "$name" == "$current" ]]; then
      echo -e "  ${GREEN}●${NC} ${CYAN}${BOLD}$name${NC} ${DIM}(active)${NC}"
    else
      echo -e "  ${DIM}○${NC} $name"
    fi
  done

  if [[ $has_profiles -eq 0 ]]; then
    echo ""
    warn "No profiles yet"
    echo -e "  ${DIM}Create one with:${NC} ${BOLD}claude-profile fork <name>${NC}"
  fi
}

cmd_current() {
  local current
  current="$(get_current_validated)"
  if [[ -n "$current" ]]; then
    echo "$current"
  else
    echo -e "${DIM}(no active profile)${NC}"
    return 1
  fi
}

cmd_show() {
  local name="${1:-$(get_current)}"
  _require_profile_name "$name" "claude-profile show <name>"
  _require_profile_exists "$name"

  echo -e "${CYAN}${BOLD}$name${NC}"
  _show_profile_summary "$name"
}

cmd_edit() {
  local name="${1:-$(get_current)}"
  _require_profile_name "$name" "claude-profile edit <name>"
  _require_profile_exists "$name"
  _refuse_if_op_interrupted

  local is_active=false
  if [[ "$(get_current)" == "$name" ]]; then
    is_active=true
    _save_current_to "$PROFILES_DIR/$name" "Auto-save before edit"
  fi

  local profile_dir="$PROFILES_DIR/$name"
  # $EDITOR runs to completion — the only case where a reload is safe. `code`
  # (no --wait) / `open` return immediately; a reload would race that editor.
  local blocking=false
  if [[ -n "${EDITOR:-}" ]]; then
    # EDITOR may carry arguments ("code --wait") — let a shell split it
    blocking=true
    sh -c "$EDITOR \"\$1\"" claude-profile-edit "$profile_dir"
  elif command -v code &>/dev/null; then
    code "$profile_dir"
  elif [[ "$(uname)" == "Darwin" ]]; then
    open "$profile_dir"
  else
    echo "$profile_dir"
  fi

  # Editing the ACTIVE profile writes into the profile dir, but live ~/.claude
  # still holds the pre-edit state — the next save/switch would overwrite the
  # edit from live. Reload the profile dir into live so the edit is the
  # authoritative state. Bracket the destructive reload with the op marker so a
  # crash mid-reload is recoverable (the profile dir keeps its copy).
  if [[ "$is_active" == true && "$blocking" == true ]]; then
    _set_op_marker "use $name"
    _load_profile_to_live "$profile_dir"
    _clear_op_marker
  fi
}

cmd_delete() {
  local name="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force) force=1; shift ;;
      *)
        if [[ -n "$name" ]]; then
          err "Unexpected argument: '$1'"
          err "Usage: claude-profile delete <name> [-f]"
          exit 1
        fi
        name="$1"; shift ;;
    esac
  done

  _require_profile_name "$name" "claude-profile delete <name> [-f]"
  _require_profile_exists "$name"
  _refuse_if_op_interrupted

  local current
  current="$(get_current)"
  if [[ "$name" == "$current" ]]; then
    err "Cannot delete the active profile. Switch first: ${BOLD}claude-profile use <other>${NC}"
    exit 1
  fi

  if [[ $force -eq 0 ]]; then
    if ! read -rp "Delete profile '$name'? [y/N] " confirm; then
      info "Cancelled"; return
    fi
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Cancelled"; return; }
  fi

  _assert_profile_path_safe "$PROFILES_DIR/$name"
  rm -rf "$PROFILES_DIR/$name"
  ok "Deleted $(_pname "$name")"
}
