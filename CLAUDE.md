# CLAUDE.md

Development guide for `claude-profile` — a bash CLI tool for switching between Claude Code configurations.

## CRITICAL: User Data Protection

**This tool manages real user configuration files (`~/.claude/`, `~/.claude.json`). A bug or careless test can destroy a user's MCP servers, settings, agents, skills, and keybindings with NO way to recover.**

### Rules — no exceptions

1. **NEVER run `claude-profile` commands against the real `$HOME`** — not for testing, not for demos, not for "quick checks". Always use an isolated environment.
2. **NEVER run `rm -rf` on `~/.claude/profiles`** or any real user path during development.
3. **ALL testing happens in bats** (which isolates `$HOME` automatically) or in a manually isolated env:
   ```bash
   export HOME=$(mktemp -d)
   export CLAUDE_CODE_HOME="$HOME/.claude"
   mkdir -p "$CLAUDE_CODE_HOME"
   git config --global user.name test && git config --global user.email test@test
   # NOW you can safely run claude-profile commands
   ```
4. **If you need to demonstrate the tool to a user**, show the bats test output or use the isolated env pattern above. Do NOT run against their real config.

### Why this matters

During early development, manual testing in the real `$HOME` destroyed a user's MCP server configuration. The backup was also deleted by `rm -rf ~/.claude/profiles`. The data was unrecoverable. This must never happen again.

## Architecture

```
claude-profile              # Entrypoint: source modules + dispatch commands
lib/
  config.sh                 # Constants, managed items, _item_source/_item_name
  output.sh                 # Colors, info/ok/warn/err helpers
  state.sh                  # get_current, set_current, backup, validation helpers
  files.sh                  # Copy operations between profiles and live paths
  git.sh                    # Git history: init, commit, resolve ref
commands/
  profile.sh                # new, fork, use, save, deactivate
  info.sh                   # list, current, show, edit, delete
  history.sh                # history, diff, restore
  ui.sh                     # prompt-init, statusline
tests/
  test_helper.bash          # Shared setup: isolated $HOME, run_cli helpers
  <command>.bats            # One test file per command
  isolation.bats            # Cross-cutting isolation tests
completions/
  claude-profile.zsh        # Zsh tab completions
  claude-profile.bash       # Bash tab completions
```

### Key principles

- **One file = one responsibility**. Commands are in `commands/`, shared logic in `lib/`.
- **All file operations go through `lib/files.sh`**. Never copy/remove managed items directly in command files — use `_snapshot_current`, `_save_current_to`, `_load_profile_to_live`, `_restore_from_backup`.
- **All git operations go through `lib/git.sh`**. Never call `git` directly in command files — use `_git_init`, `_git_commit`, `_git_resolve_ref`.
- **Profiles are independent copies, not symlinks**. Switching copies files in/out of `~/.claude/`.
- **The original backup (`.pre-profiles-backup/`) is never modified** after creation. It's the safety net.
- **Items outside `~/.claude/`** (like `~/.claude.json`) use the `name:path` format in `MANAGED_ITEMS`. Use `_item_source` for the live path and `_item_name` for the name inside profile directories.

### Path resolution

Most managed items live in `~/.claude/<name>`. Items with custom paths use `name:path` format:

```bash
# In MANAGED_ITEMS array:
"settings.json"                      # → ~/.claude/settings.json
".claude.json:$HOME/.claude.json"    # → ~/.claude.json (in $HOME, not in ~/.claude/)
```

Always use these helpers, never hardcode paths:
- `_item_source "$item"` — resolves to the live filesystem path
- `_item_name "$item"` — resolves to the storage name inside profile directories

**Use `iname` (not `name`) for loop variables** to avoid shadowing function parameters.

## Development workflow — TDD

**All changes must follow TDD: write the test first, then implement.**

### Adding a new feature

1. **Write the failing test first**

   Create or edit `tests/<command>.bats`:

   ```bash
   #!/usr/bin/env bats
   load test_helper

   @test "rename: changes profile name" {
     run_cli_ok fork original
     run_cli_ok rename original new-name

     [ ! -d "$(profile_dir original)" ]
     [ -d "$(profile_dir new-name)" ]
   }

   @test "rename: fails on nonexistent" {
     run_cli rename nope other
     [ "$status" -ne 0 ]
     [[ "$output" == *"not found"* ]]
   }

   @test "rename: refuses to rename active profile" {
     run_cli_ok fork active
     run_cli_ok use active
     run_cli rename active other
     [ "$status" -ne 0 ]
   }
   ```

