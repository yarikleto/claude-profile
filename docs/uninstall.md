# Uninstall guide

There are three layers to remove: your Claude Code configuration (profiles data), the CLI binary, and optional UI integrations. Each step is independent — you can do them in any order, but this sequence is the safest.

## Step 1: Restore your original Claude Code configuration

If you have an active profile, deactivate it to restore your original `~/.claude/` state:

```bash
claude-profile deactivate
```

This saves the active profile, copies your original files back from the backup, and clears the active profile marker.

**If `claude-profile` is no longer installed**, restore manually:

```bash
cp -R ~/.claude/__profiles__/.pre-profiles-backup/settings.json ~/.claude/settings.json
cp -R ~/.claude/__profiles__/.pre-profiles-backup/CLAUDE.md ~/.claude/CLAUDE.md
cp -R ~/.claude/__profiles__/.pre-profiles-backup/skills ~/.claude/skills
cp -R ~/.claude/__profiles__/.pre-profiles-backup/agents ~/.claude/agents
cp -R ~/.claude/__profiles__/.pre-profiles-backup/rules ~/.claude/rules
cp -R ~/.claude/__profiles__/.pre-profiles-backup/keybindings.json ~/.claude/keybindings.json
cp -R ~/.claude/__profiles__/.pre-profiles-backup/.claude.json ~/.claude.json
rm -f ~/.claude/__profiles__/.current
```

Not every file will exist — `cp` will print errors for missing ones, which is fine.

## Step 2: Remove the CLI

**Homebrew:**

```bash
brew uninstall claude-profile
brew untap yarikleto/claude-profile   # optional, removes the tap
```

**From source:**

```bash
bash uninstall.sh
```

**Manual removal:**

```bash
rm -f ~/.local/bin/claude-profile
rm -rf ~/.local/bin/claude-profile-lib
rm -f ~/.oh-my-zsh/custom/completions/_claude-profile
rm -f ~/.local/share/zsh/site-functions/_claude-profile
rm -f ~/.local/share/bash-completion/completions/claude-profile
rm -f ~/.zcompdump*
```

If you installed to a custom location:

```bash
CLAUDE_PROFILE_INSTALL_DIR=~/bin bash uninstall.sh
```

## Step 3: Remove profile data

Profiles live entirely inside `~/.claude/__profiles__/`. This directory is not used by Claude Code itself:

```bash
rm -rf ~/.claude/__profiles__
```

Make sure you completed Step 1 first, or your `~/.claude/` files will be from whichever profile was last active.

## Step 4: Remove optional UI integrations

**Statusline** — if you ran `claude-profile statusline install`:

```bash
rm -f ~/.claude/__profiles__/statusline.sh
# Also remove the "statusLine" entry from ~/.claude/settings.json
```

## Verify

```bash
which claude-profile              # should print nothing
ls ~/.claude/__profiles__             # should say "No such file or directory"
cat ~/.claude/settings.json       # should be your original settings
```

Claude Code itself is completely unaffected.
