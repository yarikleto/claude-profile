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

  # Auto-save live state so the profile dir has the latest files
  if [[ "$(get_current)" == "$name" ]]; then
    _save_current_to "$PROFILES_DIR/$name" "Auto-save before edit"
  fi

  local profile_dir="$PROFILES_DIR/$name"
  if [[ -n "${EDITOR:-}" ]]; then
    # EDITOR may carry arguments ("code --wait") — let a shell split it
    sh -c "$EDITOR \"\$1\"" claude-profile-edit "$profile_dir"
  elif command -v code &>/dev/null; then
    code "$profile_dir"
  elif [[ "$(uname)" == "Darwin" ]]; then
    open "$profile_dir"
  else
    echo "$profile_dir"
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

  rm -rf "$PROFILES_DIR/$name"
  ok "Deleted $(_pname "$name")"
}
