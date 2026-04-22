"""Shared TSV/en.json helpers for l10n scripts."""
from __future__ import annotations

import csv
import re
from pathlib import Path

SNACKBAR_SPLIT = "@@@"
REPO = Path(__file__).resolve().parents[2]
TSV_PATH = REPO / "docs" / "user_visible_strings.tsv"

_INTERP_BRACE = re.compile(r"\$\{[^}]+\}")
_INTERP_SIMPLE = re.compile(r"\$[a-zA-Z_][a-zA-Z0-9_]*")


def unescape_tsv_field(s: str) -> str:
    return s.replace("\\'", "'").replace("\\n", "\n").replace('\\"', '"')


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

    return _INTERP_SIMPLE.sub(rs, t)


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


def dart_sq(s: str) -> str:
    return "'" + s.replace("\\", r"\\").replace("'", r"\'").replace("\n", r"\n").replace("\r", r"\r") + "'"


def dart_dq(s: str) -> str:
    return '"' + s.replace("\\", r"\\").replace('"', r"\"").replace("\n", r"\n").replace("\r", r"\r") + '"'


def load_tsv_rows_raw() -> list[list[str]]:
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


def parse_file_line(cell: str) -> tuple[str, int] | None:
    if ":" not in cell:
        return None
    fp, _, ln = cell.rpartition(":")
    try:
        return fp, int(ln)
    except ValueError:
        return None


def resolve_lib_path(rel_file: str) -> Path | None:
    lib = REPO / "lib"
    p = lib / rel_file
    if p.is_file():
        return p
    if rel_file == "main.dart" and (lib / "main.dart").is_file():
        return lib / "main.dart"
    return None
