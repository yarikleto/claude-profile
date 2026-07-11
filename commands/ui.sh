# ui.sh — Shell prompt and Claude Code status line integration

# Resolve a chain of symlinks to the real file path, portably (macOS `readlink`
# has no -f). Non-symlinks pass through unchanged.
_resolve_symlink() {
  local f="$1" target
  while [[ -L "$f" ]]; do
    target="$(readlink "$f")"
    if [[ "$target" == /* ]]; then
      f="$target"
    else
      f="$(dirname "$f")/$target"
    fi
  done
  printf '%s\n' "$f"
}

# True (0) when $file parses as JSON with any available tool.
_json_valid() {
  local file="$1"
  if command -v jq &>/dev/null; then
    jq -e . "$file" >/dev/null 2>&1
    return
  fi
  if command -v python3 &>/dev/null; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file" >/dev/null 2>&1
    return
  fi
  if command -v node &>/dev/null; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$file" >/dev/null 2>&1
    return
  fi
  return 1
}

# Merge a key into a JSON file. Uses jq, python3, or node (first available).
# The merged JSON is built in a temp beside the *resolved* target and then
# atomically renamed onto it — a symlinked settings.json stays a symlink, an
# interrupted or unpermitted write never truncates the original, and the write
# is checked so callers hear about a failure instead of a false success.
# Returns 1 on any failure (no tool, invalid JSON, unwritable target).
_json_merge() {
  local file="$1" key="$2" value="$3"
  local real dir tmp produced=1

  real="$(_resolve_symlink "$file")"
  dir="$(dirname "$real")"
  tmp="$(mktemp "$dir/.statusline-merge.XXXXXX" 2>/dev/null)" || return 1

  if command -v jq &>/dev/null; then
    if jq --arg k "$key" --arg v "$value" '. + {($k): {"type": "command", "command": $v}}' "$file" > "$tmp" 2>/dev/null; then
      produced=0
    fi
  fi

  if [[ $produced -ne 0 ]] && command -v python3 &>/dev/null; then
    if python3 -c "
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
d[sys.argv[2]] = {'type': 'command', 'command': sys.argv[3]}
with open(sys.argv[4], 'w') as f: json.dump(d, f, indent=2)
" "$file" "$key" "$value" "$tmp" 2>/dev/null; then
      produced=0
    fi
  fi

  if [[ $produced -ne 0 ]] && command -v node &>/dev/null; then
    if node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
d[process.argv[2]]={type:'command',command:process.argv[3]};
fs.writeFileSync(process.argv[4],JSON.stringify(d,null,2)+'\n');
" "$file" "$key" "$value" "$tmp" 2>/dev/null; then
      produced=0
    fi
  fi

  if [[ $produced -ne 0 ]]; then
    rm -f "$tmp"
    return 1
  fi

  # Atomic replace at the resolved target keeps the symlink (if any) intact.
  if ! mv "$tmp" "$real"; then
    rm -f "$tmp"
    return 1
  fi
  return 0
}

cmd_statusline() {
  local action="${1:-}"
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
            if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null && ! command -v node &>/dev/null; then
              err "Could not update settings.json (no jq, python3, or node found)"
            elif ! _json_valid "$settings"; then
              err "Could not update settings.json — it is not valid JSON"
            else
              err "Could not update settings.json — check that its directory is writable"
            fi
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
