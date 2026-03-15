<div align="center">

<img src="docs/logo.svg" alt="claude-profile" width="560">

<br>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](claude-profile)
[![Tests: bats](https://img.shields.io/badge/Tests-bats--core-yellow)](tests/)

Different tasks need different setups. Code review needs read-only permissions and a careful persona.<br>
Daily dev needs full access and speed. Learning needs explanatory output.<br>
Define each as a profile, switch with one command.

</div>

---

```bash
$ claude-profile fork default          # save your current setup
$ claude-profile new code-review       # create a new profile
$ claude-profile use code-review       # switch instantly

$ claude-profile list
  ○ default
  ● code-review (active)
```

## Install

### Homebrew (recommended)

```bash
brew tap yarikleto/claude-profile
brew install claude-profile
```

### From source

```bash
git clone https://github.com/yarikleto/claude-profile.git
cd claude-profile && bash install.sh
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/yarikleto/claude-profile/main/install.sh | bash
```

### Update

```bash
# Homebrew
brew upgrade claude-profile

# From source — pull and re-run the installer
cd claude-profile && git pull && bash install.sh
```

Your profiles and config are never touched — updates only replace the CLI binary and modules.

## Quick start

```bash
# 1. Save your current Claude Code setup as a profile
claude-profile fork default

# 2. Create a clean profile for a different workflow
claude-profile new experiment

# 3. Switch between them
claude-profile use experiment     # clean slate
claude-profile use default        # back to your setup
```

That's it. Your original config is automatically backed up and can be restored at any time with `claude-profile deactivate`.

## What gets switched

Each profile is an independent copy of these files:

| File | Controls |
|------|----------|
| `settings.json` | Model, permissions, hooks, effort level |
| `CLAUDE.md` | Personal instructions and behavior |
| `agents/` | Custom subagents |
| `skills/` | Slash commands and workflows |
| `rules/` | Topic-specific rules |
| `keybindings.json` | Keyboard shortcuts |
| `~/.claude.json` | MCP servers and local config |

Everything else (memory, sessions, plugins) stays global across profiles.

## Commands

### Managing profiles

```
new <name>              Create a clean empty profile
fork <name>             Copy current state into a new profile
use <name>              Switch to a profile (auto-saves current)
delete <name> [-f]      Delete a profile
deactivate              Restore original state, turn off profiles
```

### Inspecting profiles

```
list                    List all profiles, highlight active
current                 Print active profile name
show [name]             Show profile contents
edit [name]             Open profile directory in editor
```

### Version history

Every profile has built-in git history. Each save is a commit.

```
save [-m "message"]     Save current state with a commit message
history [name]          View change log with dates
diff [name] [ref]       Show changes since last save or a specific commit
restore [name] <ref>    Restore profile to a point in time
```

```bash
$ claude-profile save -m "Added code review agents"
$ claude-profile history
  17c7034 2025-03-15 14:30:00  Added code review agents
  a24a13b 2025-03-15 12:00:00  Profile created

$ claude-profile restore a24a13b    # go back to that point
```

### UI integration

**Shell prompt** — see the active profile in your terminal:

```bash
# Add to .zshrc or .bashrc
eval "$(claude-profile prompt-init zsh)"
```
```
~/projects/my-app [review] $
```

**Claude Code status line:**

```bash
claude-profile statusline install
```
```
Opus 4.6 · profile: review
```

## How it works

Think of it like git branches. Your original `~/.claude/` state is the **main branch** — always preserved, never modified. Each profile is an independent **fork** you can change freely.

```
~/.claude/
├── settings.json                ← copied from active profile
├── CLAUDE.md                    ← copied from active profile
├── agents/                      ← copied from active profile
└── profiles/
    ├── .current                 # tracks which profile is active
    ├── .pre-profiles-backup/    # your original state (read-only)
    ├── default/                 # profile with its own git history
    │   ├── .git/
    │   ├── settings.json
    │   └── ...
    └── code-review/             # another independent profile
        ├── .git/
        ├── settings.json
        ├── CLAUDE.md
        └── ...
```

### Safety guarantees

- **Original state backup** — your pre-profiles `~/.claude/` is backed up automatically on first use. The backup is never modified.
- **Auto-save on switch** — `use` saves the current profile before switching. No changes are lost.
- **Full isolation** — each profile is an independent copy. Changing one never affects another.
- **Clean restore** — `deactivate` restores your original state. Safe to uninstall at any time.

## Configuration

### Custom managed items

Override what files get switched by creating `~/.claude/__profiles__/.managed`:

```bash
# One item per line. Use name:path for files outside ~/.claude/
settings.json
CLAUDE.md
agents
skills
rules
keybindings.json
.claude.json:/Users/you/.claude.json
plugins   # add new items as needed
```

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_CODE_HOME` | `~/.claude` | Claude Code config directory |
| `CLAUDE_PROFILE_INSTALL_DIR` | `~/.local/bin` | Install location for the binary |
| `CLAUDE_PROFILE_COMPLETIONS_DIR` | *(auto-detect)* | Custom completions directory |

## FAQ

<details>
<summary><strong>Does switching profiles affect running Claude Code sessions?</strong></summary>

Claude Code reads config at startup. A running session won't pick up profile changes until you restart it.
</details>

<details>
<summary><strong>What about MCP servers?</strong></summary>

`~/.claude.json` (which contains MCP server configs) is managed by profiles. Each profile gets its own MCP server setup.
</details>

<details>
<summary><strong>Can I use project-level profiles?</strong></summary>

Not yet — `claude-profile` manages user-level (`~/.claude/`) configuration. Project-level config (`.claude/` in a repo) is typically committed to git and shared with your team.
</details>

<details>
<summary><strong>How do I uninstall?</strong></summary>

**1. Restore your original config:**

```bash
claude-profile deactivate
```

**2. Remove the CLI:**

```bash
# Homebrew
brew uninstall claude-profile

# From source
bash uninstall.sh
```

**3. Remove profile data (optional):**

```bash
rm -rf ~/.claude/profiles
```

See the full [uninstall guide](docs/uninstall.md) for manual steps and edge cases.
</details>

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) with full filesystem isolation — every test runs in its own `$HOME`, so the real `~/.claude/` is never touched.

```bash
brew install bats-core    # install bats
bats tests/               # run all tests
bats tests/fork.bats      # run one test file
```

## Contributing

PRs welcome. Development follows TDD — write the failing test first, then implement. See [CLAUDE.md](CLAUDE.md) for architecture and workflow details.

## License

[MIT](LICENSE)
