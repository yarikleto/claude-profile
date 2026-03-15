# Architecture

## Overview

`claude-profile` is a bash CLI tool that switches between independent copies of Claude Code's configuration. It works by copying files in and out of `~/.claude/` — no symlinks, no daemons, no background processes.

```
User runs            claude-profile use review
                            │
                            ▼
                ┌───────────────────────┐
                │  Save current profile │  ← auto-save before switch
                │  (tracked: cp, bulk: mv)
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │  Load new profile     │  ← restore from profile dir
                │  (tracked: cp, bulk: mv)
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │  Update .current      │
                └───────────────────────┘
```

## Source layout

```
claude-profile              # Entrypoint: sources modules, dispatches commands
lib/
  config.sh                 # Constants, MANAGED_ITEMS, BULK_ITEMS, SEED defaults
  output.sh                 # Colors, info/ok/warn/err helpers
  state.sh                  # get_current, set_current, backup, validation, seed
  files.sh                  # All file operations between profiles and live paths
  git.sh                    # Git history: init, commit, resolve ref
commands/
  profile.sh                # new, fork, use, save, deactivate
  info.sh                   # list, current, show, edit, delete
  history.sh                # history, diff, restore
  ui.sh                     # statusline install/uninstall
tests/
  test_helper.bash          # Shared setup: isolated $HOME, run_cli helpers
  *.bats                    # One test file per command + isolation + security
completions/
  claude-profile.zsh        # Zsh tab completions
  claude-profile.bash       # Bash tab completions
install.sh                  # Install binary, modules, completions, seed, statusline
uninstall.sh                # Remove binary, modules, completions
```

## Disk layout

Everything the tool creates lives inside `~/.claude/__profiles__/`. The name uses double underscores to avoid conflicts with a future native profiles feature in Claude Code.

```
~/.claude/                          ← "live" location, what Claude Code reads
├── settings.json                   ← copied from active profile
├── CLAUDE.md                       ← copied from active profile
├── agents/                         ← copied from active profile
├── projects/                       ← moved from active profile
├── plugins/                        ← moved from active profile
├── history.jsonl                   ← moved from active profile
└── __profiles__/                   ← everything claude-profile owns
    ├── .current                    # one line: name of active profile
    ├── .seed/                      # templates for `new` (user-editable)
    │   ├── settings.json           #   minimal settings with statusline
    │   └── .claude.json            #   empty {}
    ├── .managed                    # custom managed items (optional)
    ├── .pre-profiles-backup/       # original state, NEVER modified
    │   ├── settings.json
    │   ├── CLAUDE.md
    │   ├── projects/
    │   └── ...
    ├── statusline.sh               # statusline script for Claude Code
    ├── default/                    # a profile
    │   ├── .git/                   #   version history (tracked items only)
    │   ├── .gitignore              #   excludes bulk items
    │   ├── settings.json           #   tracked: copied on switch
    │   ├── CLAUDE.md
    │   ├── agents/
    │   ├── projects/               #   bulk: moved on switch
    │   ├── plugins/
    │   ├── history.jsonl
    │   └── ...
    └── code-review/                # another profile
        └── ...
```

## Two types of managed items

The tool distinguishes between small config files and large data directories:

### Tracked items (`MANAGED_ITEMS`)

Small configuration files. Defined in `lib/config.sh`.

| Item | Live path | Notes |
|------|-----------|-------|
| `settings.json` | `~/.claude/settings.json` | |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | |
| `agents/` | `~/.claude/agents/` | |
| `skills/` | `~/.claude/skills/` | |
| `rules/` | `~/.claude/rules/` | |
| `keybindings.json` | `~/.claude/keybindings.json` | |
| `.claude.json` | `~/.claude.json` | Uses `name:path` format (lives outside `~/.claude/`) |

Behavior:
- **Copied** (`cp`) on every operation (switch, fork, save)
- **Tracked by git** — each profile has its own `.git/` with commit history
- Users can override the list via `__profiles__/.managed`

