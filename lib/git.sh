# git.sh — Git history tracking for profile directories

_git_history_warn() {
  local dir="$1" why="$2"
  warn "Could not record history for '$(basename "$dir")' ($why) — files saved, history skipped"
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
      if ! custom="$(awk -v begin="$GITIGNORE_MANAGED_BEGIN" -v end="$GITIGNORE_MANAGED_END" '
        function flush_buffer(  i) {
          for (i = 1; i <= buffered; i++) print buffer[i]
          buffered = 0
        }
        $0 == begin && !inside {
          inside = 1
          buffer[++buffered] = $0
          next
        }
        $0 == begin && inside {
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
      projects agent-memory >/dev/null 2>&1; then
    return 1
  fi
  if ! git -C "$dir" add -A -- . \
      ':(exclude,top)projects' \
      ':(exclude,top,glob)projects/**' \
      ':(exclude,top)agent-memory' \
      ':(exclude,top,glob)agent-memory/**' 2>/dev/null; then
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
  if [[ -e "$dir/agent-memory" || -L "$dir/agent-memory" ]]; then
    memory_paths+=(agent-memory)
  fi
  # Include dot-prefixed project keys as well as Claude Code's usual encoded
  # names. Arrays plus `--` keep whitespace, newlines, and pathspec-like names
  # literal when handed to Git.
  for memory_dir in \
      "$dir"/projects/*/memory \
      "$dir"/projects/.[!.]*/memory \
      "$dir"/projects/..?*/memory; do
    if [[ ! -e "$memory_dir" && ! -L "$memory_dir" ]]; then
      continue
    fi
    memory_paths+=("${memory_dir#"$dir"/}")
  done
  if [[ "${#memory_paths[@]}" -gt 0 ]]; then
    if ! git -C "$dir" add -f -A -- "${memory_paths[@]}" 2>/dev/null; then
      return 1
    fi
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

_git_init() {
  local dir="$1"
  if ! _git_write_ignore_policy "$dir"; then
    _git_history_warn "$dir" "could not update .gitignore"
    return 0
  fi
  if [[ ! -d "$dir/.git" ]]; then
    git -C "$dir" init -q
    if ! _git_stage_history_paths "$dir"; then
      _git_history_warn "$dir" "git add failed"
      return 0
    fi
    if ! git -C "$dir" commit -q -m "Profile created" --allow-empty 2>/dev/null; then
      _git_history_warn "$dir" "git commit failed — is your git identity configured?"
    fi
  fi
}

_git_commit() {
  local dir="$1"
  local msg="${2:-Save}"
  [[ -d "$dir/.git" ]] || _git_init "$dir"
  if ! _git_write_ignore_policy "$dir"; then
    _git_history_warn "$dir" "could not update .gitignore"
    return 0
  fi
  if ! _git_stage_history_paths "$dir"; then
    _git_history_warn "$dir" "git add failed"
    return 0
  fi
  if ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
    if ! git -C "$dir" commit -q -m "$msg" 2>/dev/null; then
      _git_history_warn "$dir" "git commit failed — is your git identity configured?"
    fi
  fi
}

# Resolve a ref (commit hash or date string) to a commit hash.
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
