#!/usr/bin/env python3
"""
Pass 1: replace static literals that appear exactly once in lib/ (match en.json value).
Pass 2: for remaining static keys, use TSV file:line to replace first match in a window.
Skips tooltip_ keys and values with @@@ or $N placeholders.
"""
from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "lib"
TSV = REPO / "docs" / "user_visible_strings.tsv"
EN = REPO / "assets" / "l10n" / "en.json"

SKIP_PATH_PARTS = (
    "map_controller_new copy",
    "/copy/",
    "_old",
    "globe_test",
    "map_controller_backup",
    "map_controller_old",
)

PLACEHOLDER = re.compile(r"\$\d+")


def unescape_tsv_field(s: str) -> str:
    return s.replace("\\'", "'").replace("\\n", "\n").replace('\\"', '"')


def dart_sq(s: str) -> str:
    return "'" + s.replace("\\", r"\\").replace("'", r"\'").replace("\n", r"\n").replace("\r", r"\r") + "'"


def dart_dq(s: str) -> str:
    return '"' + s.replace("\\", r"\\").replace('"', r"\"").replace("\n", r"\n").replace("\r", r"\r") + '"'


def skip_path(p: Path) -> bool:
    t = str(p).replace("\\", "/")
    return any(x in t for x in SKIP_PATH_PARTS)


def load_tsv_rows() -> list[dict]:
    rows: list[dict] = []
    with TSV.open(encoding="utf-8") as f:
        r = csv.reader(f, delimiter="\t")
        next(r, None)
        for row in r:
            if len(row) < 4:
                continue
            if row[0].startswith("tooltip_"):
                continue
            loc = row[2]
            if ":" not in loc:
                continue
            fp, _, ln = loc.rpartition(":")
            try:
                line_no = int(ln)
            except ValueError:
                continue
            rows.append(
                {
                    "key": row[0],
                    "file": fp,
                    "line": line_no,
                    "label": unescape_tsv_field(row[3]),
                }
            )
    return rows


def is_static_value(v: str) -> bool:
    return "@@@" not in v and not PLACEHOLDER.search(v)


def strip_const_text_line(line: str) -> str:
    return line.replace("const Text(", "Text(")


def replace_once_in_text(text: str, old: str, new: str) -> tuple[str, bool]:
    if old not in text:
        return text, False
    idx = text.find(old)
    if text.find(old, idx + 1) >= 0:
        return text, False
    text = text[:idx] + new + text[idx + len(old) :]
    line_start = text.rfind("\n", 0, idx) + 1
    line_end = text.find("\n", idx)
    if line_end < 0:
        line_end = len(text)
    line = text[line_start:line_end]
    if "const Text(" in line and ".tr" in new:
        line2 = strip_const_text_line(line)
        text = text[:line_start] + line2 + text[line_end:]
    return text, True


def pass1(en_map: dict[str, str], files: list[Path]) -> tuple[int, set[str]]:
    done: set[str] = set()
    n = 0
    for key, val in en_map.items():
        if not is_static_value(val):
            continue
        sq, dq = dart_sq(val), dart_dq(val)
        hits: list[tuple[Path, str]] = []
        for fp in files:
            t = fp.read_text(encoding="utf-8")
            cs, cd = t.count(sq), t.count(dq)
            if cs:
                hits.extend([(fp, sq)] * cs)
            if cd:
                hits.extend([(fp, dq)] * cd)
        if len(hits) != 1:
            continue
        (hit_file, hit_quote) = hits[0]
        text = hit_file.read_text(encoding="utf-8")
        new_t, ok = replace_once_in_text(text, hit_quote, f"'{key}'.tr")
        if ok:
            hit_file.write_text(new_t, encoding="utf-8")
            done.add(key)
            n += 1
    return n, done


def pass2(rows: list[dict], en_map: dict[str, str], done: set[str], files_by_path: dict[str, Path]) -> int:
    n = 0
    for row in rows:
        key = row["key"]
        if key in done:
            continue
        val = en_map.get(key)
        if val is None or not is_static_value(val):
            continue
        rel = row["file"]
        p = files_by_path.get(rel)
        if p is None:
            continue
        lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
        lo = max(0, row["line"] - 1 - 15)
        hi = min(len(lines), row["line"] - 1 + 16)
        window = "".join(lines[lo:hi])
        sq, dq = dart_sq(val), dart_dq(val)
        choice = None
        if sq in window:
            choice = sq
        elif dq in window:
            choice = dq
        if choice is None:
            continue
        joined = "".join(lines)
        wstart = sum(len(lines[i]) for i in range(lo))
        wend = wstart + len(window)
        win = joined[wstart:wend]
        if win.count(choice) != 1:
            continue
        new_j, ok = replace_once_in_text(joined, choice, f"'{key}'.tr")
        if ok:
            p.write_text(new_j, encoding="utf-8")
            done.add(key)
            n += 1
    return n


def main() -> int:
    en_map = json.loads(EN.read_text(encoding="utf-8"))
    files = [p for p in LIB.rglob("*.dart") if p.is_file() and not skip_path(p)]
    files_by_path: dict[str, Path] = {}
    for p in files:
        try:
            rel = p.relative_to(LIB).as_posix()
        except ValueError:
            continue
        files_by_path[rel] = p

    rows = load_tsv_rows()
    dry = "--dry-run" in sys.argv
    if dry:
        print("dry-run: no writes")
        return 0

    n1, done = pass1(en_map, files)
    print(f"pass1 replacements: {n1}")
    n2 = pass2(rows, en_map, done, files_by_path)
    print(f"pass2 replacements: {n2}")
    static_keys = {k for k, v in en_map.items() if is_static_value(v)}
    missing = sorted(static_keys - done)
    print(f"static keys still not applied: {len(missing)}")
    if missing[:40]:
        print("sample:", missing[:40])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
