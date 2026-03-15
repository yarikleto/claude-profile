# ui.sh — Shell prompt and Claude Code status line integration

cmd_prompt_init() {
  local shell="${1:-zsh}"

  case "$shell" in
    zsh)
      cat <<'INIT'
# claude-profile prompt integration (zsh)
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
# claude-profile prompt integration (bash)
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
    plain)
      cat <<'INIT'
_claude_profile_current() {
  local f="${CLAUDE_CODE_HOME:-$HOME/.claude}/profiles/.current"
  [[ -f "$f" ]] && tr -cd 'a-zA-Z0-9._-' < "$f"
}
INIT
      ;;
    *)
      err "Supported shells: zsh, bash, plain"
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

      ok "Status line script installed at $statusline_script"
      info "Restart Claude Code to see it"
      ;;

    uninstall)
      if [[ -f "$statusline_script" ]]; then
        rm "$statusline_script"
        ok "Removed $statusline_script"
        warn "You may want to remove 'statusLine' from settings.json manually"
      else
        warn "No status line script found"
      fi
      ;;

    *)
      err "Usage: claude-profile statusline [install|uninstall]"
      exit 1
      ;;
  esac
}