### Bulk items (`BULK_ITEMS`)

Large data directories and files. Defined in `lib/config.sh`.

| Item | Live path |
|------|-----------|
| `projects/` | `~/.claude/projects/` |
| `agent-memory/` | `~/.claude/agent-memory/` |
| `todos/` | `~/.claude/todos/` |
| `plans/` | `~/.claude/plans/` |
| `tasks/` | `~/.claude/tasks/` |
| `plugins/` | `~/.claude/plugins/` |
| `history.jsonl` | `~/.claude/history.jsonl` |

Behavior:
- **Moved** (`mv`) during switch — instant even for hundreds of MB
- **Copied** (`cp`) during fork and explicit save — preserves live data
- **Not tracked by git** — excluded via `.gitignore` in each profile
- Not user-configurable (hardcoded in `_DEFAULT_BULK_ITEMS`)

### What is NOT managed

These are infrastructure/cache files that are shared across all profiles:

| Path | Why not managed |
|------|-----------------|
| `cache/` | Transient cache |
| `debug/` | Debug logs |
| `downloads/` | Downloads |
| `file-history/` | File edit tracking |
| `ide/` | IDE integration state |
| `image-cache/`, `paste-cache/` | Caches |
| `session-env/`, `sessions/` | Ephemeral session state |
| `shell-snapshots/` | Shell state |
| `stats-cache.json`, `statsig/` | Stats and feature flags |
| `telemetry/` | Telemetry |
| `backups/` | Claude Code's own backups |
| `policy-limits.json` | Rate limits |

## Command flows

### `fork <name>`

Creates a new profile from the current live state.

```
1. _ensure_original_backup()     ← one-time backup + seed creation
2. Auto-save current profile     ← if one is active (cp tracked, cp bulk)
3. mkdir profile dir
4. _snapshot_current()           ← cp all tracked + bulk from live to profile
5. _git_init()                   ← init git, create .gitignore for bulk items
6. set_current()
```

### `new <name>`

Creates a clean empty profile.

```
1. _ensure_original_backup()
2. Auto-save current profile     ← --move-bulk (since we're switching away)
3. mkdir profile dir
4. _seed_profile()               ← copy from .seed/ or built-in defaults
5. _git_init()
6. _load_profile_to_live()       ← --move-bulk (empty profile, nothing to move)
7. set_current()
```

### `use <name>` (switch)

The core operation. Uses `mv` for bulk items for speed.

```
1. _save_current_to(current, --move-bulk)
   ├── cp tracked items: live → current profile dir
   ├── mv bulk items: live → current profile dir      ← instant
   └── git commit tracked changes
2. _load_profile_to_live(new, --move-bulk)
   ├── rm live tracked items
   ├── cp tracked items: new profile dir → live
   ├── mv bulk items: new profile dir → live           ← instant
3. set_current(new)
```

### `save [-m msg]`

Explicit save. Uses `cp` for bulk (user continues working).

```
1. _save_current_to(current)
   ├── cp tracked items: live → profile dir
   ├── cp bulk items: live → profile dir
   └── git commit
```

### `deactivate`

Restores original state from backup.

```
1. _save_current_to(current, --move-bulk)    ← save profile one last time
2. _restore_from_backup()                     ← cp from .pre-profiles-backup to live
3. clear_current()
```

### `deactivate --keep`

Detaches without restoring backup. Migration path for native profiles.

```
1. _save_current_to(current, --move-bulk)    ← save + move bulk to profile dir
2. _load_bulk_from_profile(current)          ← mv bulk back to live
3. clear_current()
```

After this: tracked items are live (untouched), bulk items are live (moved back), `.current` is gone. Claude Code sees normal config.

## Key modules

### `lib/config.sh`

Defines all constants and arrays:

