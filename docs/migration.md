# Migrating from claude-profile to native Claude Code profiles

When Claude Code adds native profile support, follow these steps to migrate without losing any data.

Run commands with the same `CLAUDE_CONFIG_DIR` and `CLAUDE_PROFILE_HOME` used
for your profiles. Paths elsewhere in this guide show the defaults; custom
directories keep their account JSON at `$CLAUDE_CONFIG_DIR/.claude.json`.

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

> **Your original backup is preserved by normal profile operations.** It lives at `$CLAUDE_PROFILE_HOME/.pre-profiles-backup/` when `CLAUDE_PROFILE_HOME` is set, otherwise `$XDG_DATA_HOME/claude-profile/.pre-profiles-backup/` when `XDG_DATA_HOME` is set, otherwise `~/.local/share/claude-profile/.pre-profiles-backup/`. You can restore from it while that directory still exists and is readable.

After running it:
- `~/.claude/settings.json` — your current profile's settings (unchanged)
- `~/.claude/CLAUDE.md` — your current profile's instructions (unchanged)
- `~/.claude/projects/` — your current profile's session history and auto memory (unchanged)
- `~/.claude.json` — your current profile's MCP servers, signed-in account, per-project trust decisions, and `/config` keys (unchanged)
- `~/.local/share/claude-profile/` — all saved profiles (can be deleted or kept for reference)

## If you change your mind

While detached, nothing auto-saves your live config into the profile you detached from.

To go back to the original pre-profiles config:

```bash
claude-profile deactivate
```

If your detached live config changed, `deactivate` saves it first as a generated `detached-...` profile, then restores the original backup.

To re-attach the current live config as a named profile or switch to a saved profile:

```bash
# Keep what you have now — save it as a new profile (this re-attaches you)
claude-profile fork back-from-native

# Or switch anyway, discarding what changed while detached
claude-profile use work --force
```

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

Your profile is still saved. Reattach it with `claude-profile use <name>` using
the same config and store variables, or follow the selected-file recovery below.

## Manual file recovery

Close Claude Code and detach from profiles before changing live files manually.
Select the store and live directory you intend to recover. Replace `YOUR_PROFILE`
below with a saved profile name, or `.pre-profiles-backup` for the original
backup. The snippet preserves the current live files and recovers settings plus
the managed account JSON. The recovery copy stays in a private directory under
your home directory until you remove it; keep it until you verify the recovered
configuration. It does not remove extra live files or restore session
history; reinstall the CLI and use `deactivate` for an exact backup restore.

If either JSON file belongs to a different account, follow
[the JSON migration steps](configuration.md#migrating-stores-with-two-json-files)
to prepare a copy first. Do not choose an account solely from its filename.

<!-- BEGIN manual-file-recovery -->
```bash
(
  set -e
  umask 077
  profile_store="${CLAUDE_PROFILE_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile}"
  live_dir="${CLAUDE_CODE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
  live_json="$HOME/.claude.json"
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    live_json="$live_dir/.claude.json"
  fi
  saved_dir="$profile_store/YOUR_PROFILE"
  test -d "$saved_dir"
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" && -e "$saved_dir/.claude.json" ]]; then
    echo 'Choose the intended account JSON using the migration steps before recovering files.' >&2
    exit 1
  fi
  recovery_dir="$(mktemp -d "$HOME/claude-profile-recovery.XXXXXX")"
  if [[ -d "$live_dir" ]]; then
    cp -RL "$live_dir" "$recovery_dir/live"
  fi
  if [[ -f "$live_json" ]]; then
    cp -Lp "$live_json" "$recovery_dir/account.json"
  fi
  printf 'Current files preserved in %s\n' "$recovery_dir"
  mkdir -p "$live_dir"
  if [[ -f "$saved_dir/settings.json" ]]; then
    cp -p "$saved_dir/settings.json" "$live_dir/settings.json"
  fi
  if [[ -f "$saved_dir/.claude-profile-home.json" ]]; then
    cp -p "$saved_dir/.claude-profile-home.json" "$live_json"
  else
    echo 'No managed account JSON in this snapshot; the live JSON was left unchanged.'
  fi
)
```
<!-- END manual-file-recovery -->

An unmigrated store created before format 2 may instead keep the home-level
file at `YOUR_PROFILE/.claude.json`. Use that legacy path only when
`.claude-profile-home.json` is absent and you know the store predates format 2.
With default paths in a current store, the root `.claude.json` can be the
distinct payload file that belongs at `~/.claude/.claude.json`. Older relocated
stores can instead have their real account JSON there; use the explicit JSON
migration steps above to preserve both sources and select the correct one.

**I deleted the profiles directory and need my backup:**

If you had a backup, it was at `~/.local/share/claude-profile/.pre-profiles-backup/`. Once deleted, it cannot be recovered. This is why we recommend running `deactivate --keep` first.
