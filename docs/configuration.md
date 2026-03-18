# Configuration

## How it works

Think of it like git branches. Your original `~/.claude/` state is the **main branch** — always preserved, never modified. Each profile is an independent **fork** you can change freely.

```
~/.claude/                                  ← "live" location, what Claude Code reads
├── settings.json                           ← from active profile
├── CLAUDE.md                               ← from active profile
├── agents/                                 ← from active profile
├── projects/                               ← from active profile
└── ...

~/.local/share/claude-profile/              ← everything claude-profile owns
├── .current                                # tracks which profile is active
├── .seed/                                  # templates for `new` (user-editable)
├── statusline.sh                           # statusline script
├── .pre-profiles-backup/                   # your original state (read-only)
├── default/                                # profile with its own git history
│   ├── .git/
│   ├── settings.json
│   ├── projects/
│   ├── .claude.json                        # stored copy of ~/.claude.json
│   └── ...
└── code-review/
    ├── .git/
    ├── settings.json
    ├── CLAUDE.md
    └── ...
```

Profiles are stored in `~/.local/share/claude-profile/` (XDG-compliant), separate from `~/.claude/`. Each profile snapshots the **entire** `~/.claude/` directory plus `~/.claude.json`.

## Seed templates

When you run `claude-profile new`, the new profile is seeded with files from `~/.local/share/claude-profile/.seed/`. This directory is created automatically during installation with minimal defaults (empty `settings.json` and `.claude.json`).

You can customize these templates:

```bash
# Edit the seed settings
vi ~/.local/share/claude-profile/.seed/settings.json

# Add more seed files
cp ~/.claude/CLAUDE.md ~/.local/share/claude-profile/.seed/CLAUDE.md
```

Next time you run `new`, it will use your custom templates.

## Git tracking

Each profile has its own git history for tracking configuration changes. A static `.gitignore` excludes large data directories from git while still copying them between profiles:

- **Git-tracked**: `settings.json`, `CLAUDE.md`, `agents/`, `skills/`, `rules/`, `keybindings.json`, `.claude.json`, etc.
- **Git-ignored** (still copied): `projects/`, `agent-memory/`, `todos/`, `plans/`, `tasks/`, `plugins/`, `history.jsonl`

This means `history`, `diff`, and `restore` commands only operate on config files, while all data is still fully isolated between profiles.

## Statusline

The statusline script lives at `~/.local/share/claude-profile/statusline.sh` and is configured automatically during installation. It shows the model name and active profile in Claude Code's status bar.

To reconfigure manually:

```bash
claude-profile statusline install    # install/update
claude-profile statusline uninstall  # remove
```

If you have a custom statusline, `install` won't overwrite it. You can reference the script path in your own statusline configuration.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_CODE_HOME` | `~/.claude` | Claude Code config directory |
| `CLAUDE_PROFILE_HOME` | *(see below)* | Override profiles storage location |
| `XDG_DATA_HOME` | `~/.local/share` | XDG data directory (profiles stored in `$XDG_DATA_HOME/claude-profile`) |
| `CLAUDE_PROFILE_INSTALL_DIR` | `~/.local/bin` | Install location for the binary |
| `CLAUDE_PROFILE_COMPLETIONS_DIR` | *(auto-detect)* | Custom completions directory |

### Storage location resolution

Priority: `CLAUDE_PROFILE_HOME` > `XDG_DATA_HOME/claude-profile` > `$HOME/.local/share/claude-profile`
