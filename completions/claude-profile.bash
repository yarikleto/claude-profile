_claude_profile_completions() {
  local cur prev commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="new fork use list current save show edit delete deactivate history diff restore statusline version help"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi

  # Resolve profiles dir: CLAUDE_PROFILE_HOME > XDG_DATA_HOME > default
  local profiles_dir
  if [[ -n "${CLAUDE_PROFILE_HOME:-}" ]]; then
    profiles_dir="$CLAUDE_PROFILE_HOME"
  elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    profiles_dir="$XDG_DATA_HOME/claude-profile"
  else
    profiles_dir="$HOME/.local/share/claude-profile"
  fi
  local profiles=""
  if [[ -d "$profiles_dir" ]]; then
    profiles="$(find "$profiles_dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} \; 2>/dev/null)"
  fi

  case "${COMP_WORDS[1]}" in
    use|switch|edit|show|info|delete|rm|save|history|log|diff|restore)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
      fi
      ;;
    new|fork)
      COMPREPLY=()  # free-form name
      ;;
    statusline)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "install uninstall" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _claude_profile_completions claude-profile
