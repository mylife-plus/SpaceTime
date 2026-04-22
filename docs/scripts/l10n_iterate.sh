#!/usr/bin/env bash
# From repo root: bash docs/scripts/l10n_iterate.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
python3 docs/scripts/verify_l10n.py
python3 docs/scripts/find_remaining_l10n.py
python3 docs/scripts/apply_tsv_line_l10n.py
for _ in 1 2 3 4 5; do
  python3 docs/scripts/find_remaining_l10n.py
  python3 docs/scripts/apply_closest_line_l10n.py || true
done
python3 docs/scripts/find_remaining_l10n.py
echo "See docs/l10n_remaining.tsv"
