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
  echo '{ "statusLine": { "type": "command", "command": "~/.claude/__profiles__/statusline.sh" } }' > "$SEED_DIR/settings.json"
  echo '{}' > "$SEED_DIR/.claude.json"
  ok "Created seed templates in $SEED_DIR"
fi

# ─── Install statusline ─────────────────────────────────────
STATUSLINE_SCRIPT="$CLAUDE_DIR/__profiles__/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

# Create the statusline script
cat > "$STATUSLINE_SCRIPT" <<'SCRIPT'
#!/bin/bash
input=$(cat)
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | cut -d'"' -f4)
model="${model:-Claude}"
profile_file="${CLAUDE_CODE_HOME:-$HOME/.claude}/__profiles__/.current"
if [[ -f "$profile_file" ]]; then
  profile="$(tr -cd 'a-zA-Z0-9._-' < "$profile_file")"
  echo "${model} · profile: ${profile}"
else
  echo "${model}"
fi
SCRIPT
chmod +x "$STATUSLINE_SCRIPT"

# Add statusLine to settings.json only if not already configured
if [[ -f "$SETTINGS" ]]; then
  if ! grep -q '"statusLine"' "$SETTINGS"; then
    _install_added=false
    if command -v jq &>/dev/null; then
      tmp="$(mktemp)"
      if jq '. + {"statusLine": {"type": "command", "command": "~/.claude/__profiles__/statusline.sh"}}' \
        "$SETTINGS" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$SETTINGS"
        _install_added=true
      else
        rm -f "$tmp"
      fi
    fi
    if [[ "$_install_added" != true ]] && command -v python3 &>/dev/null; then
      if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': '~/.claude/__profiles__/statusline.sh'}
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
" "$SETTINGS" 2>/dev/null; then
        _install_added=true
      fi
    fi
    if [[ "$_install_added" != true ]] && command -v node &>/dev/null; then
      if node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
data.statusLine = {type: 'command', command: '~/.claude/__profiles__/statusline.sh'};
fs.writeFileSync(process.argv[1], JSON.stringify(data, null, 2) + '\n');
" "$SETTINGS" 2>/dev/null; then
        _install_added=true
      fi
    fi
    if [[ "$_install_added" == true ]]; then
      ok "Status line added to settings.json"
    else
      info "Add statusLine manually to settings.json:"
      echo '  "statusLine": { "type": "command", "command": "~/.claude/__profiles__/statusline.sh" }'
    fi
  fi
elif [[ ! -f "$SETTINGS" ]]; then
  echo '{ "statusLine": { "type": "command", "command": "~/.claude/__profiles__/statusline.sh" } }' > "$SETTINGS"
  ok "Created settings.json with status line"
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
