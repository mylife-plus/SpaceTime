#!/usr/bin/env python3
"""
For keys listed in docs/l10n_remaining.tsv: replace literal on the single line
in that file where it appears, choosing the line closest to TSV line hint.
Simple static labels only.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from l10n_tsv_util import (
    REPO,
    SNACKBAR_SPLIT,
    dart_dq,
    dart_sq,
    load_tsv_rows_raw,
    parse_file_line,
    resolve_lib_path,
    unescape_tsv_field,
)

REMAINING = REPO / "docs" / "l10n_remaining.tsv"
PLACEHOLDER = re.compile(r"\$\d+")


def load_remaining_keys() -> set[str]:
    keys: set[str] = set()
    with REMAINING.open(encoding="utf-8") as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            if row.get("proposed_key"):
                keys.add(row["proposed_key"])
    return keys


def key_in_line(line: str, key: str) -> bool:
    return f"'{key}'.tr" in line or f'"{key}".tr' in line


def main() -> int:
    if not REMAINING.is_file():
        print("No l10n_remaining.tsv — run find_remaining_l10n.py first")
        return 1
    want = load_remaining_keys()
    en = json.loads((REPO / "assets" / "l10n" / "en.json").read_text(encoding="utf-8"))
    n = 0
    for row in load_tsv_rows_raw():
        key = row[0]
        if key not in want:
            continue
        loc = parse_file_line(row[2])
        if loc is None:
            continue
        rel, line_no = loc
        label = unescape_tsv_field(row[3] if len(row) > 3 else "")
        if not label or "\n" in label or "${" in label or re.match(r"^\s*\$", label):
            continue
        val = en.get(key, "")
        if SNACKBAR_SPLIT in val or PLACEHOLDER.search(val):
            continue
        path = resolve_lib_path(rel)
        if path is None:
            continue
        old_sq = dart_sq(label)
        old_dq = dart_dq(label)
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        candidates: list[int] = []
        for i, ln in enumerate(lines):
            if key_in_line(ln, key):
                continue
            c = ln.count(old_sq) + ln.count(old_dq)
            if c == 1:
                candidates.append(i)
        if not candidates:
            continue
        hint = line_no - 1
        idx = min(candidates, key=lambda i: abs(i - hint))
        ln = lines[idx]
        if old_sq in ln and ln.count(old_sq) == 1:
            lines[idx] = ln.replace(old_sq, f"'{key}'.tr", 1)
        else:
            lines[idx] = ln.replace(old_dq, f"'{key}'.tr", 1)
        lines[idx] = lines[idx].replace("const Text(", "Text(")
        path.write_text("".join(lines), encoding="utf-8")
        n += 1
        want.discard(key)

    print(f"apply_closest_line_l10n: {n} replacements; keys left in list: {len(want)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
