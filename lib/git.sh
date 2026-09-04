# git.sh — Git history tracking for profile directories

# Expected HEAD after the most recent _git_commit transaction. It stays empty
# when history was skipped or ref publication failed.
_GIT_COMMIT_HEAD=""

_git_history_warn() {
  local dir="$1" why="$2"
  warn "Could not record history for '$(basename "$dir")' ($why) — files saved, history skipped"
}

# Profile repositories are tool-owned, ordinary non-bare repositories. Refuse
# redirects before invoking Git: a `.git` symlink/gitfile, a symlinked index,
# object/ref directory, or core.worktree redirect could otherwise make a save
# mutate another repository outside the profile store.
_git_repo_metadata_is_safe() {
  local dir="$1" git_dir="$dir/.git"
  local found_link="" actual_git="" actual_worktree=""
  local expected_git expected_worktree

  if [[ -L "$git_dir" || ! -d "$git_dir" ]]; then
    return 1
  fi
  if ! found_link="$(find "$git_dir" -type l -print -quit 2>/dev/null)"; then
    return 1
  fi
  if [[ -n "$found_link" ]]; then
    return 1
  fi
  # A commondir is a plain text redirect, not a symlink: --absolute-git-dir and
  # --show-toplevel still look local while objects/refs go to another repo.
  # Profiles are standalone, so any commondir entry is invalid.
  if [[ -e "$git_dir/commondir" || -L "$git_dir/commondir" ]]; then
    return 1
  fi

  expected_worktree="$(_canonical_path "$dir")"
  expected_git="$expected_worktree/.git"
  if ! actual_git="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" ||
     ! actual_worktree="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    return 1
  fi
  actual_git="$(_canonical_path "$actual_git")"
  actual_worktree="$(_canonical_path "$actual_worktree")"
  [[ "$actual_git" == "$expected_git" && "$actual_worktree" == "$expected_worktree" ]]
}

_git_require_safe_profile_repo() {
  local dir="$1"
  _assert_profile_path_safe "$dir"
  if ! _git_repo_metadata_is_safe "$dir"; then
    err "Profile '$(basename "$dir")' has unsafe Git metadata — refusing to follow redirects"
    return 1
  fi
}

# The profile-root .gitignore is tool-owned. Refresh it through a same-store
# temporary file so an old/corrupt symlink can never redirect a shell write to
# an external target. Regular-file replacement is an atomic rename. A symlink
# is unlinked first because portable `mv` may follow a symlink to a directory.
_git_write_ignore_policy() {
  local dir="$1"
  _assert_profile_path_safe "$dir"
  local policy="$dir/.gitignore"
  local current="" custom="" desired tmp

  if [[ ! -L "$policy" && -f "$policy" ]]; then
    if ! current="$(cat "$policy" 2>/dev/null)"; then
      return 1
    fi
    if [[ "$current" == "$LEGACY_GITIGNORE_CONTENT" ]]; then
      custom=""
    elif [[ "$current" == "$LEGACY_GITIGNORE_CONTENT"$'\n'* ]]; then
      # Older generated prefix plus user-appended rules: replace only the
      # generated part and retain the additions.
      custom="${current#"$LEGACY_GITIGNORE_CONTENT"$'\n'}"
    else
      # Remove complete managed blocks, preserving everything outside them.
      # A malformed/incomplete block is retained verbatim rather than risking
      # loss of custom lines; the authoritative new block is appended last.
      if ! custom="$(awk -v begin_prefix="$GITIGNORE_MANAGED_BEGIN_PREFIX" -v end="$GITIGNORE_MANAGED_END" '
        function flush_buffer(  i) {
          for (i = 1; i <= buffered; i++) print buffer[i]
          buffered = 0
        }
        function is_begin(line) {
          return index(line, begin_prefix) == 1
        }
        is_begin($0) && !inside {
          inside = 1
          buffer[++buffered] = $0
          next
        }
        is_begin($0) && inside {
          # A second BEGIN before END proves the earlier block was malformed.
          # Preserve that buffered text and treat this BEGIN as a new candidate.
          flush_buffer()
          buffer[++buffered] = $0
          next
        }
        inside {
          buffer[++buffered] = $0
          if ($0 == end) {
            inside = 0
            buffered = 0
          }
          next
        }
        { print }
        END {
          if (inside) flush_buffer()
        }
      ' "$policy")"; then
        return 1
      fi
    fi
  fi
  if [[ -e "$policy" && ! -f "$policy" && ! -L "$policy" ]]; then
    return 1
  fi

  if [[ -n "$custom" ]]; then
    desired="$custom

$GITIGNORE_CONTENT"
  else
    desired="$GITIGNORE_CONTENT"
  fi
  if [[ ! -L "$policy" && -f "$policy" && "$current" == "$desired" ]]; then
    return 0
  fi

  if ! tmp="$(mktemp "$PROFILES_DIR/.gitignore-policy.XXXXXX")"; then
    return 1
  fi
  if ! printf '%s\n' "$desired" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if [[ -L "$policy" ]] && ! rm -f "$policy"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv -f "$tmp" "$policy"; then
    rm -f "$tmp"
    return 1
  fi
}