- `PROFILES_DIR` — `~/.claude/__profiles__`
- `MANAGED_ITEMS` — tracked config files (loaded from `.managed` or defaults)
- `BULK_ITEMS` — large data dirs (hardcoded)
- `SEED_NAMES` / `SEED_CONTENTS` — fallback seed templates
- `_item_source()` / `_item_name()` — resolve `name:path` format

### `lib/files.sh`

All file operations. **Commands never copy/move files directly.**

| Function | Used by | Tracked | Bulk |
|----------|---------|---------|------|
| `_seed_profile` | `new` | n/a | n/a |
| `_snapshot_current` | `fork` | cp | cp |
| `_save_current_to` | `use`, `save`, `deactivate` | cp + git | cp or mv |
| `_load_profile_to_live` | `use`, `new` | cp | cp or mv |
| `_load_bulk_from_profile` | `deactivate --keep` | n/a | mv |
| `_restore_from_backup` | `deactivate` | cp | cp |
| `_show_summary` | `fork`, `use` | display | display |

### `lib/state.sh`

Profile state management:

- `get_current` / `set_current` / `clear_current` — read/write `.current` file
- `_ensure_original_backup` — one-time backup + seed dir creation
- `_validate_profile_name` — prevents path traversal, flag injection

### `lib/git.sh`

Git operations for version history:

- `_git_init` — init repo, create `.gitignore` (excludes bulk items), initial commit
- `_git_commit` — stage all + commit (no-op if nothing changed)
- `_git_resolve_ref` — resolve commit hash or date string to a commit

### `commands/profile.sh`

Core operations: `new`, `fork`, `use`, `save`, `deactivate`. All follow the same pattern:
1. Validate input
2. Ensure backup exists
3. Auto-save current profile if needed
4. Perform the operation
5. Update `.current`

### `commands/ui.sh`

Statusline integration. Creates `__profiles__/statusline.sh` which reads JSON from stdin (Claude Code provides session data) and outputs model name + active profile.

## Safety design

### Original backup

Created once by `_backup_raw_state()` on first `fork` or `new`. Never modified after creation. Contains both tracked and bulk items. This is the "factory reset" — `deactivate` restores from here.

### Auto-save before switch

Every operation that changes the active profile (`use`, `new`, `deactivate`) saves the current profile first. The user never loses unsaved changes.

### Symlink protection

- `_load_profile_to_live` skips symlinks in profile dirs (`! -L` check)
- `_snapshot_current` follows symlinks at the source (user's live files are trusted) via `cp -RH`
- Profile name validation rejects `..`, `/`, leading `.` or `-`

### Path validation

- Profile names are validated against path traversal (`../`, `/`, leading dots)
- Custom `.managed` entries are validated to be under `$HOME`
- Items with `..` in the path are rejected

## Testing

All tests use [bats-core](https://github.com/bats-core/bats-core) with full filesystem isolation. Each test gets its own `$HOME` in a temp directory — the real `~/.claude/` is never touched.

Test files map to source structure:

| Test file | Tests for |
|-----------|-----------|
| `bulk.bats` | Bulk item isolation (projects, plugins, history, etc.) |
| `fork.bats` | `fork` command |
| `new.bats` | `new` command + seed templates |
| `use.bats` | `use` (switch) command |
| `save.bats` | `save` command |
| `deactivate.bats` | `deactivate` + `--keep` |
| `history.bats` | `history`, `diff`, `restore` |
| `isolation.bats` | Cross-cutting isolation guarantees |
| `security.bats` | Path traversal, symlink attacks, `.managed` validation |
| `install.bats` | `install.sh` |
| `uninstall.bats` | `uninstall.sh` |

## Releasing

1. Update `VERSION` in `lib/config.sh`
2. Commit
3. `git tag vX.Y.Z`
4. `git push origin main --tags`
5. Update homebrew formula SHA in `yarikleto/homebrew-claude-profile`

The VERSION variable and git tag must always match.
