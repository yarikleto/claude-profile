# files.sh — Copy managed items between live locations and profile directories

# Seed a new (empty) profile with template files.
# Uses __profiles__/.seed/ if it exists, otherwise falls back to built-in defaults.
_seed_profile() {
  local dst="$1"
  local seed_dir="$PROFILES_DIR/.seed"
  if [[ -d "$seed_dir" ]]; then
    # User-defined seed: copy everything from .seed/ into new profile
    local f
    for f in "$seed_dir"/* "$seed_dir"/.*; do
      local base
      base="$(basename "$f")"
      if [[ "$base" == "." || "$base" == ".." ]]; then
        continue
      fi
      if [[ -e "$f" ]]; then
        cp -RH "$f" "$dst/"
      fi
    done
  else
    # Built-in defaults
    local i
    for i in "${!SEED_NAMES[@]}"; do
      echo "${SEED_CONTENTS[$i]}" > "$dst/${SEED_NAMES[$i]}"
    done
  fi
}

_ensure_target_parent() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
}

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
  for item in "${BULK_ITEMS[@]}"; do
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
# With --move-bulk, bulk items are moved instead of copied (used during switch).
_save_current_to() {
  local dst="$1"
  local msg="${2:-Auto-save}"
  local move_bulk="${3:-}"
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
  for item in "${BULK_ITEMS[@]}"; do
    local src iname
    src="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -e "$src" ]]; then
      rm -rf "$dst/$iname"
      if [[ "$move_bulk" == "--move-bulk" ]]; then
        mv "$src" "$dst/$iname"
      else
        cp -RH "$src" "$dst/$iname"
      fi
    fi
  done
  _git_commit "$dst" "$msg"
}

# Copy profile directory contents into live locations.
# With --move-bulk, bulk items are moved instead of copied (used during switch).
_load_profile_to_live() {
  local profile_dir="$1"
  local move_bulk="${2:-}"
  # Pre-validate: ensure all source items are readable before destructive ops
  for item in "${MANAGED_ITEMS[@]}" "${BULK_ITEMS[@]}"; do
    local iname
    iname="$(_item_name "$item")"
    if [[ -e "$profile_dir/$iname" && ! -L "$profile_dir/$iname" ]]; then
      if [[ -d "$profile_dir/$iname" ]]; then
        local find_errors
        find_errors="$(find "$profile_dir/$iname" -type d 2>&1 >/dev/null)" || true
        if [[ -n "$find_errors" ]]; then
          err "Cannot read files in $profile_dir/$iname — aborting switch (live files untouched)"
          return 1
        fi
      fi
    fi
  done
  for item in "${MANAGED_ITEMS[@]}"; do
    local target iname
    target="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -L "$target" || -e "$target" ]]; then
      rm -rf "$target"
    fi
    if [[ -e "$profile_dir/$iname" && ! -L "$profile_dir/$iname" ]]; then
      _ensure_target_parent "$target"
      cp -RP "$profile_dir/$iname" "$target"
    fi
  done
  for item in "${BULK_ITEMS[@]}"; do
    local target iname
    target="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -L "$target" || -e "$target" ]]; then
      rm -rf "$target"
    fi
    if [[ -e "$profile_dir/$iname" && ! -L "$profile_dir/$iname" ]]; then
      if [[ "$move_bulk" == "--move-bulk" ]]; then
        mv "$profile_dir/$iname" "$target"
      else
        cp -RP "$profile_dir/$iname" "$target"
      fi
    fi
  done
}

# Move bulk items from a profile dir back to live (used by deactivate --keep).
_load_bulk_from_profile() {
  local profile_dir="$1"
  for item in "${BULK_ITEMS[@]}"; do
    local target iname
    target="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -L "$target" || -e "$target" ]]; then
      rm -rf "$target"
    fi
    if [[ -e "$profile_dir/$iname" && ! -L "$profile_dir/$iname" ]]; then
      mv "$profile_dir/$iname" "$target"
    fi
  done
}

# Restore from the original backup into live locations.
_restore_from_backup() {
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  if [[ ! -d "$backup_dir" ]]; then
    err "Original backup not found — refusing to restore (would destroy live files)"
    return 1
  fi
  for item in "${MANAGED_ITEMS[@]}"; do
    local target iname
    target="$(_item_source "$item")"
    iname="$(_item_name "$item")"
    if [[ -L "$target" || -e "$target" ]]; then
      rm -rf "$target"
    fi
    if [[ -e "$backup_dir/$iname" && ! -L "$backup_dir/$iname" ]]; then
      _ensure_target_parent "$target"
      cp -RP "$backup_dir/$iname" "$target"
    fi
  done
  for item in "${BULK_ITEMS[@]}"; do
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
  for item in "${MANAGED_ITEMS[@]}" "${BULK_ITEMS[@]}"; do
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
