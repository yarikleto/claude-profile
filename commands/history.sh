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

_diff_unsaved() {
  local name="$1" profile_dir="$2"
  echo -e "${CYAN}${BOLD}Unsaved changes: $name${NC}"
  echo ""

  local tmp
  tmp="$(mktemp -d)"
  trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"' RETURN

  for item in "${MANAGED_ITEMS[@]}"; do
    local src iname
    src="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -e "$src" ]]; then
      cp -RH "$src" "$tmp/$iname"
    fi
  done

  local excludes="--exclude=.git --exclude=.gitignore"
  for item in "${BULK_ITEMS[@]}"; do
    local iname
    iname="$(_item_name "$item")"
    excludes+=" --exclude=$iname"
  done

  local changes
  changes="$(eval diff -rq \"\$profile_dir\" \"\$tmp\" $excludes 2>/dev/null \
    | sed "s|$profile_dir|profile|g; s|$tmp|current|g")" || true

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

  # Restore files from git (not .git itself)
  for item in "${MANAGED_ITEMS[@]}"; do
    local iname
    iname="$(_item_name "$item")"
    rm -rf "$profile_dir/$iname"
  done
  git -C "$profile_dir" checkout "$resolved" -- . 2>/dev/null
  _git_commit "$profile_dir" "Restored to $ref"

  # If active, reload into live locations
  if [[ "$(get_current)" == "$name" ]]; then
    info "Reloading active profile..."
    _load_profile_to_live "$profile_dir"
  fi

  ok "Restored $(_pname "$name") to ${YELLOW}$ref${NC}"
}
