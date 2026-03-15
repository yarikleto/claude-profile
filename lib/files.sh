# files.sh — Copy managed items between live locations and profile directories

# Copy live ~/.claude/ state into a profile directory.
# Follows symlinks at the source (user's live files are trusted) so that
# symlinked settings are captured as regular files in the profile.
_snapshot_current() {
  local dst="$1"
  for item in "${MANAGED_ITEMS[@]}"; do
    local src iname
    src="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -e "$src" ]]; then
      cp -RH "$src" "$dst/$iname"
    fi
  done
}

# Copy live state into a profile directory and commit changes.
# Follows symlinks at the source — same rationale as _snapshot_current.
_save_current_to() {
  local dst="$1"
  local msg="${2:-Auto-save}"
  mkdir -p "$dst"
  for item in "${MANAGED_ITEMS[@]}"; do
    local src iname
    src="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -e "$src" ]]; then
      rm -rf "$dst/$iname"
      cp -RH "$src" "$dst/$iname"
    fi
  done
  _git_commit "$dst" "$msg"
}

# Copy profile directory contents into live locations.
_load_profile_to_live() {
  local profile_dir="$1"
  for item in "${MANAGED_ITEMS[@]}"; do
    local target iname
    target="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -L "$target" || -e "$target" ]]; then
      rm -rf "$target"
    fi
    if [[ -e "$profile_dir/$iname" && ! -L "$profile_dir/$iname" ]]; then
      cp -RP "$profile_dir/$iname" "$target"
    fi
  done
}

# Restore from the original backup into live locations.
_restore_from_backup() {
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  for item in "${MANAGED_ITEMS[@]}"; do
    local target iname
    target="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -L "$target" || -e "$target" ]]; then
      rm -rf "$target"
    fi
    if [[ -e "$backup_dir/$iname" && ! -L "$backup_dir/$iname" ]]; then
      cp -RP "$backup_dir/$iname" "$target"
    fi
  done
}

# Print a summary of what a profile directory contains.
_show_summary() {
  local dir="$1"
  for item in "${MANAGED_ITEMS[@]}"; do
    local iname
    iname="$(_item_name "$item")"
    if [[ -d "$dir/$iname" ]]; then
      local count
      count="$(find "$dir/$iname" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
      echo -e "  ${GREEN}✓${NC} ${BOLD}$iname${NC} ${DIM}($count items)${NC}"
    elif [[ -f "$dir/$iname" ]]; then
      echo -e "  ${GREEN}✓${NC} ${BOLD}$iname${NC}"
    else
      echo -e "  ${DIM}· $iname${NC}"
    fi
  done
}
