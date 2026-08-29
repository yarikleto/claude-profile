# Configuration

## How it works

Think of it like git branches. Your original `~/.claude/` state is the **main branch** — backed up once and preserved by normal profile operations. Each profile is an independent **fork** you can change freely.

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
├── .pre-profiles-backup/                   # your original state backup
├── default/                                # profile with its own git history
│   ├── .git/
│   ├── settings.json
│   ├── projects/
│   ├── .claude-profile-home.json           # stored copy of ~/.claude.json
│   └── ...
└── code-review/
    ├── .git/
    ├── settings.json
    ├── CLAUDE.md
    └── ...
```

Profiles are stored in `~/.local/share/claude-profile/` (XDG-compliant), separate from `~/.claude/`. Each profile snapshots the **entire** `~/.claude/` directory plus `~/.claude.json`.

Inside a stored profile, the home-level `~/.claude.json` is named
`.claude-profile-home.json`. The reserved name keeps it separate from a payload
file literally named `~/.claude/.claude.json`, which remains `.claude.json` at
the profile root.

## Seed templates

When you run `claude-profile new`, the new profile is seeded with files from `~/.local/share/claude-profile/.seed/`. This directory is created automatically during installation with minimal defaults (empty `settings.json` and `.claude.json`). The seed keeps the familiar `.claude.json` template name; `new` stores that template as `.claude-profile-home.json` inside the profile.

You can customize these templates:

```bash
# Edit the seed settings
vi ~/.local/share/claude-profile/.seed/settings.json

# Add more seed files
cp ~/.claude/CLAUDE.md ~/.local/share/claude-profile/.seed/CLAUDE.md
```

Next time you run `new`, it will use your custom templates.

## Git tracking

Each profile has its own git history for tracking configuration and durable
memory changes. A managed `.gitignore` separates persistent memory from
disposable/session data while all files are still copied between profiles:

- **Git-tracked**: `settings.json`, `CLAUDE.md`, `agents/`, `skills/`, `rules/`, `keybindings.json`, `.claude-profile-home.json`,
  `agent-memory/`, and `projects/*/memory/`.
- **Git-ignored** (still copied): all other content under `projects/` (including
  session transcripts), plus `todos/`, `plans/`, `tasks/`, `plugins/`, and
  `history.jsonl`.

This means `history`, `diff`, and `restore` cover persistent memory as well as
configuration, without filling history with transcripts. Memory can contain
personal preferences and project learnings; because it is versioned, deleting
it from the live profile does not remove older copies from that profile's Git
history. These repositories and Git objects stay local and are not uploaded by
claude-profile, but they are plaintext and protected only by filesystem
permissions.

Existing profiles receive the managed rules automatically. Their first
subsequent save establishes the earliest recoverable memory baseline. Restoring
a commit older than that baseline preserves current memory and prints a warning,
because an absent path in the old commit means it was ignored, not necessarily
that it did not exist.

Rules outside claude-profile's marked managed block are preserved when the
policy is refreshed. The managed block stays last so durable memory cannot be
silently excluded by an older or global Git ignore rule. Save and diff also
enforce the same boundary directly: nested ignore rules cannot hide durable
memory or pull project transcripts into history.

History guarantees apply to the standard `agent-memory/**` and
`projects/*/memory/**` locations. If Claude Code's `autoMemoryDirectory` points
outside the configured Claude directory, that external directory is neither
copied nor versioned. A custom location elsewhere inside the Claude directory
is still snapshotted, but follows the ordinary history policy for that path.

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
