# restore.sh — Transactional restore primitives

_restore_path_is_memory() {
  local path="$1"
  if [[ "$path" == "agent-memory" || "$path" == agent-memory/* ]]; then
    return 0
  fi
  [[ "$path" =~ ^projects/[^/]+/memory(/|$) ]]
}

_restore_path_is_disposable() {
  local path="$1"
  case "$path" in
    projects|projects/*)
      if _restore_path_is_memory "$path"; then
        return 1
      fi
      return 0
      ;;
    todos|todos/*|plans|plans/*|tasks|tasks/*|plugins|plugins/*|history.jsonl|history.jsonl/*)
      return 0
      ;;
  esac
  return 1
}

# Build a tree containing only the target state a restore is allowed to touch:
# ordinary configuration plus durable memory. Disposable roots are omitted even
# if an old/manual commit accidentally tracked them, so applying this tree leaves
# their current untracked worktree copies alone. The current tool-owned policy is
# staged from the worktree rather than taken from the target revision.
_restore_build_target_tree() (
  local profile_dir="$1" ref="$2" preserve_memory="$3"
  local scratch index entries filtered current_entries record path tree

  if ! scratch="$(mktemp -d "$PROFILES_DIR/.restore-tree.XXXXXX")"; then
    return 1
  fi
  trap 'rm -rf -- "$scratch"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  scratch="$(_canonical_path "$scratch")"
  index="$scratch/index"
  entries="$scratch/target-entries"
  filtered="$scratch/filtered-entries"
  current_entries="$scratch/current-entries"

  if ! git -C "$profile_dir" ls-tree -rz --full-tree "$ref" > "$entries" 2>/dev/null ||
     ! GIT_INDEX_FILE="$index" git -C "$profile_dir" read-tree --empty 2>/dev/null; then
    return 1
  fi
  : > "$filtered" || return 1
  while IFS= read -r -d '' record; do
    path="${record#*$'\t'}"
    if [[ "$path" == ".gitignore" || "$path" == .gitignore/* ]]; then
      continue
    fi
    if _restore_path_is_disposable "$path"; then
      continue
    fi
    if [[ "$preserve_memory" == true ]] && _restore_path_is_memory "$path"; then
      continue
    fi
    printf '%s\0' "$record" >> "$filtered" || return 1
  done < "$entries"

  if [[ "$preserve_memory" == true ]]; then
    if ! git -C "$profile_dir" ls-tree -rz --full-tree HEAD > "$current_entries" 2>/dev/null; then
      return 1
    fi
    while IFS= read -r -d '' record; do
      path="${record#*$'\t'}"
      if _restore_path_is_memory "$path"; then
        printf '%s\0' "$record" >> "$filtered" || return 1
      fi
    done < "$current_entries"
  fi

  if ! GIT_INDEX_FILE="$index" git -C "$profile_dir" update-index \
      -z --index-info < "$filtered" 2>/dev/null; then
    return 1
  fi
  if [[ -e "$profile_dir/.gitignore" || -L "$profile_dir/.gitignore" ]]; then
    if ! GIT_INDEX_FILE="$index" git -C "$profile_dir" add -f -A -- \
        .gitignore 2>/dev/null; then
      return 1
    fi
  fi
  if ! tree="$(GIT_INDEX_FILE="$index" git -C "$profile_dir" write-tree 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "$tree"
)

_restore_write_allowed_paths() {
  local profile_dir="$1" tree="$2" output="$3"
  local all_paths="${output}.all" path
  : > "$output" || return 1
  if ! git -C "$profile_dir" ls-tree -rz --name-only "$tree" > "$all_paths" 2>/dev/null; then
    rm -f "$all_paths"
    return 1
  fi
  while IFS= read -r -d '' path; do
    if [[ "$path" == ".gitignore" || "$path" == .gitignore/* ]] ||
       _restore_path_is_disposable "$path"; then
      continue
    fi
    printf '%s\0' "$path" >> "$output" || {
      rm -f "$all_paths"
      return 1
    }
  done < "$all_paths"
  rm -f "$all_paths"
}

# Run path commands in bounded batches so profiles with large memory trees do
# not exceed ARG_MAX. Every dynamic name uses literal pathspec magic, including
# names containing newlines, brackets, wildcards, or a leading colon/dash.
_restore_run_path_batches() {
  local profile_dir="$1" action="$2" paths_file="$3"
  local path pathspec path_bytes batch_bytes=0
  local -a paths=()
  while IFS= read -r -d '' path; do
    pathspec=":(top,literal)$path"
    path_bytes=$((${#pathspec} + 1))
    if [[ "${#paths[@]}" -gt 0 &&
          ( "${#paths[@]}" -ge "$GIT_PATH_BATCH_MAX" ||
            $((batch_bytes + path_bytes)) -gt "$GIT_PATH_BATCH_MAX_BYTES" ) ]]; then
      _restore_run_path_batch "$profile_dir" "$action" "${paths[@]}" || return 1
      paths=()
      batch_bytes=0
    fi
    paths+=("$pathspec")
    batch_bytes=$((batch_bytes + path_bytes))
  done < "$paths_file"
  if [[ "${#paths[@]}" -gt 0 ]]; then
    _restore_run_path_batch "$profile_dir" "$action" "${paths[@]}" || return 1
  fi
}

_restore_run_path_batch() {
  local profile_dir="$1" action="$2"
  shift 2
  case "$action" in
    remove)
      git -C "$profile_dir" rm -f --quiet --ignore-unmatch -- "$@"
      ;;
    clean)
      # These are exact, filtered target paths created by a failed checkout.
      # Include ignored entries so a target path that matches a custom rule
      # cannot survive rollback invisibly.
      git -C "$profile_dir" clean -f -d -x --quiet -- "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

# A filesystem leaf is protected only when the current allowed history tracks
# that exact leaf. Calling ls-files for a directory path is insufficient: Git
# also reports success when only descendants match, which can hide ignored
# files that a target file would otherwise replace.
_restore_worktree_leaf_is_protected() {
  local profile_dir="$1" path="$2"
  if [[ "$path" == ".gitignore" || "$path" == .gitignore/* ]] ||
     _restore_path_is_disposable "$path"; then
    return 1
  fi
  git -C "$profile_dir" ls-files --error-unmatch -- \
    ":(top,literal)$path" >/dev/null 2>&1
}

# Apply only tracked configuration and durable-memory paths. Removing the
# current tracked paths explicitly, then updating the index without `-u`, keeps
# ignored/untracked session roots out of Git's destructive unpack_trees path.
_restore_apply_target_tree() (
  local profile_dir="$1" rollback_tree="$2" target_tree="$3"
  local scratch current_paths target_paths path existing_paths existing rel probe
  local gitlink_entries record metadata mode tree
  if ! scratch="$(mktemp -d "$PROFILES_DIR/.restore-apply.XXXXXX")"; then
    return 2
  fi
  trap 'rm -rf -- "$scratch"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  scratch="$(_canonical_path "$scratch")"
  current_paths="$scratch/current-paths"
  target_paths="$scratch/target-paths"
  existing_paths="$scratch/existing-paths"
  gitlink_entries="$scratch/gitlink-entries"

  _restore_write_allowed_paths "$profile_dir" "$rollback_tree" "$current_paths" || return 2
  _restore_write_allowed_paths "$profile_dir" "$target_tree" "$target_paths" || return 2
  # An outer Git tree stores an embedded repository only as a gitlink commit
  # ID; none of that repository's tracked or untracked worktree content is in
  # the safety commit. `git rm` recursively removes the directory, so refuse
  # any allowed current/target gitlink before touching the worktree. Gitlinks
  # under disposable roots are excluded from restore and remain untouched.
  for tree in "$rollback_tree" "$target_tree"; do
    if ! git -C "$profile_dir" ls-tree -rz --full-tree "$tree" \
        > "$gitlink_entries" 2>/dev/null; then
      echo "could not inspect embedded Git repositories before restore" >&2
      return 2
    fi
    while IFS= read -r -d '' record; do
      metadata="${record%%$'\t'*}"
      mode="${metadata%% *}"
      path="${record#*$'\t'}"
      if [[ "$mode" != 160000 || "$path" == ".gitignore" ||
            "$path" == .gitignore/* ]] || _restore_path_is_disposable "$path"; then
        continue
      fi
      echo "embedded Git repository cannot be restored safely: $path" >&2
      return 2
    done < "$gitlink_entries"
  done
  # A target path can collide with a current file deliberately excluded by a
  # custom ignore rule. It can also replace a directory that contains ignored
  # content, or sit below an untracked file/symlink ancestor. The safety commit
  # cannot protect any of those leaves, so inspect the actual worktree shape
  # before the destructive phase. Directories containing only allowed tracked
  # leaves remain safe for ordinary directory/file history transitions.
  while IFS= read -r -d '' path; do
    if [[ -L "$profile_dir/$path" ||
          ( -e "$profile_dir/$path" && ! -d "$profile_dir/$path" ) ]]; then
      if _restore_worktree_leaf_is_protected "$profile_dir" "$path"; then
        continue
      fi
      echo "untracked path would be overwritten: $path" >&2
      return 2
    fi
    if [[ -d "$profile_dir/$path" ]]; then
      if ! find "$profile_dir/$path" ! -type d -print0 \
          > "$existing_paths" 2>/dev/null; then
        echo "could not inspect existing path before restore: $path" >&2
        return 2
      fi
      while IFS= read -r -d '' existing; do
        rel="${existing#"$profile_dir"/}"
        if ! _restore_worktree_leaf_is_protected "$profile_dir" "$rel"; then
          echo "untracked path would be overwritten: $rel" >&2
          return 2
        fi
      done < "$existing_paths"
      continue
    fi

    probe="$path"
    while [[ "$probe" == */* ]]; do
      probe="${probe%/*}"
      if [[ -L "$profile_dir/$probe" ||
            ( -e "$profile_dir/$probe" && ! -d "$profile_dir/$probe" ) ]]; then
        if ! _restore_worktree_leaf_is_protected "$profile_dir" "$probe"; then
          echo "untracked path would be overwritten: $probe" >&2
          return 2
        fi
        break
      fi
    done
  done < "$target_paths"
  _restore_run_path_batches "$profile_dir" remove "$current_paths" || return 1
  git -C "$profile_dir" read-tree "$target_tree" || return 1
  git -C "$profile_dir" checkout-index -a -f || return 1
)