2. **Run the test — confirm it fails**

   ```bash
   bats tests/rename.bats
   ```

3. **Implement the feature**

   - Add command function in the appropriate `commands/*.sh` file (or create a new one)
   - Add shared logic to `lib/*.sh` if needed
   - Add the command to the dispatch `case` in `claude-profile`
   - Add to completions in `completions/`

4. **Run the test — confirm it passes**

   ```bash
   bats tests/rename.bats
   ```

5. **Run the full suite — confirm nothing broke**

   ```bash
   bats tests/
   ```

6. **NEVER verify manually against real `$HOME`** — if bats tests pass, the feature works. If you need additional confidence, use the isolated env pattern from the top of this file.

### Writing tests

Tests use [bats-core](https://github.com/bats-core/bats-core). Each test gets a fully isolated `$HOME` in a temp directory — the real `~/.claude/` is never touched.

**The isolated environment provides:**
- `$HOME` → `/tmp/.../home/` (unique per test, auto-cleaned)
- `$CLAUDE_CODE_HOME` → `$HOME/.claude/`
- `~/.claude/settings.json` with realistic content
- `~/.claude/skills/my-skill/SKILL.md`
- `~/.claude/agents/` (empty directory)
- `~/.claude.json` with MCP server config
- Git identity configured (`user.name`, `user.email`)

**Test helpers** (defined in `test_helper.bash`):

| Helper | Purpose |
|--------|---------|
| `run_cli <args>` | Run claude-profile, populates `$status` and `$output` |
| `run_cli_ok <args>` | Run and assert exit 0 (prints debug info on failure) |
| `profile_dir <name>` | Returns profile directory path |
| `backup_dir` | Returns `.pre-profiles-backup` path |

**Test conventions:**

- One `.bats` file per command (matches `commands/*.sh` structure)
- Test names describe behavior, not implementation: `"auto-saves before switching"` not `"calls _save_current_to"`
- Each test is independent — no shared state between tests
- Test both the happy path AND error cases (missing args, nonexistent profiles, duplicates)
- For git history tests, make a change before `save` — git skips commits with no diff

**Example patterns:**

```bash
# Testing a command succeeds and produces correct state
@test "creates profile with expected files" {
  run_cli_ok fork myprofile
  [ -f "$(profile_dir myprofile)/settings.json" ]
}

# Testing error handling
@test "fails with helpful message on bad input" {
  run_cli some-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

# Testing isolation between profiles
@test "changing one profile doesn't affect another" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha
  echo '{"only_alpha": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok use beta
  ! grep -q '"only_alpha"' "$CLAUDE_CODE_HOME/settings.json"
}

# Testing git history
@test "save creates a commit with the message" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"   # Must change something!
  run_cli_ok save -m "My change"
  local log
  log="$(git -C "$(profile_dir default)" log --oneline)"
  [[ "$log" == *"My change"* ]]
}
```

## Commands reference

```bash
bats tests/             # Run all tests
bats tests/fork.bats    # Run tests for one command
bats tests/ --tap       # TAP output for CI
```

## Releasing

Version is defined in `lib/config.sh` as `VERSION="X.Y.Z"`. When creating a new release, **always keep the VERSION variable and git tag in sync**:

1. Update `VERSION` in `lib/config.sh`
2. Commit the change
3. Tag with the matching version: `git tag v0.1.0`
4. Push both: `git push origin main --tags`

Never create a git tag without updating `VERSION` first — `claude-profile version` must match the tag.

## Common pitfalls

- **Variable shadowing**: Use `iname` (not `name`) for managed item names in loops — `name` is often the profile name in the outer function scope.
- **`set -euo pipefail`**: Don't use `[[ cond ]] && action` — if the condition is false, the script exits. Use `if/then/fi`.
- **Git in tests**: The isolated `$HOME` has no git config by default — `test_helper.bash` sets `user.name` and `user.email`. If you add new test files, always `load test_helper`.
- **`mapfile`**: Used in `_load_managed_items`. Requires bash 4+. macOS ships bash 3 but `#!/usr/bin/env bash` picks up Homebrew's bash 5 if installed.
- **Testing against real `$HOME`**: NEVER. See the top of this file. Use bats or the isolated env pattern. There is no exception to this rule.
