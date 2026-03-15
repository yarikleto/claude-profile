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
    local profiles_dir="${CLAUDE_CODE_HOME:-$HOME/.claude}/profiles"
    local -a profiles
    if [[ -d "$profiles_dir" ]]; then
      profiles=("${(@f)$(find "$profiles_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)}")
    fi
    _describe 'profile' profiles
  }

  if (( CURRENT == 2 )); then
    _describe 'command' commands
  elif (( CURRENT == 3 )); then
    case "${words[2]}" in
      use|switch|edit|show|info|delete|rm|save|history|log|diff|restore)
        _claude_profile_profiles
        ;;
      new|fork)
        _message 'profile name'
        ;;
      statusline)
        local -a actions=('install:Install status line script' 'uninstall:Remove status line script')
        _describe 'action' actions
        ;;
    esac
  elif (( CURRENT >= 4 )); then
    case "${words[2]}" in
      # no further completions needed for new/fork
    esac
  fi
}

_claude-profile "$@"
