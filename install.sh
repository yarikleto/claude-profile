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
install_completions() {
  local shell_type="$1" src="$2" filename="$3"
  local target="${COMPLETIONS_DIR:-}"

  if [[ -z "$target" ]]; then
    case "$shell_type" in
      zsh)
        if [[ -d "$HOME/.oh-my-zsh/completions" ]]; then
          target="$HOME/.oh-my-zsh/completions"
        else
          target="$HOME/.local/share/zsh/site-functions"
          mkdir -p "$target"
        fi
        ;;
      bash)
        target="$HOME/.local/share/bash-completion/completions"
        mkdir -p "$target"
        ;;
    esac
  fi

  if [[ -f "$src" && -n "$target" ]]; then
    cp "$src" "$target/$filename"
    ok "$shell_type completions → $target/$filename"
  fi
}

current_shell="$(basename "${SHELL:-bash}")"
case "$current_shell" in
  zsh)  install_completions zsh "$SCRIPT_DIR/completions/claude-profile.zsh" "_claude-profile" ;;
  bash) install_completions bash "$SCRIPT_DIR/completions/claude-profile.bash" "claude-profile" ;;
  *)    install_completions zsh "$SCRIPT_DIR/completions/claude-profile.zsh" "_claude-profile"
        install_completions bash "$SCRIPT_DIR/completions/claude-profile.bash" "claude-profile" ;;
esac

# ─── Create seed directory ──────────────────────────────────
CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"
SEED_DIR="$CLAUDE_DIR/__profiles__/.seed"
if [[ ! -d "$SEED_DIR" ]]; then
  mkdir -p "$SEED_DIR"
  echo '{}' > "$SEED_DIR/settings.json"
  echo '{}' > "$SEED_DIR/.claude.json"
  ok "Created seed templates in $SEED_DIR"
fi

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

echo ""
ok "Installation complete!"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo "    claude-profile fork default    # Save your current setup"
echo "    claude-profile new experiment  # Create a clean profile"
echo "    claude-profile use experiment  # Switch profiles"
echo ""
