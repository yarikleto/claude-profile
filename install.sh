#!/usr/bin/env bash
# Install claude-profile
set -euo pipefail

INSTALL_DIR="${CLAUDE_PROFILE_INSTALL_DIR:-$HOME/.local/bin}"
COMPLETIONS_DIR="${CLAUDE_PROFILE_COMPLETIONS_DIR:-}"

RED='\033[0;31m' GREEN='\033[0;32m' BLUE='\033[0;34m'
BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'

info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/claude-profile" ]]; then
  err "Run install.sh from the cloned repo directory"
fi

info "Installing from $SCRIPT_DIR..."

# ─── Install binary + modules ──────────────────────────────
INSTALL_LIB="$INSTALL_DIR/claude-profile-lib"
mkdir -p "$INSTALL_DIR" "$INSTALL_LIB/lib" "$INSTALL_LIB/commands"

cp "$SCRIPT_DIR/claude-profile" "$INSTALL_DIR/claude-profile"
cp "$SCRIPT_DIR"/lib/*.sh "$INSTALL_LIB/lib/"
cp "$SCRIPT_DIR"/commands/*.sh "$INSTALL_LIB/commands/"
chmod +x "$INSTALL_DIR/claude-profile"

# Patch SCRIPT_DIR in installed binary to point to lib location
sed -i.bak "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$INSTALL_LIB\"|" "$INSTALL_DIR/claude-profile"
rm -f "$INSTALL_DIR/claude-profile.bak"

ok "Installed to $INSTALL_DIR/claude-profile"

# ─── Install shell completions ──────────────────────────────
COMPLETIONS_NEED_SETUP=""

install_zsh_completions() {
  local src="$1" filename="$2"
  local target="${COMPLETIONS_DIR:-}"

  if [[ -z "$target" ]]; then
    if [[ -d "$HOME/.oh-my-zsh/completions" ]]; then
      # oh-my-zsh auto-loads this directory
      target="$HOME/.oh-my-zsh/completions"
    else
      # Use ~/.zfunc — conventional user completion dir for zsh
      target="$HOME/.zfunc"
      # Check if fpath already includes it (via .zshrc)
      if ! grep -q '\.zfunc' "$HOME/.zshrc" 2>/dev/null; then
        COMPLETIONS_NEED_SETUP="zsh"
      fi
    fi
  fi

  mkdir -p "$target"
  if [[ -f "$src" ]]; then
    cp "$src" "$target/$filename"
    ok "zsh completions → $target/$filename"
  fi
}

install_bash_completions() {
  local src="$1" filename="$2"
  local target="${COMPLETIONS_DIR:-}"

  if [[ -z "$target" ]]; then
    # Check if bash-completion v2 is available (supports user completions dir)
    if [[ -d "$HOME/.local/share/bash-completion/completions" ]] || \
       bash -c 'pkg-config --exists bash-completion 2>/dev/null' 2>/dev/null; then
      target="$HOME/.local/share/bash-completion/completions"
    else
      # Fall back to same dir — will print setup instructions
      target="$HOME/.local/share/bash-completion/completions"
      COMPLETIONS_NEED_SETUP="${COMPLETIONS_NEED_SETUP:+$COMPLETIONS_NEED_SETUP+}bash"
    fi
  fi

  mkdir -p "$target"
  if [[ -f "$src" ]]; then
    cp "$src" "$target/$filename"
    ok "bash completions → $target/$filename"
  fi
}

current_shell="$(basename "${SHELL:-bash}")"
case "$current_shell" in
  zsh)  install_zsh_completions "$SCRIPT_DIR/completions/claude-profile.zsh" "_claude-profile" ;;
  bash) install_bash_completions "$SCRIPT_DIR/completions/claude-profile.bash" "claude-profile" ;;
  *)    install_zsh_completions "$SCRIPT_DIR/completions/claude-profile.zsh" "_claude-profile"
        install_bash_completions "$SCRIPT_DIR/completions/claude-profile.bash" "claude-profile" ;;
esac

# ─── Create seed directory ──────────────────────────────────
CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"
SEED_DIR="$CLAUDE_DIR/__profiles__/.seed"
if [[ ! -d "$SEED_DIR" ]]; then
  mkdir -p "$SEED_DIR"
  echo '{ "statusLine": { "type": "command", "command": "~/.claude/__profiles__/statusline.sh" } }' > "$SEED_DIR/settings.json"
  echo '{}' > "$SEED_DIR/.claude.json"
  ok "Created seed templates in $SEED_DIR"
fi

# ─── Install statusline ─────────────────────────────────────
"$INSTALL_DIR/claude-profile" statusline install

# ─── Check PATH ─────────────────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo -e "${BOLD}Add to your PATH:${NC}"
  echo ""
  case "$current_shell" in
    zsh)  echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc" ;;
    bash) echo "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc && source ~/.bashrc" ;;
    *)    echo "  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
  esac
  echo ""
fi

# ─── Completion setup instructions ───────────────────────────
if [[ "$COMPLETIONS_NEED_SETUP" == *"zsh"* ]]; then
  echo ""
  echo -e "${BOLD}Enable tab completions (zsh):${NC}"
  echo ""
  echo "  Add to your ~/.zshrc (before compinit):"
  echo ""
  echo "    fpath=(~/.zfunc \$fpath)"
  echo "    autoload -Uz compinit && compinit"
  echo ""
  echo "  Then: source ~/.zshrc"
fi

if [[ "$COMPLETIONS_NEED_SETUP" == *"bash"* ]]; then
  echo ""
  echo -e "${BOLD}Enable tab completions (bash):${NC}"
  echo ""
  echo "  Add to your ~/.bashrc:"
  echo ""
  echo "    source ~/.local/share/bash-completion/completions/claude-profile"
  echo ""
  echo "  Then: source ~/.bashrc"
fi

echo ""
ok "Installation complete!"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo "    claude-profile fork default    # Save your current setup"
echo "    claude-profile new experiment  # Create a clean profile"
echo "    claude-profile use experiment  # Switch profiles"
echo ""
