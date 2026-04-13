#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

git config --global commit.gpgsign false

if [ -n "${GITHUB_TOKEN:-}" ]; then
  git config --global \
    url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf \
    "https://github.com/"
else
  echo "WARNING: GITHUB_TOKEN not set — push will fail" >&2
fi
