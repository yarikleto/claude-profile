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

### One-liner

```bash
git clone https://github.com/yarikleto/claude-profile.git && cd claude-profile && bash install.sh
```

Open a new shell once to load tab completion: `exec zsh` or `exec bash`.

### Update

```bash
# Homebrew
brew upgrade claude-profile

# From source
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

Each profile snapshots the **entire** `~/.claude/` directory plus `~/.claude.json`. Switching profiles means a completely different Claude "brain" — settings, memory, conversations, plugins, history, everything.

Profiles are stored in `~/.local/share/claude-profile/` (XDG-compliant), separate from `~/.claude/`.

## Commands

```
new <name>              Create a clean empty profile and activate it
fork <name>             Copy current state into a new profile
use <name>              Switch to a profile (auto-saves current)
list                    List all profiles, highlight active
current                 Print active profile name
show [name]             Show profile contents
edit [name]             Open profile directory in editor
delete <name> [-f]      Delete a profile
deactivate              Restore original state, turn off profiles
deactivate --keep       Detach from profiles, keep current config
```

### Version history

Every profile has built-in git history. Each save is a commit.

```
save [-m "message"]     Save current state with a commit message
history [name]          View change log with dates
diff [name] [ref]       Show unsaved changes or changes since a commit
restore [name] <ref>    Restore profile to a point in time
```

```bash
$ claude-profile save -m "Added code review agents"
$ claude-profile history
  17c7034 2025-03-15 14:30:00  Added code review agents
  a24a13b 2025-03-15 12:00:00  Profile created

$ claude-profile restore a24a13b
```

### Status line

The active profile name is shown in the Claude Code status line automatically:

```
Opus 4.6 · profile: review
```

This is configured during installation. If you already have a custom `statusLine` in `settings.json`, it won't be overwritten — run `claude-profile statusline install` manually to set it up.

## Safety

- **Original backup** — your pre-profiles config is backed up on first use and **never modified** by any operation. It's your safety net.
- **Auto-save on switch** — `use` saves the current profile before switching. No changes are lost.
- **Full isolation** — each profile is an independent copy. Changing one never affects another.
- **Clean exit** — `deactivate` restores your original state. `deactivate --keep` keeps your current config for [migration](#migrating-to-native-claude-code-profiles).

> **Your original backup is always safe.** It lives at `~/.local/share/claude-profile/.pre-profiles-backup/` and is never modified — not by `--keep`, not by regular `deactivate`, not by any profile operation. You can always restore from it manually.

## Migrating to native Claude Code profiles

When Claude Code adds native profile support, you can migrate without losing any data:

```bash
# 1. Switch to the profile you want to keep
claude-profile use my-preferred-profile

# 2. Detach — keeps your current config exactly as-is
claude-profile deactivate --keep

# 3. Uninstall
brew uninstall claude-profile        # or: bash uninstall.sh

# 4. Clean up (optional)
rm -rf ~/.local/share/claude-profile
```

`--keep` saves your profile, clears the active marker, and leaves all your files in place — Claude Code sees normal config. Without `--keep`, `deactivate` restores your original pre-profiles config.

See the full [migration guide](docs/migration.md) for details and troubleshooting.

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
<summary><strong>Can I customize the storage location?</strong></summary>

Set `CLAUDE_PROFILE_HOME` to override the profiles storage location, or `XDG_DATA_HOME` to use a custom XDG data directory. See [configuration docs](docs/configuration.md).
</details>

<details>
<summary><strong>How do I uninstall?</strong></summary>

```bash
claude-profile deactivate --keep   # or without --keep to restore original
brew uninstall claude-profile      # or: bash uninstall.sh
rm -rf ~/.local/share/claude-profile  # remove profile data
```

See the full [uninstall guide](docs/uninstall.md).
</details>

<details>
<summary><strong>What happens when Claude Code adds native profiles?</strong></summary>

See [migration guide](#migrating-to-native-claude-code-profiles). `deactivate --keep` gives you a clean exit — your config stays intact.
</details>

## Contributing

PRs welcome. Development follows TDD — write the failing test first, then implement. See [CLAUDE.md](CLAUDE.md) for architecture and dev workflow.

```bash
brew install bats-core    # install test runner
bats tests/               # run all tests
```

## License

[MIT](LICENSE)
