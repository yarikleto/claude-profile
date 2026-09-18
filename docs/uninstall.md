# Uninstall guide

There are three layers to remove: your Claude Code configuration (profiles data), the CLI binary, and optional UI integrations. Each step is independent — you can do them in any order, but this sequence is the safest.

## Step 1: Restore your original Claude Code configuration

Run this with the same `CLAUDE_CONFIG_DIR` and `CLAUDE_PROFILE_HOME` used for
the profiles to restore the original configuration:

```bash
claude-profile deactivate
```

This saves the active profile, copies your original files back from the backup, and clears the active profile marker.
If you already detached with `deactivate --keep`, the same command restores the original backup; if your detached live config changed, it is first saved as a generated `detached-...` profile.

**If `claude-profile` is no longer installed**, reinstall it and run `deactivate`
for an exact restore. For selected-file recovery, follow
[manual file recovery](migration.md#manual-file-recovery), using
`.pre-profiles-backup` as the saved directory. Those steps resolve both live
paths and preserve the current files before copying. A custom directory's
account JSON belongs inside that directory; leave any unrelated
`$HOME/.claude.json` alone.

Older backups with a payload `.claude.json` need
[explicit JSON selection in a copy](configuration.md#migrating-stores-with-two-json-files).

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

The default store is `~/.local/share/claude-profile/`. If you used
`CLAUDE_PROFILE_HOME` or `XDG_DATA_HOME`, remove only that selected store after
recovery; the following example is for the default store:

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
