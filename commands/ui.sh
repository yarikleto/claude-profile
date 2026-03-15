# ui.sh — Shell prompt and Claude Code status line integration

_PROMPT_MARKER="# claude-profile prompt"
_PROMPT_SOURCE_LINE='eval "$(claude-profile prompt-init __SHELL__)"'

_prompt_snippet() {
  local shell="$1"
  case "$shell" in
    zsh)
      cat <<'INIT'
_claude_profile_current() {
  local f="${CLAUDE_CODE_HOME:-$HOME/.claude}/profiles/.current"
  if [[ -f "$f" ]]; then
    local name
    name="$(tr -cd 'a-zA-Z0-9._-' < "$f")"
    echo " %F{blue}[%f%F{cyan}${name}%f%F{blue}]%f"
  fi
}
setopt PROMPT_SUBST
RPROMPT='$(_claude_profile_current)'"${RPROMPT:+ $RPROMPT}"
INIT
      ;;
    bash)
      cat <<'INIT'
_claude_profile_current() {
  local f="${CLAUDE_CODE_HOME:-$HOME/.claude}/profiles/.current"
  if [[ -f "$f" ]]; then
    local name
    name="$(tr -cd 'a-zA-Z0-9._-' < "$f")"
    echo " [\033[36m${name}\033[0m]"
  fi
}
PS1="${PS1/%\\$ / \$(_claude_profile_current)\\$ }"
INIT
      ;;
    *)
      err "Supported shells: ${BOLD}zsh${NC}, ${BOLD}bash${NC}"
      exit 1
      ;;
  esac
}

_detect_shell() {
  local name
  name="$(basename "${SHELL:-}")"
  case "$name" in
    zsh|bash) echo "$name" ;;
    *) echo "zsh" ;;
  esac
}

_rc_file() {
  local shell="$1"
  case "$shell" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) echo "$HOME/.bashrc" ;;
  esac
}

cmd_prompt_init() {
  local action="${1:-}"
  local shell="${2:-}"

  # If first arg is a shell name (legacy: `prompt-init zsh`), print snippet
  if [[ "$action" == "zsh" || "$action" == "bash" ]]; then
    echo "$_PROMPT_MARKER ($action)"
    _prompt_snippet "$action"
    return
  fi

  shell="${shell:-$(_detect_shell)}"
  local rc
  rc="$(_rc_file "$shell")"
  local source_line="${_PROMPT_SOURCE_LINE/__SHELL__/$shell}"

  case "$action" in
    install)
      if [[ -f "$rc" ]] && grep -qF "$_PROMPT_MARKER" "$rc"; then
        ok "Already installed in ${BOLD}$rc${NC}"
        return
      fi

      echo "" >> "$rc"
      echo "$_PROMPT_MARKER" >> "$rc"
      echo "$source_line" >> "$rc"

      ok "Added to ${BOLD}$rc${NC}"
      info "Restart your shell or run: ${BOLD}source $rc${NC}"
      ;;

    uninstall)
      if [[ ! -f "$rc" ]] || ! grep -qF "$_PROMPT_MARKER" "$rc"; then
        warn "Not installed in ${BOLD}$rc${NC}"
        return
      fi

      local tmp
      tmp="$(mktemp)"
      grep -vF "$_PROMPT_MARKER" "$rc" | grep -vF 'claude-profile prompt-init' > "$tmp"
      mv "$tmp" "$rc"

      ok "Removed from ${BOLD}$rc${NC}"
      info "Restart your shell or run: ${BOLD}source $rc${NC}"
      ;;

    "")
      err "Usage: claude-profile prompt-init ${BOLD}install${NC}|${BOLD}uninstall${NC} [zsh|bash]"
      echo ""
      echo -e "  ${BOLD}install${NC}    Add prompt integration to your shell rc file"
      echo -e "  ${BOLD}uninstall${NC}  Remove it"
      echo ""
      echo -e "  ${DIM}Shell is auto-detected from \$SHELL (current: $(_detect_shell))${NC}"
      exit 1
      ;;

    *)
      err "Usage: claude-profile prompt-init ${BOLD}install${NC}|${BOLD}uninstall${NC} [zsh|bash]"
      exit 1
      ;;
  esac
}

cmd_statusline() {
  local action="${1:-install}"
  local statusline_script="$CLAUDE_DIR/statusline-profile.sh"

  case "$action" in
    install)
      cat > "$statusline_script" <<'SCRIPT'
#!/bin/bash
input=$(cat)
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | cut -d'"' -f4)
model="${model:-Claude}"
profile_file="${CLAUDE_CODE_HOME:-$HOME/.claude}/profiles/.current"
if [[ -f "$profile_file" ]]; then
  profile="$(tr -cd 'a-zA-Z0-9._-' < "$profile_file")"
  echo "${model} · profile: ${profile}"
else
  echo "${model}"
fi
SCRIPT
      chmod +x "$statusline_script"

      local settings="$CLAUDE_DIR/settings.json"
      if [[ -f "$settings" ]]; then
        if grep -q '"statusLine"' "$settings"; then
          warn "statusLine already configured in settings.json"
          info "Manually set it to:"
          echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" }"
        else
          local tmp
          tmp="$(mktemp)"
          if sed '$ s/}/,\n  "statusLine": { "type": "command", "command": "~\/.claude\/statusline-profile.sh" }\n}/' "$settings" > "$tmp"; then
            mv "$tmp" "$settings"
            ok "Status line configured in settings.json"
          else
            rm -f "$tmp"
            err "Failed to update settings.json"
            exit 1
          fi
        fi
      else
        echo '{ "statusLine": { "type": "command", "command": "~/.claude/statusline-profile.sh" } }' > "$settings"
        ok "Created settings.json with status line"
      fi

      ok "Status line script installed at ${BOLD}$statusline_script${NC}"
      info "Restart Claude Code to see it"
      ;;

    uninstall)
      if [[ -f "$statusline_script" ]]; then
        rm "$statusline_script"
        ok "Removed ${BOLD}$statusline_script${NC}"
        warn "You may want to remove 'statusLine' from settings.json manually"
      else
        warn "No status line script found"
      fi
      ;;

    *)
      err "Usage: claude-profile statusline ${BOLD}install${NC}|${BOLD}uninstall${NC}"
      exit 1
      ;;
  esac
}
