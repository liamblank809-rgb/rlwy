#!/usr/bin/env bash
set -u

# The Hermes Skills Hub is used rather than copying arbitrary third-party code
# into the image. This keeps skill discovery/update separate from the founder
# operating system.

if ! command -v hermes >/dev/null 2>&1; then
  exit 0
fi

for term in ${FOUNDER_SKILLS:-}; do
  echo "[skills] discover: $term"
  hermes skills search "$term" --source official || true
done
