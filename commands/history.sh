# history.sh — Git-based change tracking: history, diff, restore

cmd_history() {
  local name="${1:-$(get_current)}"
  _require_profile_name "$name" "claude-profile history [name]"
  _require_profile_exists "$name"

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
  if [[ $# -gt 2 ]]; then
    err "Usage: claude-profile diff [name] [commit|date]"
    exit 1
  fi
  if [[ $# -eq 2 ]]; then
    # Two args are positional: <name> <ref> — never silently demote a
    # misspelled profile name to a ref
    name="$1" ref="$2"
    _validate_profile_name "$name"
    _require_profile_exists "$name"
  elif [[ $# -eq 1 ]]; then
    if [[ -d "$PROFILES_DIR/$1" ]]; then
      name="$1"
    else
      ref="$1"
    fi
  fi

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
  local f
  for f in "$CLAUDE_DIR"/* "$CLAUDE_DIR"/.*; do
    local base
    base="$(basename "$f")"
    # The user's live .git/.gitignore must not be ingested — a live
    # .gitignore's rules would hide untracked changes from the diff
    if _skip_entry "$base"; then
      continue
    fi
    if [[ -e "$f" ]]; then
      cp -RL "$f" "$dst/$base" || return 1
    fi
  done
  if [[ -e "$HOME/.claude.json" ]]; then
    cp -L "$HOME/.claude.json" "$(_profile_home_json "$dst")" || return 1
  fi
}

_clear_diff_worktree() {
  local repo="$1"
  local f
  for f in "$repo"/* "$repo"/.*; do
    local base
    base="$(basename "$f")"
    if [[ "$base" == "." || "$base" == ".." || "$base" == ".git" ]]; then
      continue
    fi
    rm -rf "$f"
  done
}

_prepare_diff_baseline_repo() {
  local profile_dir="$1" repo="$2"
  local ignore_content=""

  if [[ -f "$profile_dir/.gitignore" ]]; then
    ignore_content="$(cat "$profile_dir/.gitignore")"
  fi

  if git -C "$profile_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$profile_dir" archive HEAD | tar -x -f - -C "$repo" || return 1
    if [[ -z "$ignore_content" && -f "$repo/.gitignore" ]]; then
      ignore_content="$(cat "$repo/.gitignore")"
    fi
  fi

  git -C "$repo" init -q || return 1
  if [[ -n "$ignore_content" ]]; then
    printf '%s\n' "$ignore_content" >> "$repo/.git/info/exclude"
  fi
  rm -f "$repo/.gitignore"
  git -C "$repo" add -A -- . || return 1
  git -C "$repo" commit -q -m "Diff baseline" --allow-empty || return 1
}

_diff_git_status() {
  local repo="$1"
  git -C "$repo" status --porcelain --untracked-files=all -- . ':!.gitignore' \
    | sed 's/^/  /'
}

_print_diff_changes() {
  local changes="$1"
  if [[ -n "$changes" ]]; then
    echo "$changes"
  else
    echo -e "  ${DIM}(no changes)${NC}"
  fi
}

# Status of live files against the active profile's committed baseline.
# Rebuilds the baseline in $repo, overlays the live snapshot, then diffs —
# this catches deletions that comparing against the thin profile dir misses.
_active_diff_status() {
  local profile_dir="$1" repo="$2"
  mkdir -p "$repo" || return 1
  _prepare_diff_baseline_repo "$profile_dir" "$repo" || return 1
  _clear_diff_worktree "$repo" || return 1
  _snapshot_live_for_diff "$repo" || return 1
  _diff_git_status "$repo"
}

_diff_active_unsaved() {
  local profile_dir="$1"
  local tmp changes rc=0
  tmp="$(mktemp -d)" || return 1

  changes="$(_active_diff_status "$profile_dir" "$tmp/repo")" || rc=$?
  rm -rf "$tmp"
  [[ "$rc" -eq 0 ]] || return "$rc"

  _print_diff_changes "$changes"
}

_diff_profile_unsaved() {
  local profile_dir="$1"
  _print_diff_changes "$(_diff_git_status "$profile_dir")"
}

_diff_unsaved() {
  local name="$1" profile_dir="$2"
  echo -e "${CYAN}${BOLD}Unsaved changes: $name${NC}"
  echo ""

  if [[ "$(get_current)" == "$name" ]]; then
    _diff_active_unsaved "$profile_dir"
  else
    _diff_profile_unsaved "$profile_dir"
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
  local name="" ref="" arg
  for arg in "$@"; do
    if [[ "$arg" =~ [/[:cntrl:]] || "$arg" == .* || "$arg" == -* ]]; then
      err "Invalid profile name '$arg' (must start with alphanumeric, no slashes or dots)"
      exit 1
    fi
  done
  if [[ $# -eq 1 ]]; then
    ref="$1"
  elif [[ $# -eq 2 ]]; then
    # Two args are positional: <name> <ref> — never silently demote a
    # misspelled profile name to a ref and roll back the active profile
    name="$1" ref="$2"
    _validate_profile_name "$name"
    _require_profile_exists "$name"
  elif [[ $# -gt 2 ]]; then
    err "Usage: claude-profile restore [name] <commit|date>"; exit 1
  fi

  _refuse_if_op_interrupted

  name="${name:-$(get_current_validated)}"
  if [[ -n "$name" ]]; then
    _validate_profile_name "$name"
  fi
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

  # Auto-save unsaved live changes if this is the active profile; for a
  # non-active profile, commit any stray working-tree edits the same way
  if [[ "$(get_current)" == "$name" ]]; then
    _save_current_to "$profile_dir" "Auto-save before restore to $ref"
  else
    _git_commit "$profile_dir" "Auto-save before restore to $ref"
  fi
  # The rollback deletes the working tree first — proceed only if that
  # safety-net commit actually landed
  if [[ -n "$(git -C "$profile_dir" status --porcelain 2>/dev/null)" ]]; then
    err "Unsaved changes could not be committed — aborting restore (profile and live files untouched)"
    err "Fix git in $profile_dir (e.g. configure user.name/user.email), then retry"
    exit 1
  fi

  # Full rollback: remove tracked files that don't exist in the target commit,
  # then restore the target's files. Plain `git checkout <ref> -- .` only
  # updates paths present in the target — it won't delete files added later.
  if ! git -C "$profile_dir" rm -rf --quiet . 2>/dev/null; then
    err "Failed to clean working tree for $ref — profile unchanged"
    exit 1
  fi
  if ! git -C "$profile_dir" checkout "$resolved" -- . 2>/dev/null; then
    git -C "$profile_dir" checkout HEAD -- . 2>/dev/null || true
    err "Failed to check out $ref — the profile was restored to its last saved state instead"
    exit 1
  fi
  _git_commit "$profile_dir" "Restored to $ref"

  # If active, reload into live locations
  if [[ "$(get_current)" == "$name" ]]; then
    info "Reloading active profile..."
    _set_op_marker "use $name"
    _load_profile_to_live "$profile_dir"
    _clear_op_marker
  fi

  ok "Restored $(_pname "$name") to ${YELLOW}$ref${NC}"
}
