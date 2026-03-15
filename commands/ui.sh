# ui.sh — Shell prompt and Claude Code status line integration

cmd_statusline() {
  local action="${1:-install}"
  local statusline_script="$PROFILES_DIR/statusline.sh"

  case "$action" in
    install)
      cat > "$statusline_script" <<'SCRIPT'
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
          if sed '$ s/}/,\n  "statusLine": { "type": "command", "command": "~\/.claude\/__profiles__\/statusline.sh" }\n}/' "$settings" > "$tmp"; then
            mv "$tmp" "$settings"
            ok "Status line configured in settings.json"
          else
            rm -f "$tmp"
            err "Failed to update settings.json"
            exit 1
          fi
        fi
      else
        echo '{ "statusLine": { "type": "command", "command": "~/.claude/__profiles__/statusline.sh" } }' > "$settings"
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
