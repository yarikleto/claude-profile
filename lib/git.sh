# git.sh — Git history tracking for profile directories

_git_init() {
  local dir="$1"
  if [[ ! -d "$dir/.git" ]]; then
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
  if git -C "$dir" rev-parse --verify "$ref" &>/dev/null; then
    echo "$ref"
  else
    local resolved
    resolved="$(git -C "$dir" log --format='%H' --before="$ref" -1 2>/dev/null || true)"
    if [[ -z "$resolved" ]]; then
      err "Could not resolve '$ref' as commit or date"
      exit 1
    fi
    echo "$resolved"
  fi
}
