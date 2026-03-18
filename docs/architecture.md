# Architecture

## Overview

`claude-profile` is a bash CLI tool that switches between independent copies of Claude Code's configuration. It works by copying the entire `~/.claude/` directory in and out of profile directories — no symlinks, no daemons, no background processes.

```
User runs            claude-profile use review
                            │
                            ▼
                ┌───────────────────────┐
                │  Save current profile │  ← auto-save before switch
                │  (full directory)     │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │  Load new profile     │  ← restore from profile dir
                │  (full directory)     │
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
  config.sh                 # Constants, XDG path resolution, SEED defaults
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

Profiles are stored in an XDG-compliant location, separate from `~/.claude/`:

```
~/.claude/                                  ← "live" location, what Claude Code reads
├── settings.json                           ← from active profile
├── CLAUDE.md                               ← from active profile
├── agents/                                 ← from active profile
├── projects/                               ← from active profile
├── plugins/                                ← from active profile
├── history.jsonl                           ← from active profile
└── ...

~/.local/share/claude-profile/              ← everything claude-profile owns
├── .current                                # one line: name of active profile
├── .seed/                                  # templates for `new` (user-editable)
│   ├── settings.json
│   └── .claude.json
├── .pre-profiles-backup/                   # original state, NEVER modified
│   ├── settings.json
│   ├── CLAUDE.md
│   ├── projects/
│   └── ...
├── statusline.sh                           # statusline script for Claude Code
├── default/                                # a profile
│   ├── .git/                               #   version history
│   ├── .gitignore                          #   excludes large data dirs
│   ├── settings.json
│   ├── CLAUDE.md
│   ├── agents/
│   ├── projects/
│   ├── plugins/
│   ├── history.jsonl
│   ├── .claude.json                        #   stored copy of ~/.claude.json
│   └── ...
└── code-review/                            # another profile
    └── ...
