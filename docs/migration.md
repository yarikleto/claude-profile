# Migrating from claude-profile to native Claude Code profiles

When Claude Code adds native profile support, follow these steps to migrate without losing any data.

## Quick migration

```bash
# Switch to the profile you want to keep
claude-profile use my-preferred-profile

# Detach — keeps all your files exactly as-is
claude-profile deactivate --keep

# Uninstall
brew uninstall claude-profile    # or: bash uninstall.sh

# Clean up profile data (optional — safe to keep for reference)
rm -rf ~/.local/share/claude-profile
```

After this, your `~/.claude/` will look exactly as if you'd configured it manually — Claude Code (and any native profile system) will see normal config files.

## What `deactivate --keep` does

1. **Saves** your current profile to its directory (so you have a copy)
2. **Clears** the active profile marker (`.current` file)
3. **Does NOT** restore the original backup — your current config stays

> **Your original backup is safe.** Neither `--keep` nor regular `deactivate` ever modifies the backup at `~/.local/share/claude-profile/.pre-profiles-backup/`. It is created once and never touched. You can always restore from it manually, even after migration.

After running it:
- `~/.claude/settings.json` — your current profile's settings (unchanged)
- `~/.claude/CLAUDE.md` — your current profile's instructions (unchanged)
- `~/.claude/projects/` — your current profile's memory (unchanged)
- `~/.claude.json` — your current profile's MCP servers (unchanged)
- `~/.local/share/claude-profile/` — all saved profiles (can be deleted or kept for reference)

## What `deactivate` (without --keep) does

Restores the backup taken when you first ran `fork` or `new`. Use this if you want to go back to your original config from before you started using profiles.

## Accessing old profiles after migration

Even after `deactivate --keep`, all your profiles are saved in `~/.local/share/claude-profile/<name>/`. Each profile directory contains all the files that were part of that profile. You can manually copy files from any profile:

```bash
# See what profiles you had
ls ~/.local/share/claude-profile/

# Copy a specific file from an old profile
cp ~/.local/share/claude-profile/work/CLAUDE.md ~/somewhere/

# View the git history of a profile
git -C ~/.local/share/claude-profile/work log --oneline
```

## Removing the statusline

If you ran `claude-profile statusline install`, also remove:

```bash
rm -f ~/.local/share/claude-profile/statusline.sh
```

And remove the `"statusLine"` entry from `~/.claude/settings.json`, or set up a new one using Claude Code's `/statusline` command.

## Migrating from v0.x (old storage location)

If you are upgrading from v0.x where profiles were stored in `~/.claude/__profiles__/`, the `install.sh` script automatically migrates your profiles to the new XDG-compliant location (`~/.local/share/claude-profile/`).

If you need to migrate manually:

```bash
mv ~/.claude/__profiles__ ~/.local/share/claude-profile
./install.sh
```

## Troubleshooting

**I ran `deactivate` (without --keep) and lost my config:**

Your profile is still saved. Find it and copy the files back:

```bash
ls ~/.local/share/claude-profile/
# Find your profile name, then:
cp ~/.local/share/claude-profile/YOUR_PROFILE/settings.json ~/.claude/settings.json
cp ~/.local/share/claude-profile/YOUR_PROFILE/.claude.json ~/.claude.json
# ... etc for other files you need
```

**I deleted the profiles directory and need my backup:**

If you had a backup, it was at `~/.local/share/claude-profile/.pre-profiles-backup/`. Once deleted, it cannot be recovered. This is why we recommend running `deactivate --keep` first.
