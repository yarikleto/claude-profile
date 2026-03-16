# git.sh — Git history tracking for profile directories

_git_init() {
  local dir="$1"
  if [[ ! -d "$dir/.git" ]]; then
    # Exclude bulk items from git tracking
    local gitignore=""
    for item in "${BULK_ITEMS[@]}"; do
      local iname
      iname="$(_item_name "$item")"
      gitignore+="/$iname"$'\n'
    done
    if [[ -n "$gitignore" ]]; then
      echo "$gitignore" > "$dir/.gitignore"
    fi
    git -C "$dir" init -q
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "Profile created" --allow-empty 2>/dev/null || true
  fi
}

_git_commit() {
  local dir="$1"
  local msg="${2:-Save}"
  [[ -d "$dir/.git" ]] || _git_init "$dir"
  git -C "$dir" add -A
  if ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
    git -C "$dir" commit -q -m "$msg" 2>/dev/null || true
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