```

### Storage location resolution

Priority: `CLAUDE_PROFILE_HOME` > `XDG_DATA_HOME/claude-profile` > `$HOME/.local/share/claude-profile`

The `~/.claude.json` file (MCP server config) lives in `$HOME`, not inside `~/.claude/`. It is stored as `.claude.json` inside each profile directory and copied to/from `$HOME/.claude.json` on switch.

## Full-directory snapshots

Profiles snapshot the **entire** `~/.claude/` directory. There is no distinction between "managed items" and "bulk items" — everything is captured. A static `.gitignore` excludes large data dirs from git tracking while still copying/moving them.

Git-tracked (small config):
- Everything not in `.gitignore`

Git-ignored (large data, still copied/moved):
- `projects/`, `agent-memory/`, `todos/`, `plans/`, `tasks/`, `plugins/`, `history.jsonl`

## Command flows

### `fork <name>`

Creates a new profile from the current live state.

```
1. _ensure_original_backup()     ← one-time backup + seed creation
2. Auto-save current profile     ← if one is active (cp)
3. mkdir profile dir
4. _snapshot_current()           ← cp entire ~/.claude/ + ~/.claude.json to profile
5. _git_init()                   ← init git with static .gitignore
6. set_current()
```

### `new <name>`

Creates a clean empty profile.

```
1. _ensure_original_backup()
2. Auto-save current profile     ← --move (since we're switching away)
3. mkdir profile dir
4. _seed_profile()               ← copy from .seed/ or built-in defaults
5. _git_init()
6. _load_profile_to_live()       ← cp from profile to live
7. set_current()
```

### `use <name>` (switch)

The core operation. Uses `--move` for speed.

```
1. _validate_profile_for_load(target)   ← pre-check before destructive ops
2. _save_current_to(current, --move)
   ├── mv all items: ~/.claude/ → current profile dir
   ├── cp ~/.claude.json → current profile dir
   └── git commit
3. _load_profile_to_live(new, --move)
   ├── clear ~/.claude/
   ├── mv items: new profile dir → ~/.claude/
   ├── cp .claude.json → ~/.claude.json
4. set_current(new)
```

### `save [-m msg]`

Explicit save. Uses `cp` (user continues working).

```
1. _save_current_to(current)
   ├── cp all items: ~/.claude/ → profile dir
   ├── cp ~/.claude.json → profile dir
   └── git commit
```

### `deactivate`

Restores original state from backup.

```
1. Verify backup exists
2. _save_current_to(current, --move)    ← save profile one last time
3. _restore_from_backup()               ← cp from .pre-profiles-backup to live
4. clear_current()
```

### `deactivate --keep`

Detaches without restoring backup. Migration path for native profiles.

```
1. _save_current_to(current)    ← save (cp) to profile dir
2. clear_current()
```

After this: live files are untouched, `.current` is gone. Claude Code sees normal config.

## Key modules

### `lib/config.sh`

Defines constants and path resolution:

- `PROFILES_DIR` — resolved via `CLAUDE_PROFILE_HOME` > `XDG_DATA_HOME` > default
- `CLAUDE_DIR` — `${CLAUDE_CODE_HOME:-$HOME/.claude}`
- `SEED_NAMES` / `SEED_CONTENTS` — fallback seed templates
- `GITIGNORE_CONTENT` — static gitignore for large data dirs

### `lib/files.sh`

All file operations. **Commands never copy/move files directly.**

| Function | Used by | Behavior |
|----------|---------|----------|
| `_seed_profile` | `new` | Copy .seed/ or defaults to profile |
| `_snapshot_current` | `fork`, backup | cp ~/.claude/ + ~/.claude.json to dst |
| `_save_current_to` | `use`, `save`, `deactivate` | cp/mv ~/.claude/ to dst + git commit |
| `_validate_profile_for_load` | `use` | Pre-check safety before destructive ops |
| `_load_profile_to_live` | `use`, `new`, `restore` | cp/mv profile to ~/.claude/ |
| `_restore_from_backup` | `deactivate` | Load from .pre-profiles-backup |
| `_show_summary` | `fork`, `use` | Display profile contents |

### `lib/state.sh`

Profile state management:

- `get_current` / `set_current` / `clear_current` — read/write `.current` file
- `_ensure_original_backup` — one-time backup + seed dir creation
- `_validate_profile_name` — prevents path traversal, flag injection

### `lib/git.sh`

Git operations for version history:

- `_git_init` — init repo, write static `.gitignore`, initial commit
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

Statusline integration. Creates `statusline.sh` which reads JSON from stdin (Claude Code provides session data) and outputs model name + active profile. Uses the same 3-tier path resolution to find `.current`.

## Safety design

### Original backup

Created once by `_backup_raw_state()` on first `fork` or `new`. Never modified after creation. Contains the full snapshot of `~/.claude/` + `~/.claude.json`. This is the "factory reset" — `deactivate` restores from here.

### Auto-save before switch

Every operation that changes the active profile (`use`, `new`, `deactivate`) saves the current profile first. The user never loses unsaved changes.

### Pre-validation before destructive switch

`cmd_use` calls `_validate_profile_for_load` BEFORE saving the current profile. This ensures that if the target profile has issues (unreadable dirs, symlinks), the switch is aborted before any files are moved.

### Symlink protection

- `_load_profile_to_live` skips symlinks in profile dirs (`! -L` check)
- `_validate_profile_for_load` rejects nested symlinks inside directories
- `_snapshot_current` follows symlinks at the source (user's live files are trusted) via `cp -RH`
- Profile name validation rejects `..`, `/`, leading `.` or `-`

## Testing

All tests use [bats-core](https://github.com/bats-core/bats-core) with full filesystem isolation. Each test gets its own `$HOME` in a temp directory — the real `~/.claude/` is never touched.

Test files map to source structure:

| Test file | Tests for |
|-----------|-----------|
| `bulk.bats` | Large data dir isolation (projects, plugins, history, etc.) |
| `fork.bats` | `fork` command |
| `new.bats` | `new` command + seed templates |
| `use.bats` | `use` (switch) command |
| `save.bats` | `save` command |
| `deactivate.bats` | `deactivate` + `--keep` |
| `history.bats` | `history`, `diff`, `restore` |
| `isolation.bats` | Cross-cutting isolation guarantees |
| `security.bats` | Path traversal, symlink attacks |
| `data_safety.bats` | Data integrity through operations |
| `install.bats` | `install.sh` |
| `uninstall.bats` | `uninstall.sh` |

## Releasing

1. Update `VERSION` in `lib/config.sh`
2. Commit
3. `git tag vX.Y.Z`
4. `git push origin main --tags`
5. Update homebrew formula SHA in `yarikleto/homebrew-claude-profile`

The VERSION variable and git tag must always match.
