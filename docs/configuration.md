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

## What a profile covers

A profile holds your **user-level** configuration. Claude Code reads four other
places that no profile contains or swaps.

| Lives in the repository | What it carries |
| --- | --- |
| `.claude/settings.json` | Settings shared with the team |
| `.claude/settings.local.json` | Your own settings for that repo — where **Yes, and don't ask again** saves an allow rule |
| `.mcp.json` | Project-scoped MCP servers |
| `CLAUDE.md`, `.claude/agents/`, `.claude/skills/` | Project instructions, agents, and skills |

Managed settings are the fifth: a `managed-settings.json` file, an MDM policy,
or server-managed settings from the claude.ai console, deployed by your
organization and outranking everything below.

How they combine with the profile, per Claude Code's
[settings precedence](https://code.claude.com/docs/en/settings#settings-precedence):

- **Permission rules from every file merge into one set, evaluated `deny` →
  `ask` → `allow`.** Scope does not break the tie, so a profile's `deny` or
  `ask` rule still holds in a repo whose `.claude/settings.local.json` allows
  the same call. What a repo's saved allow rules do reach is everything the
  profile leaves un-ruled — so write a restrictive profile as explicit
  `deny`/`ask` entries rather than relying on an empty `allow` list.
- **Where both files set the same single-value key, the repository's wins.** A
  project's `permissions.defaultMode` beats the profile's, except `auto` and
  `bypassPermissions`, which project files cannot set. Not every key is up for
  grabs: a repository's shared `.claude/settings.json` cannot set the keys the
  [settings reference](https://code.claude.com/docs/en/settings-reference#all-settings)
  scopes `User or managed`, `Managed`, or `Global config`, so for those the
  profile's value stands.
- **Project-scoped MCP servers outrank user-scoped ones and are not merged**, so
  a server declared in a repo's `.mcp.json` loads under every profile.

Run `/status` inside Claude Code to list the settings files the running session
actually loaded.

### What `~/.claude.json` carries

`~/.claude.json` is Claude Code's own file in `$HOME`, outside `~/.claude/`.
Alongside MCP server configuration it records which account you are signed in
as, per-project state such as trust decisions and MCP server approvals, and the
global config keys `/config` writes. `new` seeds it empty, so a fresh profile
runs onboarding again and asks you to trust each folder.

The login token itself is stored separately: on macOS in the Keychain, which
profiles never touch, and on Linux and Windows in `~/.claude/.credentials.json`,
which is inside the snapshot — so on those platforms the token swaps with the
profile. macOS
[falls back to that same file](https://code.claude.com/docs/en/iam#credential-management)
whenever the Keychain refuses the write, such as a locked Keychain in an SSH
session.

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
personal preferences and project learnings, and the stored `~/.claude.json`
carries the signed-in account record and MCP server definitions; because both
are versioned, deleting them from the live profile does not remove older copies
from that profile's Git history. On Linux and Windows — and on macOS whenever
the Keychain write is rejected — `.credentials.json` is versioned too, so
`restore` can bring an earlier login back. These repositories and Git objects
stay local and are not uploaded by claude-profile; they are plaintext, protected
only by filesystem permissions — the store is created `chmod 700` and every
command runs under `umask 077`, so the copies stay readable just by you.

Existing profiles receive the managed rules automatically. Their first
subsequent save establishes the earliest recoverable memory baseline. Restoring
a commit older than that baseline preserves current memory and prints a warning,
because an absent path in the old commit means it was ignored, not necessarily
that it did not exist. Restore always preserves current session/disposable
roots, even if an older bug or a manual force-add put those paths in a commit.
Restore also refuses to remove or recreate an embedded Git repository in an
ordinary tracked path: the outer profile history stores only its gitlink commit
ID, not the nested repository's worktree, so applying that transition could
otherwise delete data that the safety commit cannot recover.

Rules outside claude-profile's marked managed block are preserved textually
when the policy is refreshed, and still apply to ordinary profile paths. They
cannot override the managed history boundary: standard durable memory is
always versioned, while project transcripts and the other disposable roots are
always excluded. There is currently no `.gitignore` opt-out for that boundary.
Save and diff enforce it directly, so nested or global ignore rules cannot hide
durable memory or pull project transcripts into history.

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
| `CLAUDE_CODE_HOME` | `~/.claude` | Live Claude Code directory that `claude-profile` snapshots and swaps |
| `CLAUDE_PROFILE_HOME` | *(see below)* | Override profiles storage location |
| `XDG_DATA_HOME` | `~/.local/share` | XDG data directory (profiles stored in `$XDG_DATA_HOME/claude-profile`) |
| `CLAUDE_PROFILE_INSTALL_DIR` | `~/.local/bin` | Install location for the binary |
| `CLAUDE_PROFILE_COMPLETIONS_DIR` | *(auto-detect)* | Custom completions directory |

`CLAUDE_CODE_HOME` belongs to `claude-profile`; Claude Code does not read it. Claude Code relocates its own home-directory files with [`CLAUDE_CONFIG_DIR`](https://code.claude.com/docs/en/env-vars), which `claude-profile` does not read — so if you set that, point `CLAUDE_CODE_HOME` at the same directory or profiles will manage one Claude Code no longer reads.

### Storage location resolution

Priority: `CLAUDE_PROFILE_HOME` > `XDG_DATA_HOME/claude-profile` > `$HOME/.local/share/claude-profile`
