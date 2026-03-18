# ui.sh — Shell prompt and Claude Code status line integration

# Safely merge a key into a JSON file. Uses jq, python3, or node (first available).
_json_merge() {
  local file="$1" key="$2" value="$3"
  local tmp

  if command -v jq &>/dev/null; then
    tmp="$(mktemp)"
    if jq --arg k "$key" --arg v "$value" '. + {($k): {"type": "command", "command": $v}}' "$file" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$file"; return 0
    fi
    rm -f "$tmp"
  fi

  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d[sys.argv[2]] = {'type': 'command', 'command': sys.argv[3]}
with open(p, 'w') as f: json.dump(d, f, indent=2)
" "$file" "$key" "$value" 2>/dev/null && return 0
  fi

  if command -v node &>/dev/null; then
    node -e "
const fs=require('fs'), f=process.argv[1];
const d=JSON.parse(fs.readFileSync(f,'utf8'));
d[process.argv[2]]={type:'command',command:process.argv[3]};
fs.writeFileSync(f,JSON.stringify(d,null,2)+'\n');
" "$file" "$key" "$value" 2>/dev/null && return 0
  fi

  return 1
}

cmd_statusline() {
  local action="${1:-install}"
  ensure_dir
  local statusline_script="$PROFILES_DIR/statusline.sh"

  case "$action" in
    install)
      if [[ -L "$statusline_script" ]]; then
        err "Refusing to overwrite symlink at $statusline_script"
        exit 1
      fi
      cat > "$statusline_script" <<'SCRIPT'
#!/bin/bash
input=$(cat)
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | cut -d'"' -f4)
model="${model:-Claude}"
# Resolve profiles dir: CLAUDE_PROFILE_HOME > XDG_DATA_HOME > default
if [[ -n "${CLAUDE_PROFILE_HOME:-}" ]]; then
  _profiles_dir="$CLAUDE_PROFILE_HOME"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
  _profiles_dir="$XDG_DATA_HOME/claude-profile"
else
  _profiles_dir="$HOME/.local/share/claude-profile"
fi
profile_file="$_profiles_dir/.current"
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
          if _json_merge "$settings" "statusLine" "$statusline_script"; then
            ok "Status line configured in settings.json"
          else
            err "Could not update settings.json (no jq, python3, or node found)"
            info "Add manually to settings.json:"
            echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" }"
            exit 1
          fi
        fi
      else
        mkdir -p "$CLAUDE_DIR"
        echo "{ \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" } }" > "$settings"
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
