# Configuration

## How it works

Think of it like git branches. Your original `~/.claude/` state is the **main branch** — backed up once and preserved by normal profile operations. Each profile is an independent **fork** you can change freely.

The paths below are defaults. If you set `CLAUDE_CONFIG_DIR`, profiles manage that
directory and its `.claude.json` instead; see [environment variables](#environment-variables).

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

By default, `~/.claude.json` is Claude Code's own file in `$HOME`, outside `~/.claude/`.
When `CLAUDE_CONFIG_DIR` is set, that file is `$CLAUDE_CONFIG_DIR/.claude.json`.
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
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Official Claude Code setting: relocates the live directory and puts `.claude.json` inside it |
| `CLAUDE_CODE_HOME` | *(unset)* | Legacy `claude-profile` override for the live directory only; Claude Code does not read it |
| `CLAUDE_PROFILE_HOME` | *(see below)* | Override profiles storage location |
| `XDG_DATA_HOME` | `~/.local/share` | XDG data directory (profiles stored in `$XDG_DATA_HOME/claude-profile`) |
| `CLAUDE_PROFILE_INSTALL_DIR` | `~/.local/bin` | Install location for the binary |
| `CLAUDE_PROFILE_COMPLETIONS_DIR` | *(auto-detect)* | Custom completions directory |

Prefer [`CLAUDE_CONFIG_DIR`](https://code.claude.com/docs/en/env-vars), which both
Claude Code and `claude-profile` read. Export it in the shell that runs both:

```bash
export CLAUDE_CONFIG_DIR="$HOME/.claude-work"
export CLAUDE_PROFILE_HOME="$HOME/.local/share/claude-profile-work"
claude-profile fork work
claude
```

A non-empty `CLAUDE_CONFIG_DIR` selects the live directory and
`$CLAUDE_CONFIG_DIR/.claude.json`. Without it, `CLAUDE_CODE_HOME` selects only the
live directory and the separate file stays at `$HOME/.claude.json`. Empty values
are treated as unset. If both variables are non-empty, they must resolve to the
same directory; otherwise commands stop before writing. Run
`unset CLAUDE_CODE_HOME` to remove a conflicting legacy override.
`CLAUDE_CONFIG_DIR` must be an absolute path. The live directory must be a
dedicated configuration directory; `/`, your home directory, and its ancestors
are refused, including aliases through symlinks.

The `.claude.json` inside an explicitly configured directory is stored as
`.claude-profile-home.json` in each profile, just like the default home file.
Changing these variables does not move existing configuration or profile stores.

`CLAUDE_CONFIG_DIR` does not change where profiles are stored. Keep
one stable live directory per profile store. Give independent configurations
separate `CLAUDE_PROFILE_HOME` values, even when used at different times: each
store has one active profile and one original backup. On the first write, the
store records the canonical directory and JSON location in `.live-paths`.
Later writes, installation, and live-file inspection refuse a mismatch before
changing configuration. `list` and `history` remain available for inspection.
Equivalent directory aliases work, and replacing a JSON symlink does not change
the binding. Existing stores without this metadata adopt the paths selected on
their first write after upgrading; their old location cannot be inferred.

### Upgrading with a custom config directory

Older releases ignored `CLAUDE_CONFIG_DIR`, so existing profiles and the original
backup may contain the default configuration instead of your custom one. The
updated version never rewrites that backup. Set a fresh `CLAUDE_PROFILE_HOME`
alongside `CLAUDE_CONFIG_DIR`, then run `claude-profile fork <name>` before
switching profiles. This captures the custom live configuration and creates its
own original backup. Keep the previous store for recovery.

### Migrating stores with two JSON files

Some older stores contain the real account JSON at `PROFILE/.claude.json`,
while `PROFILE/.claude-profile-home.json` contains an unused or different
account's home file, or is absent. This can happen when `CLAUDE_CONFIG_DIR` was
`$HOME/.claude` (including devcontainers), or when `CLAUDE_CODE_HOME` matched the
custom directory under an older version.

The two names do not tell you which account is intended. The conflict message
prints both paths and the managed source that would be loaded. Inspect those
files locally and identify the intended account and MCP servers before making a
choice. Simply moving the payload aside can leave the wrong account selected.

1. Keep the original store and its backup intact. Use a fresh store with the
   intended `CLAUDE_CONFIG_DIR`, then `fork before-recovery` to preserve the
   current live configuration there.
2. Copy the old profile directory into that fresh store under a new, unused
   profile name. Preserve separate copies of both JSON files outside the copied
   profile, including the existing `.claude-profile-home.json` if it exists.
3. If `.claude.json` is the real account JSON, move it to
   `.claude-profile-home.json` **in the copied profile**, replacing only the
   already-preserved managed copy. The copied profile must no longer have a
   root `.claude.json` entry. If the managed file is the intended account JSON,
   keep it and move the unrelated payload to your recovery copies instead.
4. Run `claude-profile use <copied-profile>` with that fresh store and the same
   config-directory setting. Check the account and MCP servers in Claude Code.

Saves, switches, and history restores refuse incompatible JSON layouts so they
cannot silently discard one source. An original backup with this conflict needs
the same recovery through a copy; do not edit the original backup in place.

### Storage location resolution

Priority: `CLAUDE_PROFILE_HOME` > `XDG_DATA_HOME/claude-profile` > `$HOME/.local/share/claude-profile`