# Stage exactly the paths covered by profile history. The root ignore policy is
# useful for normal Git inspection, but it cannot be the enforcement boundary:
# a lower-level .gitignore can override it in either direction. Clear both data
# roots from the index, stage ordinary config without them, then force-add only
# the durable subsets. This also removes a transcript that an older/nested rule
# accidentally allowed into history and makes the marker's exactness truthful.
#
# An optional alternate index is used by `diff` so a read-only command can apply
# this same policy without changing the profile repository's real index.
_git_stage_history_paths() (
  local dir="$1" alternate_index="${2:-}"
  if [[ -n "$alternate_index" ]]; then
    export GIT_INDEX_FILE="$alternate_index"
  fi

  if ! git -C "$dir" rm -r -f --cached --ignore-unmatch -- \
      projects agent-memory todos plans tasks plugins history.jsonl \
      >/dev/null 2>&1; then
    return 1
  fi
  # Never pass `.` here: an older policy ignoring all of projects makes Git
  # reject that pathspec before memory can be force-added. Enumerate tracked
  # plus non-ignored untracked paths, filter the disposable roots ourselves, and
  # stage literal leaves in batches; `ls-files --cached` keeps deletions exact.
  local ordinary_paths_file ordinary_path ordinary_pathspec ordinary_path_bytes
  local ordinary_batch_bytes=0
  local -a ordinary_paths=()
  if ! ordinary_paths_file="$(mktemp "$PROFILES_DIR/.git-stage-paths.XXXXXX")"; then
    return 1
  fi
  trap 'rm -f -- "$ordinary_paths_file"' EXIT
  if ! git -C "$dir" ls-files -z --cached --others --exclude-standard -- \
      > "$ordinary_paths_file" 2>/dev/null; then
    return 1
  fi
  while IFS= read -r -d '' ordinary_path; do
    case "$ordinary_path" in
      projects|projects/*|agent-memory|agent-memory/*|todos|todos/*|plans|plans/*|tasks|tasks/*|plugins|plugins/*|history.jsonl|history.jsonl/*)
        continue
        ;;
    esac
    ordinary_pathspec=":(top,literal)$ordinary_path"
    ordinary_path_bytes=$((${#ordinary_pathspec} + 1))
    if [[ "${#ordinary_paths[@]}" -gt 0 &&
          ( "${#ordinary_paths[@]}" -ge "$GIT_PATH_BATCH_MAX" ||
            $((ordinary_batch_bytes + ordinary_path_bytes)) -gt "$GIT_PATH_BATCH_MAX_BYTES" ) ]]; then
      if ! git -C "$dir" add -A -- "${ordinary_paths[@]}" 2>/dev/null; then
        return 1
      fi
      ordinary_paths=()
      ordinary_batch_bytes=0
    fi
    ordinary_paths+=("$ordinary_pathspec")
    ordinary_batch_bytes=$((ordinary_batch_bytes + ordinary_path_bytes))
  done < "$ordinary_paths_file"
  if [[ "${#ordinary_paths[@]}" -gt 0 ]] &&
     ! git -C "$dir" add -A -- "${ordinary_paths[@]}" 2>/dev/null; then
    return 1
  fi

  # The marker must always be committed even if a global ignore rule happens
  # to exclude .gitignore itself.
  if [[ -e "$dir/.gitignore" || -L "$dir/.gitignore" ]]; then
    if ! git -C "$dir" add -f -A -- .gitignore 2>/dev/null; then
      return 1
    fi
  fi

  local -a memory_paths=()
  local memory_dir
  if [[ ! -L "$dir/agent-memory" && -e "$dir/agent-memory" ]]; then
    memory_paths+=(":(top,literal)agent-memory")
  fi
  # The globs also cover dot-prefixed project keys. Literal pathspec magic keeps
  # user-controlled brackets, wildcards and colons from matching sibling paths.
  # Skip symlinked ancestors — mutating saves repair such links beforehand.
  if [[ ! -L "$dir/projects" ]]; then
    for memory_dir in \
        "$dir"/projects/*/memory \
        "$dir"/projects/.[!.]*/memory \
        "$dir"/projects/..?*/memory; do
      if [[ ! -e "$memory_dir" && ! -L "$memory_dir" ]]; then
        continue
      fi
      if [[ -L "${memory_dir%/memory}" || -L "$memory_dir" ]]; then
        continue
      fi
      memory_paths+=(":(top,literal)${memory_dir#"$dir"/}")
    done
  fi
  if [[ "${#memory_paths[@]}" -gt 0 ]]; then
    local -a memory_batch=()
    local memory_path memory_path_bytes memory_batch_bytes=0
    for memory_path in "${memory_paths[@]}"; do
      memory_path_bytes=$((${#memory_path} + 1))
      if [[ "${#memory_batch[@]}" -gt 0 &&
            ( "${#memory_batch[@]}" -ge "$GIT_PATH_BATCH_MAX" ||
              $((memory_batch_bytes + memory_path_bytes)) -gt "$GIT_PATH_BATCH_MAX_BYTES" ) ]]; then
        if ! git -C "$dir" add -f -A -- "${memory_batch[@]}" 2>/dev/null; then
          return 1
        fi
        memory_batch=()
        memory_batch_bytes=0
      fi
      memory_batch+=("$memory_path")
      memory_batch_bytes=$((memory_batch_bytes + memory_path_bytes))
    done
    if [[ "${#memory_batch[@]}" -gt 0 ]] &&
       ! git -C "$dir" add -f -A -- "${memory_batch[@]}" 2>/dev/null; then
      return 1
    fi
  fi
)

# Report versioned worktree changes without modifying the repository's real
# index or object store. Restore uses this to verify its safety snapshots; diff
# uses it to inspect inactive profiles.
_diff_git_status() (
  local repo="$1"
  local scratch index objects git_dir real_objects changes

  if ! git_dir="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null)"; then
    return 1
  fi
  real_objects="$git_dir/objects"
  if ! scratch="$(mktemp -d "$PROFILES_DIR/.diff-work.XXXXXX")"; then
    return 1
  fi
  trap 'rm -rf -- "$scratch"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  scratch="$(_canonical_path "$scratch")"
  # Keep both the alternate index and any blobs hashed by `git add` outside
  # the profile repository. The real object directory is read-only alternate
  # storage, so an inactive `diff` does not mutate an otherwise read-only repo.
  index="$scratch/index"
  objects="$scratch/objects"
  if ! mkdir -p "$objects/info"; then
    return 1
  fi
  # GIT_ALTERNATE_OBJECT_DIRECTORIES is colon-delimited; an alternates file
  # takes the absolute path directly — safe with ':' in the store path, no
  # symlink needed. Being line-delimited, only a newline needs the detour below.
  if [[ "$real_objects" == *$'\n'* ]]; then
    if ! ln -s "$real_objects" "$objects/alternate" ||
       ! printf 'alternate\n' > "$objects/info/alternates"; then
      return 1
    fi
  elif ! printf '%s\n' "$real_objects" > "$objects/info/alternates"; then
    return 1
  fi

  export GIT_INDEX_FILE="$index"
  export GIT_OBJECT_DIRECTORY="$objects"
  unset GIT_ALTERNATE_OBJECT_DIRECTORIES

  if ! git -C "$repo" read-tree HEAD 2>/dev/null; then
    return 1
  fi
  if ! _git_stage_history_paths "$repo" "$index"; then
    return 1
  fi
  if ! changes="$(git -C "$repo" diff \
      --cached --name-status --no-renames HEAD -- . \
      ':(exclude).gitignore' 2>/dev/null)"; then
    return 1
  fi
  if [[ -n "$changes" ]]; then
    printf '%s\n' "$changes" | sed 's/^/  /'
  fi
)

# Commits carrying the marker have exact memory semantics: a missing memory
# path means it was absent. Older commits ignored memory, so absence is
# unknowable and restore must preserve the current memory instead.
_git_ref_has_memory_history() {
  local dir="$1" ref="$2" ignore_content
  if ! ignore_content="$(git -C "$dir" show "$ref:.gitignore" 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "$ignore_content" | grep -Fqx "$GITIGNORE_MEMORY_MARKER"
}

# Build profile history in a private index. No staging command touches the real
# index, so an add/filter/path failure cannot leave half-staged deletions. Git's
# commit object is created without updating refs; the fully validated index is
# published first, then update-ref advances HEAD with compare-and-swap. A crash
# therefore leaves either old HEAD plus a complete staged snapshot, or new HEAD
# plus its matching index — never a new commit paired with a stale index.
_git_commit_history_transaction() {
  local dir="$1" msg="$2" allow_empty="${3:-false}"
  local index backup real_index old_index_present=false
  local old_head="" old_tree="" new_tree="" new_commit=""
  local head_ref="" head_ref_status=0
  local has_head=false changed=false

  _GIT_COMMIT_HEAD=""

  real_index="$dir/.git/index"
  if [[ -L "$real_index" || ( -e "$real_index" && ! -f "$real_index" ) ]]; then
    _git_history_warn "$dir" "git index is not a regular file"
    return 0
  fi
  if ! index="$(mktemp "$dir/.git/.claude-profile-index.XXXXXX")"; then
    _git_history_warn "$dir" "could not create a temporary git index"
    return 0
  fi
  # read-tree requires a valid index or no file at all.
  rm -f "$index"

  if old_head="$(git -C "$dir" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)"; then
    has_head=true
    if ! old_tree="$(git -C "$dir" rev-parse --verify 'HEAD^{tree}' 2>/dev/null)"; then
      rm -f "$index"
      _git_history_warn "$dir" "could not resolve current git tree"
      return 0
    fi
    if ! GIT_INDEX_FILE="$index" git -C "$dir" read-tree HEAD 2>/dev/null; then
      rm -f "$index"
      _git_history_warn "$dir" "could not initialize git index"
      return 0
    fi
  else
    # HEAD^{commit} also fails for dangling refs and non-commit objects. Only
    # a symbolic HEAD whose target ref does not exist is genuinely unborn.
    if ! head_ref="$(git -C "$dir" symbolic-ref -q HEAD 2>/dev/null)"; then
      rm -f "$index"
      _git_history_warn "$dir" "could not resolve current git HEAD"
      return 0
    fi
    if git -C "$dir" show-ref --verify --quiet "$head_ref" 2>/dev/null; then
      head_ref_status=0
    else
      head_ref_status=$?
    fi
    if [[ "$head_ref_status" -ne 1 ]]; then
      rm -f "$index"
      _git_history_warn "$dir" "could not resolve current git HEAD"
      return 0
    fi
    if ! GIT_INDEX_FILE="$index" git -C "$dir" read-tree --empty 2>/dev/null; then
      rm -f "$index"
      _git_history_warn "$dir" "could not initialize git index"
      return 0
    fi
  fi

  if ! _git_stage_history_paths "$dir" "$index"; then
    rm -f "$index"
    _git_history_warn "$dir" "git add failed"
    return 0
  fi

  if ! new_tree="$(GIT_INDEX_FILE="$index" git -C "$dir" write-tree 2>/dev/null)"; then
    rm -f "$index"
    _git_history_warn "$dir" "could not write git tree"
    return 0
  fi
  if [[ "$has_head" == true ]]; then
    [[ "$new_tree" == "$old_tree" ]] || changed=true
  else
    changed=true
  fi

  if [[ "$changed" == true || "$allow_empty" == true ]]; then
    local -a commit_tree_args=("$new_tree")
    if [[ "$has_head" == true ]]; then
      commit_tree_args+=(-p "$old_head")
    fi
    # Preserve the repo's commit-signing requirement so a configured but
    # unavailable signer still aborts history, like `git commit`.
    if [[ "$(git -C "$dir" config --bool --get commit.gpgsign 2>/dev/null || true)" == true ]]; then
      commit_tree_args+=(-S)
    fi
    if ! new_commit="$(git -C "$dir" commit-tree \
        "${commit_tree_args[@]}" -m "$msg" 2>/dev/null)"; then
      rm -f "$index"
      _git_history_warn "$dir" "git commit failed — is your git identity configured?"
      return 0
    fi
  fi

  if ! backup="$(mktemp "$dir/.git/.claude-profile-index-backup.XXXXXX")"; then
    rm -f "$index"
    _git_history_warn "$dir" "could not allocate git index backup"
    return 0
  fi
  if [[ -f "$real_index" ]]; then
    if ! cp "$real_index" "$backup" 2>/dev/null; then
      rm -f "$index" "$backup"
      _git_history_warn "$dir" "could not back up git index"
      return 0
    fi
    old_index_present=true
  else
    rm -f "$backup"
  fi
  if ! mv -f "$index" "$real_index"; then
    rm -f "$index" "$backup"
    _git_history_warn "$dir" "could not replace git index"
    return 0
  fi

  if [[ -n "$new_commit" ]]; then
    local update_ok=false
    if [[ "$has_head" == true ]]; then
      if git -C "$dir" update-ref -m "claude-profile history update" HEAD \
          "$new_commit" "$old_head" 2>/dev/null; then
        update_ok=true
      fi
    elif git -C "$dir" update-ref -m "claude-profile history update" \
        HEAD "$new_commit" 2>/dev/null; then
      update_ok=true
    fi
    if [[ "$update_ok" != true ]]; then
      local restored=false
      if [[ "$old_index_present" == true ]]; then
        if mv -f "$backup" "$real_index" 2>/dev/null; then
          restored=true
        fi
      elif rm -f "$real_index" 2>/dev/null; then
        restored=true
      fi
      if [[ "$restored" == true ]]; then
        _git_history_warn "$dir" "could not advance git history; original index restored"
      else
        _git_history_warn "$dir" "could not advance git history; index contains a complete staged snapshot"
      fi
      return 0
    fi
    _GIT_COMMIT_HEAD="$new_commit"
  elif [[ "$has_head" == true ]]; then
    _GIT_COMMIT_HEAD="$old_head"
  fi
  rm -f "$backup"
}

_git_init() {
  local dir="$1" payload_state="${2:-}"
  _assert_profile_path_safe "$dir"
  if [[ -e "$dir/.git" || -L "$dir/.git" ]]; then
    _git_require_safe_profile_repo "$dir" || return 1
  fi
  # A caller may skip the walk only after replacing the complete payload with
  # cp -RL output. Move/direct-commit paths can still contain live symlinks and
  # must retain the full repair before Git sees the worktree.
  if [[ "$payload_state" != "--payload-materialized" ]]; then
    if ! _repair_profile_symlinks "$dir"; then
      _git_history_warn "$dir" "could not dereference profile symlinks"
      return 1
    fi
  fi
  if ! _git_write_ignore_policy "$dir"; then
    _git_history_warn "$dir" "could not update .gitignore"
    return 0
  fi
  if [[ ! -d "$dir/.git" ]]; then
    if ! git -C "$dir" init -q; then
      _git_history_warn "$dir" "git init failed"
      return 0
    fi
    _git_require_safe_profile_repo "$dir" || return 1
    _git_commit_history_transaction "$dir" "Profile created" true
  fi
}

_git_commit() {
  local dir="$1"
  local msg="${2:-Save}"
  local payload_state="${3:-}"
  _GIT_COMMIT_HEAD=""
  _assert_profile_path_safe "$dir"
  if [[ ! -e "$dir/.git" && ! -L "$dir/.git" ]]; then
    if ! _git_init "$dir" "$payload_state"; then
      return 1
    fi
    return 0
  fi
  _git_require_safe_profile_repo "$dir" || return 1
  if [[ "$payload_state" != "--payload-materialized" ]]; then
    if ! _repair_profile_symlinks "$dir"; then
      _git_history_warn "$dir" "could not dereference profile symlinks"
      return 1
    fi
  fi
  if ! _git_write_ignore_policy "$dir"; then
    _git_history_warn "$dir" "could not update .gitignore"
    return 0
  fi
  _git_commit_history_transaction "$dir" "$msg"
}

_git_resolve_ref() {
  local dir="$1" ref="$2"
  local resolved="" date_ref="$ref"

  # Resolve commit-ish refs explicitly so date-like strings don't get
  # misinterpreted by git's date parser.
  if resolved="$(git -C "$dir" rev-parse --verify "${ref}^{commit}" 2>/dev/null)"; then
    echo "$resolved"
    return 0
  fi

  # Git's approxidate parser handles bare YYYY-MM-DD inconsistently for
  # pre-epoch dates. Normalize calendar dates to end-of-day UTC first.
  if [[ "$ref" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    date_ref="${ref}T23:59:59Z"
  fi

  resolved="$(git -C "$dir" rev-list -1 --before="$date_ref" HEAD 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    err "Could not resolve '$ref' as commit or date"
    exit 1
  fi

  echo "$resolved"
}
