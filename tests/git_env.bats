#!/usr/bin/env bats
# Regression coverage for Git hook environments. Git launches hooks with
# repository-local GIT_* variables exported; the test suite must scrub those at
# load time before any fixture creates commits.

clean_git() (
  unset $(git rev-parse --local-env-vars 2>/dev/null) \
        GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM 2>/dev/null || true
  git "$@"
)

@test "git environment: suite launch scrubs inherited repository variables" {
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  local canary="$BATS_TEST_TMPDIR/canary"
  clean_git init -q "$canary"
  clean_git -C "$canary" -c user.email=test@test -c user.name=test \
    commit -q --allow-empty -m CANARY

  local expected_head
  expected_head="$(clean_git -C "$canary" rev-parse HEAD)"

  run env \
    GIT_DIR="$canary/.git" \
    GIT_WORK_TREE="$canary" \
    GIT_INDEX_FILE="$canary/.git/index" \
    bats "$repo_root/tests/isolation.bats"

  if [[ "$status" -ne 0 ]]; then
    echo "$output"
  fi
  [ "$status" -eq 0 ]

  [ "$(clean_git -C "$canary" rev-parse HEAD)" = "$expected_head" ]
  [ "$(clean_git -C "$canary" rev-list --count HEAD)" -eq 1 ]

  local canary_status
  canary_status="$(clean_git -C "$canary" status --short)"
  if [[ -n "$canary_status" ]]; then
    echo "$canary_status"
  fi
  [ -z "$canary_status" ]
}
