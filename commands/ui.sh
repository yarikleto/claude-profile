# ui.sh — Shell prompt and Claude Code status line integration

# Add statusLine key to a JSON settings file using available JSON tools.
# Falls back through jq → python3 → node, or errors with manual instructions.
_add_statusline_to_json() {
  local settings="$1" script_path="$2"
  local tmp
  tmp="$(mktemp)"

  if command -v jq &>/dev/null; then
    if jq --arg cmd "$script_path" \
      '. + {"statusLine": {"type": "command", "command": $cmd}}' \
      "$settings" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$settings"
      return 0
    fi
  fi

  if command -v python3 &>/dev/null; then
    if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['statusLine'] = {'type': 'command', 'command': sys.argv[2]}
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
" "$settings" "$script_path" 2>/dev/null; then
      rm -f "$tmp"
      return 0
    fi
  fi

  if command -v node &>/dev/null; then
    if node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
data.statusLine = {type: 'command', command: process.argv[2]};
fs.writeFileSync(process.argv[1], JSON.stringify(data, null, 2) + '\n');
" "$settings" "$script_path" 2>/dev/null; then
      rm -f "$tmp"
      return 0
    fi
  fi

  rm -f "$tmp"
  return 1
}

cmd_statusline() {
  local action="${1:-install}"
  ensure_dir
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
          if _add_statusline_to_json "$settings" "$statusline_script"; then
            ok "Status line configured in settings.json"
          else
            err "Could not update settings.json (no jq, python3, or node found)"
            info "Add manually to settings.json:"
            echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" }"
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
