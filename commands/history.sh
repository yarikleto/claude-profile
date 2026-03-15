# history.sh — Git-based change tracking: history, diff, restore

cmd_history() {
  local name="${1:-$(get_current)}"
  _require_profile_name "$name" "claude-profile history [name]"

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir/.git" ]]; then
    warn "No history for profile $(_pname "$name")"; return
  fi

  echo -e "${CYAN}${BOLD}History: $name${NC}"
  echo ""
  git -C "$profile_dir" log --format="  %C(yellow)%h%C(reset) %C(dim)%ci%C(reset)  %s" --date=short
}

cmd_diff() {
  local name="" ref=""
  for arg in "$@"; do
    if [[ -d "$PROFILES_DIR/$arg" ]]; then
      name="$arg"
    else
      ref="$arg"
    fi
  done

  name="${name:-$(get_current)}"
  _require_profile_name "$name" "claude-profile diff [name] [commit|date]"

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir/.git" ]]; then
    warn "No history for profile $(_pname "$name")"; return
  fi

  if [[ -z "$ref" ]]; then
    _diff_unsaved "$name" "$profile_dir"
  else
    _diff_since_ref "$name" "$profile_dir" "$ref"
  fi
}

_snapshot_live_for_diff() {
  local dst="$1"
  for item in "${MANAGED_ITEMS[@]}"; do
    local src iname
    src="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -e "$src" ]]; then
      cp -RH "$src" "$dst/$iname" || return 1
    fi
  done
}

_diff_unsaved() {
  local name="$1" profile_dir="$2"
  echo -e "${CYAN}${BOLD}Unsaved changes: $name${NC}"
  echo ""

  local tmp
  tmp="$(mktemp -d)" || return 1
  if ! _snapshot_live_for_diff "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi

  local diff_args
  diff_args=(-rq "$profile_dir" "$tmp" --exclude=.git --exclude=.gitignore)
  for item in "${BULK_ITEMS[@]}"; do
    diff_args+=("--exclude=$(_item_name "$item")")
  done

  local changes diff_status=0
  if ! changes="$(diff "${diff_args[@]}" 2>/dev/null \
    | sed "s|$profile_dir|profile|g; s|$tmp|current|g")"; then
    diff_status=$?
    if [[ $diff_status -gt 1 ]]; then
      rm -rf "$tmp"
      return "$diff_status"
    fi
  fi
  rm -rf "$tmp"

  if [[ -n "$changes" ]]; then
    echo "$changes"
  else
    echo -e "  ${DIM}(no changes)${NC}"
  fi
}

_diff_since_ref() {
  local name="$1" profile_dir="$2" ref="$3"
  local resolved
  resolved="$(_git_resolve_ref "$profile_dir" "$ref")"

  echo -e "${CYAN}${BOLD}Changes since $ref: $name${NC}"
  echo ""
  git -C "$profile_dir" diff "$resolved"..HEAD --stat --
  echo ""
  git -C "$profile_dir" diff "$resolved"..HEAD --
}

cmd_restore() {
  local name="" ref=""
  for arg in "$@"; do
    if [[ -d "$PROFILES_DIR/$arg" ]]; then
      name="$arg"
    else
      ref="$arg"
    fi
  done

  name="${name:-$(get_current)}"
  if [[ -z "$name" || -z "$ref" ]]; then
    err "Usage: claude-profile restore [name] <commit|date>"; exit 1
  fi

  local profile_dir="$PROFILES_DIR/$name"
  if [[ ! -d "$profile_dir/.git" ]]; then
    err "No history for profile $(_pname "$name")"; exit 1
  fi

  local resolved
  resolved="$(_git_resolve_ref "$profile_dir" "$ref")"

  local short
  short="$(git -C "$profile_dir" log --format='%h %s' -1 "$resolved" --)"
  info "Restoring $(_pname "$name") to: ${YELLOW}$short${NC}"

  # Auto-save unsaved live changes if this is the active profile
  if [[ "$(get_current)" == "$name" ]]; then
    _save_current_to "$profile_dir" "Auto-save before restore to $ref"
  fi

  # Restore files from git — checkout overwrites in-place (no pre-delete needed)
  if ! git -C "$profile_dir" checkout "$resolved" -- . 2>/dev/null; then
    err "Failed to checkout $ref — profile unchanged"
    exit 1
  fi
  _git_commit "$profile_dir" "Restored to $ref"

  # If active, reload into live locations
  if [[ "$(get_current)" == "$name" ]]; then
    info "Reloading active profile..."
    _load_profile_to_live "$profile_dir"
  fi

  ok "Restored $(_pname "$name") to ${YELLOW}$ref${NC}"
  info "Note: bulk items (projects/, todos/, etc.) are not affected by restore"
}
