#!/usr/bin/env bash
# Uninstall claude-profile
set -euo pipefail

INSTALL_DIR="${CLAUDE_PROFILE_INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_LIB="$INSTALL_DIR/claude-profile-lib"

GREEN='\033[0;32m' BLUE='\033[0;34m' NC='\033[0m'
info() { echo -e "${BLUE}▸${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
ZDOTDIR_PATH="${ZDOTDIR:-$HOME}"

expand_home_path() {
  local path="$1"
  path="${path/#\~/$HOME}"
  path="${path//\$\{HOME\}/$HOME}"
  path="${path//\$HOME/$HOME}"
  printf '%s\n' "$path"
}

detect_oh_my_zsh_custom_dir() {
  local rc="$ZDOTDIR_PATH/.zshrc"
  local custom_dir=""

  if [[ -n "${ZSH_CUSTOM:-}" ]]; then
    expand_home_path "$ZSH_CUSTOM"
    return 0
  fi

  if [[ -f "$rc" ]]; then
    custom_dir="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?ZSH_CUSTOM=//p' "$rc" | tail -n 1)"
    custom_dir="${custom_dir%\"}"
    custom_dir="${custom_dir#\"}"
    custom_dir="${custom_dir%\'}"
    custom_dir="${custom_dir#\'}"
    if [[ -n "$custom_dir" ]]; then
      expand_home_path "$custom_dir"
      return 0
    fi
  fi

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    printf '%s\n' "$HOME/.oh-my-zsh/custom"
  fi

  return 0
}

clear_zsh_completion_cache() {
  local dump_files=()
  shopt -s nullglob
  dump_files=("$ZDOTDIR_PATH"/.zcompdump*)
  shopt -u nullglob

  if (( ${#dump_files[@]} )); then
    rm -f "${dump_files[@]}"
    ok "Cleared zsh completion cache"
  fi
}

# Remove binary
if [[ -f "$INSTALL_DIR/claude-profile" ]]; then
  rm "$INSTALL_DIR/claude-profile"
  ok "Removed $INSTALL_DIR/claude-profile"
fi

# Remove lib modules
if [[ -d "$INSTALL_LIB" ]]; then
  rm -rf "$INSTALL_LIB"
  ok "Removed $INSTALL_LIB"
fi

# Remove completions
COMPLETIONS_DIR="${CLAUDE_PROFILE_COMPLETIONS_DIR:-}"
OH_MY_ZSH_CUSTOM="$(detect_oh_my_zsh_custom_dir)"
for f in \
  "$HOME/.oh-my-zsh/completions/_claude-profile" \
  ${OH_MY_ZSH_CUSTOM:+"$OH_MY_ZSH_CUSTOM/completions/_claude-profile"} \
  "$HOME/.zfunc/_claude-profile" \
  "$HOME/.local/share/zsh/site-functions/_claude-profile" \
  "$HOME/.local/share/bash-completion/completions/claude-profile" \
  ${COMPLETIONS_DIR:+"$COMPLETIONS_DIR/_claude-profile"} \
  ${COMPLETIONS_DIR:+"$COMPLETIONS_DIR/claude-profile"}; do
  if [[ -f "$f" ]]; then
    rm "$f"
    ok "Removed $f"
  fi
done
clear_zsh_completion_cache

# Remove completion setup from shell rc files
for rc in "$ZDOTDIR_PATH/.zshrc" "$HOME/.bashrc"; do
  if [[ -f "$rc" ]] && grep -q '# >>> claude-profile completions >>>' "$rc"; then
    sed -i.bak '/# >>> claude-profile completions >>>/,/# <<< claude-profile completions <<</d' "$rc"
    rm -f "$rc.bak"
    ok "Removed completion setup from $(basename "$rc")"
  fi
done

echo ""
info "Profiles are kept in ~/.claude/__profiles__/ — delete manually if needed."
echo ""
ok "Uninstall complete"
