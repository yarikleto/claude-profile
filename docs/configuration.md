# Configuration

## How it works

Think of it like git branches. Your original `~/.claude/` state is the **main branch** — always preserved, never modified. Each profile is an independent **fork** you can change freely.

```
~/.claude/
├── settings.json                ← copied from active profile
├── CLAUDE.md                    ← copied from active profile
├── agents/                      ← copied from active profile
├── projects/                    ← moved from active profile (bulk)
└── __profiles__/
    ├── .current                 # tracks which profile is active
    ├── .seed/                   # templates for `new` (user-editable)
    ├── .managed                 # custom managed items (optional)
    ├── statusline.sh            # statusline script
    ├── .pre-profiles-backup/    # your original state (read-only)
    ├── default/                 # profile with its own git history
    │   ├── .git/
    │   ├── settings.json
    │   ├── projects/            # bulk: moved in/out on switch
    │   └── ...
    └── code-review/
        ├── .git/
        ├── settings.json
        ├── CLAUDE.md
        └── ...
```

Everything the tool stores lives in `~/.claude/__profiles__/`. This directory name is chosen to avoid conflicts with a future native profiles feature in Claude Code.

## Custom managed items

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

## Seed templates

When you run `claude-profile new`, the new profile is seeded with files from `~/.claude/__profiles__/.seed/`. This directory is created automatically during installation with minimal defaults (`settings.json` with statusline config, empty `.claude.json`).

You can customize these templates:

```bash
# Edit the seed settings
vi ~/.claude/__profiles__/.seed/settings.json

# Add more seed files
cp ~/.claude/CLAUDE.md ~/.claude/__profiles__/.seed/CLAUDE.md
```

Next time you run `new`, it will use your custom templates.

## Bulk items

Large data directories and files (`projects/`, `agent-memory/`, `todos/`, `plans/`, `tasks/`, `plugins/`, `history.jsonl`) are handled differently from config files:

- **On switch (`use`)** — moved (instant, even for hundreds of MB)
- **On fork/save** — copied (safe, preserves live data)
- **Not tracked by git** — excluded via `.gitignore` in each profile

This means switching profiles with large `projects/` directories is fast.

## Statusline

The statusline script lives at `~/.claude/__profiles__/statusline.sh` and is configured automatically during installation. It shows the model name and active profile in Claude Code's status bar.

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
| `CLAUDE_PROFILE_INSTALL_DIR` | `~/.local/bin` | Install location for the binary |
| `CLAUDE_PROFILE_COMPLETIONS_DIR` | *(auto-detect)* | Custom completions directory |
