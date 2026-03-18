# files.sh — Full-directory operations between live ~/.claude/ and profile directories

# Seed a new (empty) profile with template files.
# Uses $PROFILES_DIR/.seed/ if it exists, otherwise falls back to built-in defaults.
_seed_profile() {
  local dst="$1"
  local seed_dir="$PROFILES_DIR/.seed"
  if [[ -d "$seed_dir" ]]; then
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

# Copy live ~/.claude/ state into a profile directory (no git commit).
# Follows symlinks at the source (user's live files are trusted) so that
# symlinked settings are captured as regular files in the profile.
_snapshot_current() {
  local dst="$1"
  # Copy everything from CLAUDE_DIR
  local f
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." ]]; then
      continue
    fi
    if [[ -e "$f" ]]; then
      cp -RH "$f" "$dst/$base"
    fi
  done
  # Special: always copy ~/.claude.json
  if [[ -e "$HOME/.claude.json" ]]; then
    cp -RH "$HOME/.claude.json" "$dst/.claude.json"
  fi
}

# Copy live state into a profile directory and commit changes.
# With --move, items are moved instead of copied (used during switch).
_save_current_to() {
  local dst="$1"
  local msg="${2:-Auto-save}"
  local move="${3:-}"
  mkdir -p "$dst"
  local f
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." ]]; then
      continue
    fi
    if [[ -e "$f" ]]; then
      rm -rf "$dst/$base"
      if [[ "$move" == "--move" ]]; then
        mv "$f" "$dst/$base"
      else
        cp -RH "$f" "$dst/$base"
      fi
    fi
  done
  # Special: always copy ~/.claude.json (even with --move, since it lives outside CLAUDE_DIR)
  if [[ -e "$HOME/.claude.json" ]]; then
    rm -rf "$dst/.claude.json"
    cp -RH "$HOME/.claude.json" "$dst/.claude.json"
  fi
  _git_commit "$dst" "$msg"
}

# Pre-validate a profile directory is safe to load (no symlinks, all readable).
# Call this BEFORE any destructive operations (like --move save).
_validate_profile_for_load() {
  local profile_dir="$1"
  local f
  for f in "$profile_dir"/* "$profile_dir"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." || "$base" == ".git" || "$base" == ".gitignore" ]]; then
      continue
    fi
    if [[ -L "$f" ]]; then
      err "Symlink '$base' found in profile — aborting switch (live files untouched)"
      return 1
    fi
    if [[ -e "$f" ]]; then
      if [[ -d "$f" ]]; then
        local find_errors
        find_errors="$(find "$f" -type d 2>&1 >/dev/null)" || true
        if [[ -n "$find_errors" ]]; then
          err "Cannot read files in $f — aborting switch (live files untouched)"
          return 1
        fi
        # Reject nested symlinks inside directories (could escape sandbox)
        local nested_symlink
        nested_symlink="$(find "$f" -type l 2>/dev/null | head -1)" || true
        if [[ -n "$nested_symlink" ]]; then
          err "Symlink found in $f — aborting switch (live files untouched)"
          return 1
        fi
      elif [[ -f "$f" && ! -r "$f" ]]; then
        err "Unreadable file '$base' in profile — aborting switch (live files untouched)"
        return 1
      fi
    fi
  done
}

# Copy profile directory contents into live locations.
# With --move, items are moved instead of copied (used during switch).
_load_profile_to_live() {
  local profile_dir="$1"
  local move="${2:-}"

  # Pre-validate
  _validate_profile_for_load "$profile_dir" || return 1

  # Clear CLAUDE_DIR contents
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." ]]; then
      continue
    fi
    if [[ -L "$f" || -e "$f" ]]; then
      rm -rf "$f"
    fi
  done

  # Always clear ~/.claude.json before loading — if the target profile has one,
  # it will be restored below. If not, absence is the correct state.
  rm -f "$HOME/.claude.json"

  # Copy/move profile contents to live locations
  for f in "$profile_dir"/* "$profile_dir"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." || "$base" == ".git" || "$base" == ".gitignore" ]]; then
      continue
    fi
    # Handle .claude.json specially — goes to $HOME/.claude.json
    # Always copy (never move) since .claude.json lives outside CLAUDE_DIR
    if [[ "$base" == ".claude.json" ]]; then
      if [[ -e "$f" && ! -L "$f" ]]; then
        cp -RP "$f" "$HOME/.claude.json"
      fi
      continue
    fi
    if [[ -e "$f" && ! -L "$f" ]]; then
      if [[ "$move" == "--move" ]]; then
        mv "$f" "$CLAUDE_DIR/$base"
      else
        cp -RP "$f" "$CLAUDE_DIR/$base"
      fi
    fi
  done

  # Ensure CLAUDE_DIR exists after clearing
  mkdir -p "$CLAUDE_DIR"
}

# Restore from the original backup into live locations.
_restore_from_backup() {
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  if [[ ! -d "$backup_dir" ]]; then
    err "Original backup not found — refusing to restore (would destroy live files)"
    return 1
  fi
  _load_profile_to_live "$backup_dir"
}

# Print a summary of what a profile directory contains.
_show_summary() {
  local dir="$1"
  local f
  for f in "$dir"/* "$dir"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." || "$base" == ".git" || "$base" == ".gitignore" ]]; then
      continue
    fi
    if [[ -d "$f" ]]; then
      local count
      count="$(find "$f" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
      echo -e "  ${GREEN}✓${NC} ${BOLD}$base${NC} ${DIM}($count items)${NC}"
    elif [[ -f "$f" ]]; then
      echo -e "  ${GREEN}✓${NC} ${BOLD}$base${NC}"
    fi
  done
}
