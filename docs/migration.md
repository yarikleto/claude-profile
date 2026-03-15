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
rm -rf ~/.claude/__profiles__
```

After this, your `~/.claude/` will look exactly as if you'd configured it manually — Claude Code (and any native profile system) will see normal config files.

## What `deactivate --keep` does

1. **Saves** your current profile to its directory (so you have a copy)
2. **Moves** bulk data (projects, memory, etc.) back to the live location
3. **Clears** the active profile marker (`.current` file)
4. **Does NOT** restore the original backup — your current config stays

> **Your original backup is safe.** Neither `--keep` nor regular `deactivate` ever modifies the backup at `~/.claude/__profiles__/.pre-profiles-backup/`. It is created once and never touched. You can always restore from it manually, even after migration.

After running it:
- `~/.claude/settings.json` — your current profile's settings (unchanged)
- `~/.claude/CLAUDE.md` — your current profile's instructions (unchanged)
- `~/.claude/projects/` — your current profile's memory (unchanged)
- `~/.claude.json` — your current profile's MCP servers (unchanged)
- `~/.claude/__profiles__/` — all saved profiles (can be deleted or kept for reference)

## What `deactivate` (without --keep) does

Restores the backup taken when you first ran `fork` or `new`. Use this if you want to go back to your original config from before you started using profiles.

## Accessing old profiles after migration

Even after `deactivate --keep`, all your profiles are saved in `~/.claude/__profiles__/<name>/`. Each profile directory contains all the files that were part of that profile. You can manually copy files from any profile:

```bash
# See what profiles you had
ls ~/.claude/__profiles__/

# Copy a specific file from an old profile
cp ~/.claude/__profiles__/work/CLAUDE.md ~/somewhere/

# View the git history of a profile
git -C ~/.claude/__profiles__/work log --oneline
```

## Removing the statusline

If you ran `claude-profile statusline install`, also remove:

```bash
rm -f ~/.claude/statusline-profile.sh
```

And remove the `"statusLine"` entry from `~/.claude/settings.json`, or set up a new one using Claude Code's `/statusline` command.

## Troubleshooting

**I ran `deactivate` (without --keep) and lost my config:**

Your profile is still saved. Find it and copy the files back:

```bash
ls ~/.claude/__profiles__/
# Find your profile name, then:
cp ~/.claude/__profiles__/YOUR_PROFILE/settings.json ~/.claude/settings.json
cp ~/.claude/__profiles__/YOUR_PROFILE/.claude.json ~/.claude.json
# ... etc for other files you need
```

**I deleted `__profiles__/` and need my backup:**

If you had a backup, it was at `~/.claude/__profiles__/.pre-profiles-backup/`. Once deleted, it cannot be recovered. This is why we recommend running `deactivate --keep` first.
