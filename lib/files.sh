# files.sh — Full-directory operations between live ~/.claude/ and profile directories

# Entries never copied, moved, or deleted when syncing between live ~/.claude/
# and profile dirs. Profile dirs carry their own .git/.gitignore (written by
# _git_init); any in live ~/.claude/ are the USER's — never ingested into a
# profile, never clobbered, never deleted. To skip another entry everywhere,
# add one pattern below; every copy/move/clear/summary loop uses this predicate.
_skip_entry() {
  case "$1" in
    . | .. | .git | .gitignore | .claude-profile-home.json) return 0 ;;
    *) return 1 ;;
  esac
}

# The relocated JSON is handled separately at its reserved profile name;
# copying it as payload too would lose or duplicate it during a move switch.
_skip_live_entry() {
  _skip_entry "$1" || [[ "$CLAUDE_JSON_IN_CONFIG_DIR" == true && "$1" == ".claude.json" ]]
}

# Path at which a profile stores the home-level ~/.claude.json.
_profile_home_json() { printf '%s\n' "$1/$CLAUDE_HOME_JSON"; }

# Path to read a profile's stored home file, tolerating the legacy layout
# (root .claude.json) for a profile that predates format-2 migration. Prints a
# path that may not exist (the reserved location) when neither is present.
_profile_home_json_read() {
  local dir="$1"
  if [[ -e "$dir/$CLAUDE_HOME_JSON" ]]; then
    printf '%s\n' "$dir/$CLAUDE_HOME_JSON"
  elif [[ -e "$dir/.claude.json" && ! -d "$dir/.claude.json" ]]; then
    printf '%s\n' "$dir/.claude.json"
  else
    printf '%s\n' "$dir/$CLAUDE_HOME_JSON"
  fi
}

# Where copy-mode saves stage each entry before atomically moving it into a
# profile. It lives at the STORE root (a dotdir the store-level loops already
# skip), not inside the profile payload — so a real user file named `.saving.*`
# is captured normally instead of colliding with a staging temp.
_staging_dir() { printf '%s\n' "$PROFILES_DIR/.saving"; }

