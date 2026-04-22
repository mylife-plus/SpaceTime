#!/usr/bin/env python3
"""
Build assets/l10n/{en,es,fr,de}.json from docs/user_visible_strings.tsv
Skips proposed_key starting with tooltip_.
Snackbar title+body: "title@@@body" (translate parts separately for non-EN).
Interpolations: ${...} and $var become $1, $2, ... in order.
"""
from __future__ import annotations

import csv
import json
import os
import re
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TSV_PATH = REPO / "docs" / "user_visible_strings.tsv"
OUT_DIR = REPO / "assets" / "l10n"

SNACKBAR_SPLIT = "@@@"

_INTERP_BRACE = re.compile(r"\$\{[^}]+\}")
_INTERP_SIMPLE = re.compile(r"\$[a-zA-Z_][a-zA-Z0-9_]*")


def normalize_interpolations(s: str) -> str:
    n = 0

    def rb(m):
        nonlocal n
        n += 1
        return f"${n}"

    t = _INTERP_BRACE.sub(rb, s)

    def rs(m):
        nonlocal n
        n += 1
        return f"${n}"

    t = _INTERP_SIMPLE.sub(rs, t)
    return t


def snackbar_body(note: str, source_kind: str) -> str | None:
    if source_kind != "snackbar" or not (note or "").strip():
        return None
    note = note.strip()
    if note.startswith("key=") or note.startswith("line "):
        return None
    if "not a string literal" in note:
        return None
    if "inside Text.rich" in note:
        return None
    return note


def unescape_tsv_field(s: str) -> str:
    return s.replace("\\'", "'").replace("\\n", "\n").replace('\\"', '"')


def english_entry(row: list[str]) -> str:
    sk = row[1]
    label = unescape_tsv_field(row[3] if len(row) > 3 else "")
    note = unescape_tsv_field(row[4] if len(row) > 4 else "")
    body = snackbar_body(note, sk)
    nl = normalize_interpolations(label)
    if body is not None:
        nb = normalize_interpolations(body)
        return f"{nl}{SNACKBAR_SPLIT}{nb}"
    return nl


def load_rows() -> list[list[str]]:
    rows: list[list[str]] = []
    with TSV_PATH.open(encoding="utf-8") as f:
        r = csv.reader(f, delimiter="\t")
        next(r, None)
        for row in r:
            if len(row) < 4:
                continue
            if row[0].startswith("tooltip_"):
                continue
            rows.append(row)
    return rows


def build_en_map() -> dict[str, str]:
    m: dict[str, str] = {}
    for row in load_rows():
        key = row[0]
        if key in m:
            print(f"WARN duplicate key {key}", file=sys.stderr)
        m[key] = english_entry(row)
    return m


def translate_map(en_map: dict[str, str], target: str) -> dict[str, str]:
    try:
        from deep_translator import GoogleTranslator
    except ImportError:
        print("Install: pip install deep-translator", file=sys.stderr)
        sys.exit(1)
    tr = GoogleTranslator(source="en", target=target)
    pieces: set[str] = set()
    for v in en_map.values():
        for part in v.split(SNACKBAR_SPLIT):
            pieces.add(part)
    plist = sorted(pieces)
    mapping: dict[str, str] = {}
    batch = 25
    for i in range(0, len(plist), batch):
        chunk = plist[i : i + batch]
        try:
            translated = tr.translate_batch(chunk)
        except Exception as e:
            print(f"batch translate fail {i}: {e}", file=sys.stderr)
            translated = list(chunk)
        if not translated or len(translated) != len(chunk):
            translated = list(chunk)
        for a, b in zip(chunk, translated):
            mapping[a] = b or a
        time.sleep(0.9)
        print(f"  {target}: pieces {min(i + batch, len(plist))}/{len(plist)}", flush=True)
    out: dict[str, str] = {}
    for k, v in en_map.items():
        if SNACKBAR_SPLIT in v:
            a, b = v.split(SNACKBAR_SPLIT, 1)
            out[k] = mapping.get(a, a) + SNACKBAR_SPLIT + mapping.get(b, b)
        else:
            out[k] = mapping.get(v, v)
    return out


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    en_map = build_en_map()
    with (OUT_DIR / "en.json").open("w", encoding="utf-8") as f:
        json.dump(en_map, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"Wrote en.json ({len(en_map)} keys)")
    if "--translate" not in sys.argv:
        print("Skip es/fr/de (pass --translate to call Google Translate)")
        return
    only = None
    for a in sys.argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].strip().lower()
    targets = [("es", "es"), ("fr", "fr"), ("de", "de")]
    if only:
        targets = [(c, t) for c, t in targets if c == only]
        if not targets:
            print(f"Unknown --only={only}", file=sys.stderr)
            sys.exit(1)
    for code, tgt in targets:
        print(f"Translating -> {code}...")
        loc = translate_map(en_map, tgt)
        with (OUT_DIR / f"{code}.json").open("w", encoding="utf-8") as f:
            json.dump(loc, f, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"Wrote {code}.json")


if __name__ == "__main__":
    main()
