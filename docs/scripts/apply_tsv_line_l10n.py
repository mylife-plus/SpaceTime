#!/usr/bin/env python3
"""
Replace simple static string literals on/near TSV line numbers with 'key'.tr.
Batches by file. Skips tooltip_, dynamic labels, snackbar/composite en values.
"""
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


def try_replace_near_line(
    lines: list[str], line_no: int, key: str, old_sq: str, old_dq: str
) -> int:
    """Returns 1 if edited, 2 if already wired, 0 if no match."""
    for delta in range(-4, 5):
        idx = line_no - 1 + delta
        if idx < 0 or idx >= len(lines):
            continue
        ln = lines[idx]
        if key_in_line(ln, key):
            return 2
        if old_sq not in ln and old_dq not in ln:
            continue
        if ln.count(old_sq) + ln.count(old_dq) != 1:
            continue
        if old_sq in ln:
            lines[idx] = ln.replace(old_sq, f"'{key}'.tr", 1)
        else:
            lines[idx] = ln.replace(old_dq, f"'{key}'.tr", 1)
        lines[idx] = lines[idx].replace("const Text(", "Text(")
        return 1
    return 0


def main() -> int:
    en = json.loads((REPO / "assets" / "l10n" / "en.json").read_text(encoding="utf-8"))
    jobs: dict[Path, list[tuple[int, str, str]]] = defaultdict(list)
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
        jobs[path].append((line_no, key, label))

    n = 0
    for path, items in jobs.items():
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        for line_no, key, label in sorted(items, key=lambda x: -x[0]):
            old_sq = dart_sq(label)
            old_dq = dart_dq(label)
            if try_replace_near_line(lines, line_no, key, old_sq, old_dq) == 1:
                n += 1
        path.write_text("".join(lines), encoding="utf-8")

    print(f"apply_tsv_line_l10n: {n} replacements in {len(jobs)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
