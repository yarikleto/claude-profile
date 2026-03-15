_claude_profile_completions() {
  local cur prev commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="new fork use list current save show edit delete deactivate history diff restore prompt-init statusline version help"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return
  fi

  local profiles_dir="${CLAUDE_CODE_HOME:-$HOME/.claude}/profiles"
  local profiles=""
  if [[ -d "$profiles_dir" ]]; then
    profiles="$(find "$profiles_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null)"
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
    prompt-init)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "zsh bash plain" -- "$cur"))
      fi
      ;;
    statusline)
      if [[ ${COMP_CWORD} -eq 2 ]]; then
        COMPREPLY=($(compgen -W "install uninstall" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _claude_profile_completions claude-profile
