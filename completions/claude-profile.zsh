#compdef claude-profile

_claude-profile() {
  local -a commands
  commands=(
    'new:Create a clean empty profile'
    'fork:Copy current state into a new profile'
    'use:Switch to a profile'
    'list:List all profiles'
    'current:Show active profile'
    'save:Save & commit current state'
    'show:Show profile contents'
    'edit:Open profile in editor'
    'delete:Delete a profile'
    'deactivate:Turn off profiles'
    'history:View change history'
    'diff:Show changes'
    'restore:Restore to a point in time'
    'statusline:Claude Code status line'
    'version:Print version'
    'help:Show help'
  )

  _claude_profile_profiles() {
    # Resolve profiles dir: CLAUDE_PROFILE_HOME > XDG_DATA_HOME > default
    local profiles_dir
    if [[ -n "${CLAUDE_PROFILE_HOME:-}" ]]; then
      profiles_dir="$CLAUDE_PROFILE_HOME"
    elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
      profiles_dir="$XDG_DATA_HOME/claude-profile"
    else
      profiles_dir="$HOME/.local/share/claude-profile"
    fi
    local -a profiles
    if [[ -d "$profiles_dir" ]]; then
      profiles=("${(@f)$(find "$profiles_dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -exec basename {} \;)}")
    fi
    _describe 'profile' profiles
  }

  if (( CURRENT == 2 )); then
    _describe 'command' commands
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      use|switch)
        local -a flags=('--force:Discard unsaved detached config')
        _describe 'option' flags
        _claude_profile_profiles
        ;;
      edit|show|info|delete|rm|save|history|log|diff|restore)
        _claude_profile_profiles
        ;;
      new)
        local -a flags=('--force:Discard unsaved detached config')
        _describe 'option' flags
        _message 'profile name'
        ;;
      fork)
        _message 'profile name'
        ;;
      deactivate|off)
        local -a flags=(
          '--keep:Detach without restoring backup'
        )
        _describe 'option' flags
        ;;
      statusline)
        local -a actions=('install:Install status line script' 'uninstall:Remove status line script')
        _describe 'action' actions
        ;;
    esac
  elif (( CURRENT >= 4 )); then
    case "${words[2]}" in
      use|switch)
        # --force may precede the name — keep offering profiles
        _claude_profile_profiles
        ;;
    esac
  fi
}

_claude-profile "$@"
