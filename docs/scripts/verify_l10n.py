#!/usr/bin/env python3
"""Compare assets/l10n/*.json keys to docs/user_visible_strings.tsv (exclude tooltip_)."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TSV = REPO / "docs" / "user_visible_strings.tsv"
L10N = REPO / "assets" / "l10n"


def tsv_keys() -> set[str]:
    keys: set[str] = set()
    with TSV.open(encoding="utf-8") as f:
        r = csv.reader(f, delimiter="\t")
        next(r, None)
        for row in r:
            if len(row) < 1:
                continue
            k = row[0]
            if k.startswith("tooltip_"):
                continue
            keys.add(k)
    return keys


def main() -> int:
    expected = tsv_keys()
    langs = ["en", "es", "fr", "de"]
    maps: dict[str, set[str]] = {}
    for code in langs:
        p = L10N / f"{code}.json"
        if not p.exists():
            print(f"MISSING file {p}", file=sys.stderr)
            return 1
        with p.open(encoding="utf-8") as f:
            maps[code] = set(json.load(f).keys())

    base = maps["en"]
    for code in langs[1:]:
        if maps[code] != base:
            only_en = sorted(base - maps[code])
            only_x = sorted(maps[code] - base)
            print(f"KEY MISMATCH {code} vs en: only in en {len(only_en)}, only in {code} {len(only_x)}")
            if only_en[:20]:
                print("  sample only en:", only_en[:20])
            if only_x[:20]:
                print(f"  sample only {code}:", only_x[:20])
            return 1

    missing = sorted(expected - base)
    extra = sorted(base - expected)
    if missing:
        print(f"MISSING in json ({len(missing)}):", missing[:30], ("..." if len(missing) > 30 else ""))
    if extra:
        print(f"EXTRA in json ({len(extra)}):", extra[:30], ("..." if len(extra) > 30 else ""))
    if missing or extra:
        return 1
    print(f"OK: {len(expected)} keys in all of {langs}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
