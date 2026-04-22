#!/usr/bin/env python3
"""Replace literal on TSV line index only (handles duplicate literals in same file)."""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
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

PLACEHOLDER = re.compile(r"\$\d+")


def key_in_line(line: str, key: str) -> bool:
    return f"'{key}'.tr" in line or f'"{key}".tr' in line


def main() -> int:
    en = json.loads((REPO / "assets" / "l10n" / "en.json").read_text(encoding="utf-8"))
    by_path: dict[Path, list[tuple[int, str, str]]] = defaultdict(list)
    for row in load_tsv_rows_raw():
        key = row[0]
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
        by_path[path].append((line_no, key, label))

    n = 0
    for path, items in by_path.items():
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        for line_no, key, label in sorted(items, key=lambda x: -x[0]):
            idx = line_no - 1
            if idx < 0 or idx >= len(lines):
                continue
            if key_in_line(lines[idx], key):
                continue
            old_sq = dart_sq(label)
            old_dq = dart_dq(label)
            ln = lines[idx]
            if ln.count(old_sq) == 1:
                lines[idx] = ln.replace(old_sq, f"'{key}'.tr", 1)
                lines[idx] = lines[idx].replace("const Text(", "Text(")
                n += 1
            elif ln.count(old_dq) == 1:
                lines[idx] = ln.replace(old_dq, f"'{key}'.tr", 1)
                lines[idx] = lines[idx].replace("const Text(", "Text(")
                n += 1
        path.write_text("".join(lines), encoding="utf-8")

    print(f"apply_tsv_exact_line_l10n: {n} single-line replacements")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
