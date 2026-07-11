# Uninstall guide

There are three layers to remove: your Claude Code configuration (profiles data), the CLI binary, and optional UI integrations. Each step is independent — you can do them in any order, but this sequence is the safest.

## Step 1: Restore your original Claude Code configuration

Deactivate to restore your original `~/.claude/` state:

```bash
claude-profile deactivate
```

This saves the active profile, copies your original files back from the backup, and clears the active profile marker.
If you already detached with `deactivate --keep`, the same command restores the original backup; if your detached live config changed, it is first saved as a generated `detached-...` profile.

**If `claude-profile` is no longer installed**, restore manually:

```bash
# Copy everything from the backup — the trailing /. includes dotfiles
# (e.g. .credentials.json), which a bare * glob would skip
mkdir -p ~/.claude
cp -R ~/.local/share/claude-profile/.pre-profiles-backup/. ~/.claude/
# .claude.json lives in $HOME, not inside ~/.claude/
mv -f ~/.claude/.claude.json ~/.claude.json 2>/dev/null || true
rm -f ~/.local/share/claude-profile/.current
```

Not every file will exist — errors about missing ones are fine.

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

Profiles live entirely inside `~/.local/share/claude-profile/`:

```bash
rm -rf ~/.local/share/claude-profile
```

Make sure you completed Step 1 first, or your `~/.claude/` files will be from whichever profile was last active.

## Step 4: Remove optional UI integrations

**Statusline** — if you ran `claude-profile statusline install`:

```bash
rm -f ~/.local/share/claude-profile/statusline.sh
# Also remove the "statusLine" entry from ~/.claude/settings.json
```

## Verify

```bash
which claude-profile                     # should print nothing
ls ~/.local/share/claude-profile         # should say "No such file or directory"
cat ~/.claude/settings.json              # should be your original settings
```

Claude Code itself is completely unaffected.