_restore_profile_after_failure() {
  local profile_dir="$1" rollback_tree="$2" target_tree="$3"
  local rollback_commit="$4" expected_head="$5"
  local scratch target_paths rollback_error="" rollback_changes="" rollback_rc=0
  if ! scratch="$(mktemp -d "$PROFILES_DIR/.restore-rollback.XXXXXX")"; then
    err "Failed to allocate rollback workspace"
    return 1
  fi
  target_paths="$scratch/target-paths"

  if ! _restore_write_allowed_paths "$profile_dir" "$target_tree" "$target_paths"; then
    rm -rf "$scratch"
    err "Failed to inspect target paths during rollback"
    return 1
  fi
  # A final restore commit may already have advanced HEAD before its
  # verification failed. Move the ref back with compare-and-swap so rollback
  # cannot overwrite an unrelated ref update made after we observed HEAD.
  if [[ -z "$expected_head" ]] ||
     ! rollback_error="$(git -C "$profile_dir" update-ref \
        -m "claude-profile restore rollback" HEAD \
        "$rollback_commit" "$expected_head" 2>&1)"; then
    rm -rf "$scratch"
    if [[ -n "$rollback_error" ]]; then
      err "Failed to restore the last saved history: $rollback_error"
    else
      err "Failed to identify the history ref to roll back"
    fi
    return 1
  fi
  # Reset the index first. Target-only files left by a partial checkout are now
  # untracked; clean only the filtered target path list, then materialize HEAD.
  if ! rollback_error="$(git -C "$profile_dir" read-tree "$rollback_tree" 2>&1)" ||
     ! _restore_run_path_batches "$profile_dir" clean "$target_paths" \
        >>"$scratch/rollback-output" 2>&1 ||
     ! git -C "$profile_dir" checkout-index -a -f \
        >>"$scratch/rollback-output" 2>&1; then
    if [[ -z "$rollback_error" && -f "$scratch/rollback-output" ]]; then
      rollback_error="$(cat "$scratch/rollback-output")"
    fi
    rm -rf "$scratch"
    if [[ -n "$rollback_error" ]]; then
      err "Failed to restore the last saved state: $rollback_error"
    else
      err "Failed to restore the last saved state"
    fi
    return 1
  fi
  rm -rf "$scratch"

  if ! git -C "$profile_dir" diff --cached --quiet "$rollback_tree" -- 2>/dev/null ||
     ! git -C "$profile_dir" diff --quiet 2>/dev/null; then
    err "Failed to verify the restored index and working tree"
    return 1
  fi
  rollback_changes="$(_diff_git_status "$profile_dir")" || rollback_rc=$?
  if [[ "$rollback_rc" -ne 0 || -n "$rollback_changes" ]]; then
    err "Failed to verify the restored history policy"
    return 1
  fi
  return 0
}
