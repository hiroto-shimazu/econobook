#!/usr/bin/env bash
set -euo pipefail

echo "→ Resolve deps"
flutter pub get

echo "→ Format (changed files only if git present)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CHANGED=$(git diff --name-only --diff-filter=ACM | grep '\.dart$' || true)
  if [ -n "$CHANGED" ]; then
    dart format $CHANGED
  fi
fi

echo "→ Full format (safety net)"
dart format lib/ test/

echo "→ Analyze"
dart analyze

echo "→ Unit/Widget tests"
flutter test --coverage

echo "→ Done ✅"