# True (0) when a profile directory holds any real entry (dotfiles included)
# beyond the skipped git metadata.
_dir_has_entries() {
  local dir="$1" f base
  if [[ -L "$dir/$CLAUDE_HOME_JSON" || -e "$dir/$CLAUDE_HOME_JSON" ]]; then
    return 0
  fi
  for f in "$dir"/* "$dir"/.*; do
    base="$(basename "$f")"
    if _skip_entry "$base"; then
      continue
    fi
    if [[ -L "$f" || -e "$f" ]]; then
      return 0
    fi
  done
  return 1
}

# Refuse to snapshot a live state containing dangling symlinks: cp -RL cannot
# copy them, and silently dropping them would make the snapshot lie.
_assert_live_has_no_broken_symlinks() {
  local f base broken
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.* "$CLAUDE_JSON_FILE"; do
    base="$(basename "$f")"
    if [[ "$f" != "$CLAUDE_JSON_FILE" ]] && _skip_live_entry "$base"; then
      continue
    fi
    if [[ ! -L "$f" && ! -e "$f" ]]; then
      continue
    fi
    broken="$(find "$f" \( -type l ! -exec test -e {} \; \) -print 2>/dev/null | head -1 || true)"
    if [[ -n "$broken" ]]; then
      err "Broken symlink in live config: $broken"
      err "Fix or remove it, then re-run"
      return 1
    fi
  done
}

# True (0) when the live state holds anything a load would destroy:
# ~/.claude.json exists, or live ~/.claude/ contains any entry (dotfiles
# included) other than the skipped git metadata.
_live_state_nonempty() {
  if [[ -L "$CLAUDE_JSON_FILE" || -e "$CLAUDE_JSON_FILE" ]]; then
    return 0
  fi
  local f
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    if [[ -L "$f" || -e "$f" ]]; then
      return 0
    fi
  done
  return 1
}

# True (0) when the live state is byte-identical to a profile-shaped directory.
# A live state that already exists elsewhere is safe to replace.
_live_state_equals_dir() {
  local dir="$1"
  local f base
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    if [[ ! -L "$f" && ! -e "$f" ]]; then
      continue
    fi
    if ! diff -rq "$f" "$dir/$base" >/dev/null 2>&1; then
      return 1
    fi
  done
  # Entries only in $dir mean the live state lost something — not identical
  for f in "$dir"/* "$dir"/.*; do
    base="$(basename "$f")"
    if _skip_entry "$base"; then
      continue
    fi
    if [[ ! -L "$f" && ! -e "$f" ]]; then
      continue
    fi
    if _skip_live_entry "$base" || [[ ! -e "$CLAUDE_DIR/$base" ]]; then
      return 1
    fi
  done
  # Compare the managed JSON separately in either live layout.
  local dir_home
  dir_home="$(_profile_home_json_read "$dir")"
  if [[ -e "$CLAUDE_JSON_FILE" || -e "$dir_home" ]]; then
    if ! diff -q "$CLAUDE_JSON_FILE" "$dir_home" >/dev/null 2>&1; then
      return 1
    fi
  fi
  return 0
}

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
      if _skip_entry "$base"; then
        continue
      fi
      if [[ -e "$f" ]]; then
        # A seed entry named .claude.json is the home-file template — store it
        # at the reserved home location, not as a live-payload entry.
        if [[ "$base" == ".claude.json" ]]; then
          cp -RL "$f" "$(_profile_home_json "$dst")"
        else
          cp -RL "$f" "$dst/$base"
        fi
      fi
    done
  else
    local i name
    for i in "${!SEED_NAMES[@]}"; do
      name="${SEED_NAMES[$i]}"
      if [[ "$name" == ".claude.json" ]]; then
        echo "${SEED_CONTENTS[$i]}" > "$(_profile_home_json "$dst")"
      else
        echo "${SEED_CONTENTS[$i]}" > "$dst/$name"
      fi
    done
  fi
}

_ensure_target_parent() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
}

# Copy live ~/.claude/ state into a profile directory (no git commit).
# Follows all symlinks (user's live files are trusted) so that
# symlinked files are captured as regular files in the profile.
_snapshot_current() {
  local dst="$1"
  _assert_profile_path_safe "$dst"
  _assert_live_has_no_broken_symlinks || return 1
  local f
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    if [[ -e "$f" ]]; then
      cp -RL "$f" "$dst/$base"
    fi
  done
  if [[ -e "$CLAUDE_JSON_FILE" ]]; then
    cp -RL "$CLAUDE_JSON_FILE" "$(_profile_home_json "$dst")"
  fi
}

# Copy live state into a profile directory and commit changes.
# With --move, items are moved instead of copied (used during switch).
# The result is an exact snapshot: entries the live state no longer has are
# removed from the destination, so deletions don't resurrect on the next load.
_save_current_to() {
  local dst="$1"
  local msg="${2:-Auto-save}"
  local move="${3:-}"
  _assert_profile_path_safe "$dst"
  mkdir -p "$dst"
  # An empty live state is never worth snapshotting — after an interrupted
  # switch, saving it would propagate deletions into a still-complete profile.
  if ! _live_state_nonempty; then
    return 0
  fi
  if [[ "$move" != "--move" ]]; then
    _assert_live_has_no_broken_symlinks || return 1
  fi
  # Clean staging left by an earlier interrupted copy. It lives at the store
  # root, not in the profile payload — see _staging_dir.
  local staging
  staging="$(_staging_dir)"
  rm -rf "$staging" 2>/dev/null || true
  local f base
  # Deletions propagate. Must run BEFORE the move loop — after a --move the live
  # dir is empty and this would wipe the entries just moved.
  for f in "$dst"/* "$dst"/.*; do
    base="$(basename "$f")"
    # The reserved home file is skipped here (handled below); a root
    # .claude.json is now a genuine live-payload entry and propagates normally.
    if _skip_entry "$base"; then
      continue
    fi
    if [[ ! -L "$f" && ! -e "$f" ]]; then
      continue
    fi
    if [[ ! -L "$CLAUDE_DIR/$base" && ! -e "$CLAUDE_DIR/$base" ]]; then
      rm -rf "$f"
    fi
  done
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    if [[ ! -L "$f" && ! -e "$f" ]]; then
      continue
    fi
    if [[ "$move" == "--move" ]]; then
      rm -rf "${dst:?}/$base"
      mv "$f" "$dst/$base"
    else
      # Copy into store-root staging first (same filesystem as the profile, so
      # the move is a rename) — the destination keeps its previous copy if the
      # copy fails partway.
      mkdir -p "$staging"
      local tmp="$staging/$base"
      rm -rf "$tmp"
      if ! cp -RL "$f" "$tmp"; then
        rm -rf "$tmp"
        err "Could not copy '$base' — profile keeps its previous copy"
        return 1
      fi
      rm -rf "${dst:?}/$base"
      mv "$tmp" "$dst/$base"
    fi
  done
  rm -rf "$staging" 2>/dev/null || true
  # Remove the live JSON after a move-mode save so recovery at the save/load
  # boundary cannot sweep the outgoing profile's JSON into the target profile.
  local dst_home
  dst_home="$(_profile_home_json "$dst")"
  if [[ -e "$CLAUDE_JSON_FILE" ]]; then
    rm -rf "$dst_home"
    cp -RL "$CLAUDE_JSON_FILE" "$dst_home"
    if [[ "$move" == "--move" ]]; then
      rm -f "$CLAUDE_JSON_FILE"
    fi
  else
    rm -rf "$dst_home"
  fi
  if [[ "$move" == "--move" ]]; then
    _git_commit "$dst" "$msg"
  else
    # Every payload entry was replaced from cp -RL output above, so no symlink
    # can remain outside the separately managed .git/.gitignore metadata.
    _git_commit "$dst" "$msg" --payload-materialized
  fi
}

# Move live entries into a profile directory WITHOUT removing anything else
# there and without touching git. Used to return a half-moved switch's files
# to the profile they came from before any auto-save can absorb them.
_sweep_live_entries_to() {
  local dst="$1" f base
  _assert_profile_path_safe "$dst"
  mkdir -p "$dst"
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    if [[ -L "$f" || -e "$f" ]]; then
      rm -rf "${dst:?}/$base"
      mv "$f" "$dst/$base"
    fi
  done
  if [[ -e "$CLAUDE_JSON_FILE" ]]; then
    local dst_home
    dst_home="$(_profile_home_json "$dst")"
    rm -rf "$dst_home"
    cp -RL "$CLAUDE_JSON_FILE" "$dst_home"
    rm -f "$CLAUDE_JSON_FILE"
  fi
}

# Materialize valid profile symlinks, then verify the profile is safe to load.
# Call this BEFORE any destructive operations (like --move save).
_validate_profile_for_load() {
  local profile_dir="$1"
  _assert_profile_path_safe "$profile_dir"

  # A default-layout payload .claude.json and the managed JSON cannot share
  # one relocated path. Refuse before saving/moving any live files.
  if [[ "$CLAUDE_JSON_IN_CONFIG_DIR" == true &&
        ( -e "$profile_dir/.claude.json" || -L "$profile_dir/.claude.json" ) ]]; then
    if [[ "$(_read_store_format)" -ge 2 ||
          "$(_profile_home_json_read "$profile_dir")" != "$profile_dir/.claude.json" ]]; then
      err "Profile payload .claude.json conflicts with the managed JSON at $CLAUDE_JSON_FILE"
      err "Use this profile with its original config layout, or rename its payload .claude.json before switching"
      return 1
    fi
  fi

  # Stored symlinks can come from an interrupted move-mode switch.
  _repair_profile_symlinks "$profile_dir" || return 1

  local f
  for f in "$profile_dir"/* "$profile_dir"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_entry "$base"; then
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
        # Defence-in-depth: reject any symlinks that survived repair
        local nested_symlink
        nested_symlink="$(find "$f" -type l 2>/dev/null | head -1)" || true
        if [[ -n "$nested_symlink" ]]; then
          err "Symlink found in $f — aborting switch (live files untouched)"
          return 1
        fi
        # Unreadable files nested in readable dirs would kill a copy-based
        # load after the live state is already cleared — reject up front
        local nested_file
        while IFS= read -r -d '' nested_file; do
          if [[ ! -r "$nested_file" ]]; then
            err "Unreadable file '$nested_file' in profile — aborting switch (live files untouched)"
            return 1
          fi
        done < <(find "$f" -type f -print0 2>/dev/null)
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
  local f

  # The source must be a real dir inside the store — never a symlink whose
  # target we would copy into the live config.
  _assert_profile_path_safe "$profile_dir"

  _validate_profile_for_load "$profile_dir" || return 1
  mkdir -p "$CLAUDE_DIR"

  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    if [[ -L "$f" || -e "$f" ]]; then
      rm -rf "$f"
    fi
  done

  # Always clear the managed JSON before loading — if the target profile has one,
  # it will be restored below. If not, absence is the correct state.
  rm -f "$CLAUDE_JSON_FILE"

  # Resolve the stored home file up front. For a legacy (pre-format-2) profile
  # this may be the root .claude.json, which must then NOT also be loaded as a
  # live payload entry.
  local home_src legacy_root_home=""
  home_src="$(_profile_home_json_read "$profile_dir")"
  if [[ "$home_src" == "$profile_dir/.claude.json" ]]; then
    legacy_root_home="yes"
  fi

  for f in "$profile_dir"/* "$profile_dir"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_entry "$base"; then
      continue
    fi
    # A legacy root .claude.json IS the home file — restored below, not here.
    if [[ -n "$legacy_root_home" && "$base" == ".claude.json" ]]; then
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

  # Keep the stored JSON even during move-mode loads, as in the default layout.
  if [[ -e "$home_src" && ! -L "$home_src" ]]; then
    cp -RP "$home_src" "$CLAUDE_JSON_FILE"
  fi
}

_restore_from_backup() {
  local backup_dir="$PROFILES_DIR/.pre-profiles-backup"
  if [[ ! -d "$backup_dir" ]]; then
    err "Original backup not found — refusing to restore (would destroy live files)"
    return 1
  fi
  _load_profile_to_live "$backup_dir"
}

_show_summary_item() {
  local path="$1" label="$2"
  if [[ -d "$path" ]]; then
    local count
    count="$(find "$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    echo -e "  ${GREEN}✓${NC} ${BOLD}$label${NC} ${DIM}($count items)${NC}"
  elif [[ -f "$path" ]]; then
    echo -e "  ${GREEN}✓${NC} ${BOLD}$label${NC}"
  fi
}

# Print a summary of what a profile directory physically contains.
_show_summary() {
  local dir="$1"
  local f
  for f in "$dir"/* "$dir"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_entry "$base"; then
      continue
    fi
    _show_summary_item "$f" "$base"
  done
  # The home file is stored under a reserved name — surface it as .claude.json.
  local home_src
  home_src="$(_profile_home_json_read "$dir")"
  if [[ -e "$home_src" ]]; then
    _show_summary_item "$home_src" ".claude.json"
  fi
}

# Print a summary of the active profile's live files. After `use --move`,
# these are the active profile contents; the profile directory is thin.
_show_live_summary() {
  local f
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    if _skip_live_entry "$base"; then
      continue
    fi
    _show_summary_item "$f" "$base"
  done

  if [[ -e "$CLAUDE_JSON_FILE" ]]; then
    _show_summary_item "$CLAUDE_JSON_FILE" ".claude.json"
  fi
}

# Print the logical contents of a profile, accounting for a moved-thin active dir.
_show_profile_summary() {
  local name="$1"
  if [[ "$(get_current)" == "$name" ]]; then
    _show_live_summary
  else
    _show_summary "$PROFILES_DIR/$name"
  fi
}
