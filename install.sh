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
ZDOTDIR_PATH="${ZDOTDIR:-$HOME}"
ZSH_COMPLETIONS_INSTALLED=""
BASH_COMPLETIONS_INSTALLED=""

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

install_zsh_completions() {
  local src="$1" filename="$2"
  local target="${COMPLETIONS_DIR:-}"
  local omz_custom=""

  if [[ -z "$target" ]]; then
    omz_custom="$(detect_oh_my_zsh_custom_dir)"
    if [[ -n "$omz_custom" ]]; then
      # oh-my-zsh auto-loads $ZSH_CUSTOM/completions via fpath
      target="$omz_custom/completions"
    else
      # Use ~/.zfunc — conventional user completion dir for zsh
      target="$HOME/.zfunc"
      # Check if fpath already includes it (via .zshrc)
      if ! grep -q '\.zfunc' "$ZDOTDIR_PATH/.zshrc" 2>/dev/null; then
        COMPLETIONS_NEED_SETUP="zsh"
      fi
    fi
  fi

  mkdir -p "$target"
  if [[ -f "$src" ]]; then
    cp "$src" "$target/$filename"
    ZSH_COMPLETIONS_INSTALLED=1
    clear_zsh_completion_cache
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
    BASH_COMPLETIONS_INSTALLED=1
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

# ─── Resolve profiles dir ──────────────────────────────────
CLAUDE_DIR="${CLAUDE_CODE_HOME:-$HOME/.claude}"
if [[ -n "${CLAUDE_PROFILE_HOME:-}" ]]; then
  PROFILES_DIR="$CLAUDE_PROFILE_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  PROFILES_DIR="$XDG_DATA_HOME/claude-profile"
else
  PROFILES_DIR="$HOME/.local/share/claude-profile"
fi

# ─── Migrate from old location ──────────────────────────────
OLD_PROFILES_DIR="$CLAUDE_DIR/__profiles__"
if [[ -d "$OLD_PROFILES_DIR" && ! -d "$PROFILES_DIR" && ! -L "$PROFILES_DIR" ]]; then
  info "Migrating profiles from $OLD_PROFILES_DIR to $PROFILES_DIR..."
  mkdir -p "$(dirname "$PROFILES_DIR")"
  mv "$OLD_PROFILES_DIR" "$PROFILES_DIR"
  ok "Migrated profiles to $PROFILES_DIR"
fi

# ─── Create seed directory ──────────────────────────────────
SEED_DIR="$PROFILES_DIR/.seed"
if [[ ! -d "$SEED_DIR" ]]; then
  mkdir -p "$SEED_DIR"
  echo '{}' > "$SEED_DIR/settings.json"
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

# ─── Auto-configure shell completions ───────────────────────
COMPLETION_BEGIN="# >>> claude-profile completions >>>"
COMPLETION_END="# <<< claude-profile completions <<<"

if [[ "$COMPLETIONS_NEED_SETUP" == *"zsh"* ]]; then
  rc="$ZDOTDIR_PATH/.zshrc"
  if ! grep -q "$COMPLETION_BEGIN" "$rc" 2>/dev/null; then
    cat >> "$rc" << 'ZSHEOF'

# >>> claude-profile completions >>>
fpath=(~/.zfunc $fpath)
autoload -Uz compinit && compinit
# <<< claude-profile completions <<<
ZSHEOF
    ok "Added completion setup to ~/.zshrc"
  fi
fi

if [[ "$COMPLETIONS_NEED_SETUP" == *"bash"* ]]; then
  rc="$HOME/.bashrc"
  if ! grep -q "$COMPLETION_BEGIN" "$rc" 2>/dev/null; then
    cat >> "$rc" << 'BASHEOF'

# >>> claude-profile completions >>>
source ~/.local/share/bash-completion/completions/claude-profile
# <<< claude-profile completions <<<
BASHEOF
    ok "Added completion setup to ~/.bashrc"
  fi
fi

echo ""
ok "Installation complete!"
if [[ -n "$ZSH_COMPLETIONS_INSTALLED" ]]; then
  info "Open a new zsh session once to load completions immediately (for example: exec zsh)"
fi
if [[ -n "$BASH_COMPLETIONS_INSTALLED" ]]; then
  info "Open a new bash session or source ~/.bashrc to load completions"
fi
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo "    claude-profile fork default    # Save your current setup"
echo "    claude-profile new experiment  # Create a clean profile"
echo "    claude-profile use experiment  # Switch profiles"
echo ""
