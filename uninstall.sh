#!/usr/bin/env bash
# Uninstall claude-profile
set -euo pipefail

INSTALL_DIR="${CLAUDE_PROFILE_INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_LIB="$INSTALL_DIR/claude-profile-lib"

GREEN='\033[0;32m' BLUE='\033[0;34m' NC='\033[0m'
info() { echo -e "${BLUE}▸${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }

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
for f in \
  "$HOME/.oh-my-zsh/completions/_claude-profile" \
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

# Remove completion setup from shell rc files
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
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
