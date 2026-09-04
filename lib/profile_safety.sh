# profile_safety.sh — Profile path confinement and stored symlink repair

# Gate every profile mutation on a path inside the store. A symlinked profile
# root, or any path that resolves outside the store, could redirect file and
# Git operations to unrelated data. Call before touching the path.
_assert_profile_path_safe() {
  local target="$1"
  if [[ -L "$target" ]]; then
    err "Refusing to operate on a symlinked profile path: $target"
    exit 1
  fi
  local canon store
  canon="$(_canonical_path "$target")"
  store="$(_canonical_path "$PROFILES_DIR")"
  if [[ "$canon" != "$store" && "$canon" != "$store"/* ]]; then
    err "Refusing to operate outside the profile store: $target"
    exit 1
  fi
}

# Stored profiles must be independent copies; move-mode switches and old save
# formats can leave trusted live symlinks in the payload. Replace each with a
# regular copy of its target before history staging or loading.
_materialize_profile_symlink() (
  local symlink="$1" slot="$2"
  local replacement="$slot/replacement"
  local original="$slot/original-link"

  # The renames below leave a quarantine window: the trap, kept in this subshell
  # so it cannot replace the CLI's lock/op traps, restores the original link if
  # its destination is absent. Status 125 means the only copy is in the repair
  # workspace and must not be cleaned up.
  _restore_quarantined_profile_link() {
    local status=$?
    trap - EXIT INT TERM
    if [[ ( -e "$original" || -L "$original" ) &&
          ! -e "$symlink" && ! -L "$symlink" ]]; then
      if ! mv "$original" "$symlink" 2>/dev/null; then
        err "Cannot restore quarantined profile link"
        err "Original link is preserved at $original"
        status=125
      fi
    fi
    exit "$status"
  }
  trap _restore_quarantined_profile_link EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  mkdir "$slot" || return 1
  cp -RL "$symlink" "$replacement" 2>/dev/null || return 1
  mv "$symlink" "$original" 2>/dev/null || return 1
  mv "$replacement" "$symlink" 2>/dev/null || return 1
  if ! rm -f "$original"; then
    warn "Independent copy installed, but quarantined link remains at $original"
  fi
)

_repair_profile_symlinks() {
  local profile_dir="$1"
  _assert_profile_path_safe "$profile_dir"
  local repaired=0
  local symlink repair_root=""
  while IFS= read -r -d '' symlink; do
    # Broken symlink: -L is true but -e is false
    if [[ ! -e "$symlink" ]]; then
      err "Broken symlink in profile: $symlink — cannot make an independent copy"
      return 1
    fi
    # Build the replacement outside the payload, then quarantine the original
    # link: the checked rename stops portable `mv` following a still-present
    # directory symlink. Rollback: _materialize_profile_symlink's trap.
    if [[ -z "$repair_root" ]]; then
      if ! repair_root="$(mktemp -d "$PROFILES_DIR/.symlink-repair.XXXXXX")"; then
        err "Cannot allocate symlink repair workspace — aborting"
        return 1
      fi
      repair_root="$(_canonical_path "$repair_root")"
    fi
    local slot="$repair_root/$repaired" repair_rc=0
    _materialize_profile_symlink "$symlink" "$slot" || repair_rc=$?
    if [[ "$repair_rc" -ne 0 ]]; then
      if [[ "$repair_rc" -ne 125 ]]; then
        rm -rf "$slot"
        rmdir "$repair_root" 2>/dev/null || true
        err "Cannot materialize profile symlink — original link restored"
      fi
      return 1
    fi
    rmdir "$slot" 2>/dev/null || true
    repaired=$((repaired + 1))
  done < <(find "$profile_dir" \
    \( -path "$profile_dir/.git" -o -path "$profile_dir/.gitignore" \) \
    -prune -o -type l -print0 2>/dev/null)

  if [[ $repaired -gt 0 ]]; then
    warn "Repaired $repaired symlink(s) in profile as independent copies"
  fi
  if [[ -n "$repair_root" ]]; then
    rmdir "$repair_root" 2>/dev/null || true
  fi
}
