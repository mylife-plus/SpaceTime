#!/usr/bin/env python3
"""
Compare lib/ + inventory TSV: list rows whose proposed_key is not wired and/or
English literal still appears in the target file.
Output: docs/l10n_remaining.tsv (and summary line count).
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from l10n_tsv_util import (
    REPO,
    SNACKBAR_SPLIT,
    dart_dq,
    dart_sq,
    english_entry,
    load_tsv_rows_raw,
    parse_file_line,
    resolve_lib_path,
    snackbar_body,
    unescape_tsv_field,
)

OUT = REPO / "docs" / "l10n_remaining.tsv"
APP_TEXT = REPO / "lib" / "app" / "config" / "app_text.dart"


def strip_dart_comments(text: str) -> str:
    """Remove // line comments and /* */ (best-effort)."""
    text = re.sub(r"/\*[\s\S]*?\*/", " ", text)
    lines = []
    for ln in text.splitlines():
        if "//" in ln:
            in_str = False
            q = ""
            i = 0
            cut = len(ln)
            while i < len(ln) - 1:
                c = ln[i]
                if not in_str:
                    if c in "'\"":
                        in_str = True
                        q = c
                    elif c == "/" and ln[i + 1] == "/":
                        cut = i
                        break
                else:
                    if c == "\\":
                        i += 1
                    elif c == q:
                        in_str = False
                i += 1
            ln = ln[:cut]
        lines.append(ln)
    return "\n".join(lines)


def key_integrated_in_text(text: str, key: str) -> bool:
    esc = re.escape(key)
    if f"'{key}'.tr" in text or f'"{key}".tr' in text:
        return True
    if re.search(rf"trKey\s*\(\s*['\"]{esc}['\"]", text):
        return True
    if re.search(rf"showTrSnackbar\s*\([\s\S]{{0,800}}?['\"]{esc}['\"]", text):
        return True
    return False


def app_text_uses_key(key: str) -> bool:
    if not APP_TEXT.is_file():
        return False
    t = APP_TEXT.read_text(encoding="utf-8")
    return f"'{key}'.tr" in t


def literal_still_present(text: str, label: str, en_value: str) -> bool:
    t = strip_dart_comments(text)
    if not label and not en_value:
        return False
    sq_l = dart_sq(label)
    dq_l = dart_dq(label)
    if sq_l in t or dq_l in t:
        return True
    if SNACKBAR_SPLIT in en_value:
        a, b = en_value.split(SNACKBAR_SPLIT, 1)
        # Compare raw TSV title/body for Get.snackbar leftovers
        if dart_sq(a) in t or dart_dq(a) in t:
            if dart_sq(b) in t or dart_dq(b) in t:
                return True
            if "$" in b and "Get.snackbar" in t:
                return True
    if "${" in label or (label.startswith("$") and len(label) < 40):
        if label.strip() and label in t:
            return True
    return False


def main() -> int:
    import json

    en_path = REPO / "assets" / "l10n" / "en.json"
    en_map = json.loads(en_path.read_text(encoding="utf-8"))

    remaining: list[dict] = []
    for row in load_tsv_rows_raw():
        key = row[0]
        sk = row[1]
        loc = parse_file_line(row[2])
        if loc is None:
            remaining.append(
                {
                    "key": key,
                    "reason": "bad_file_cell",
                    "file": row[2],
                    "source_kind": sk,
                }
            )
            continue
        rel, _ln = loc
        path = resolve_lib_path(rel)
        if path is None:
            remaining.append(
                {
                    "key": key,
                    "reason": "missing_file",
                    "file": rel,
                    "source_kind": sk,
                }
            )
            continue
        text = path.read_text(encoding="utf-8")
        label = unescape_tsv_field(row[3] if len(row) > 3 else "")
        en_val = en_map.get(key, english_entry(row))

        integrated = key_integrated_in_text(text, key)
        if key.startswith("apptexts_") and app_text_uses_key(key):
            integrated = True

        if integrated:
            continue

        if not literal_still_present(text, label, en_val):
            continue

        remaining.append(
            {
                "key": key,
                "reason": "literal_in_file",
                "file": str(path.relative_to(REPO)),
                "source_kind": sk,
                "english_label": label[:120],
            }
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "proposed_key",
                "reason",
                "file",
                "source_kind",
                "english_label",
            ],
            delimiter="\t",
            extrasaction="ignore",
        )
        w.writeheader()
        for r in remaining:
            w.writerow(
                {
                    "proposed_key": r["key"],
                    "reason": r["reason"],
                    "file": r.get("file", ""),
                    "source_kind": r.get("source_kind", ""),
                    "english_label": r.get("english_label", ""),
                }
            )

    print(f"Wrote {OUT} — {len(remaining)} remaining (inventory minus tooltips: {len(load_tsv_rows_raw())})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
