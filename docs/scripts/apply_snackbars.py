#!/usr/bin/env python3
"""Replace Get.snackbar('t','m', with showTrSnackbar('key', using assets/l10n/en.json + TSV line hints."""
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

SKIP = ("map_controller_new copy", "/copy/", "_old", "globe_test")

SNACK = "@@@"


def unescape_tsv_field(s: str) -> str:
    return s.replace("\\'", "'").replace("\\n", "\n").replace('\\"', '"')


def dart_unescape(inner: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(inner):
        if inner[i] == "\\" and i + 1 < len(inner):
            c = inner[i + 1]
            if c == "n":
                out.append("\n")
            elif c == "r":
                out.append("\r")
            elif c == "t":
                out.append("\t")
            elif c in "'\"\\":
                out.append(c)
            else:
                out.append(inner[i : i + 2])
            i += 2
        else:
            out.append(inner[i])
            i += 1
    return "".join(out)


def normalize_interps(s: str) -> str:
    n = 0

    def rb(m):
        nonlocal n
        n += 1
        return f"${n}"

    t = re.sub(r"\$\{[^}]+\}", rb, s)

    def rs(m):
        nonlocal n
        n += 1
        return f"${n}"

    return re.sub(r"\$[a-zA-Z_][a-zA-Z0-9_]*", rs, t)


def extract_dart_string_from(text: str, start: int) -> tuple[str, int] | None:
    i = start
    while i < len(text) and text[i] in " \t\n\r":
        i += 1
    if i >= len(text) or text[i] not in "'\"":
        return None
    q = text[i]
    j = i + 1
    buf: list[str] = []
    while j < len(text):
        c = text[j]
        if c == "\\" and j + 1 < len(text):
            buf.append(text[j : j + 2])
            j += 2
        elif c == q:
            lit = text[i : j + 1]
            return lit, j + 1
        else:
            buf.append(c)
            j += 1
    return None


def find_call_end(text: str, open_paren: int) -> int:
    depth = 0
    j = open_paren
    in_s = False
    sq = ""
    while j < len(text):
        c = text[j]
        if in_s:
            if c == "\\" and j + 1 < len(text):
                j += 2
                continue
            if c == sq:
                in_s = False
            j += 1
            continue
        if c in "'\"":
            in_s = True
            sq = c
            j += 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


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


def load_snackbar_rows() -> list[dict]:
    rows: list[dict] = []
    with TSV.open(encoding="utf-8") as f:
        r = csv.reader(f, delimiter="\t")
        next(r, None)
        for row in r:
            if len(row) < 4:
                continue
            if row[0].startswith("tooltip_"):
                continue
            if row[1] != "snackbar":
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
                    "note": unescape_tsv_field(row[4] if len(row) > 4 else ""),
                }
            )
    return rows


def resolve_path(rel: str) -> Path | None:
    candidates = [LIB / rel, LIB.parent / rel]
    for c in candidates:
        if c.is_file():
            return c
    return None


def ensure_import(text: str) -> str:
    imp = "import 'package:spacetime/app/l10n/l10n_loader.dart';"
    if imp in text:
        return text
    lines = text.splitlines(keepends=True)
    insert_at = 0
    for i, ln in enumerate(lines):
        if ln.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, imp + "\n")
    return "".join(lines)


def skip_file(p: Path) -> bool:
    t = str(p).replace("\\", "/")
    return any(s in t for s in SKIP)


def main() -> int:
    en = json.loads(EN.read_text(encoding="utf-8"))
    rows = load_snackbar_rows()
    n_ok = 0
    for row in rows:
        key = row["key"]
        val = en.get(key)
        if val is None or SNACK not in val:
            continue
        title_en, body_en = val.split(SNACK, 1)
        title_n = normalize_interps(title_en)
        body_n = normalize_interps(body_en)
        p = resolve_path(row["file"])
        if p is None or skip_file(p):
            continue
        text = p.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        nlines = len(lines)
        ln_idx = max(0, min(row["line"] - 1, max(0, nlines - 1)))
        line_byte = sum(len(lines[i]) for i in range(ln_idx))

        def try_replace_in(scope: str, offset: int) -> tuple[str, bool]:
            pos = 0
            best: tuple[int, int, str] | None = None
            best_dist = 10**9
            while True:
                idx = scope.find("Get.snackbar", pos)
                if idx < 0:
                    break
                lp = scope.find("(", idx)
                if lp < 0:
                    pos = idx + 1
                    continue
                end_rel = find_call_end(scope, lp)
                if end_rel < 0:
                    pos = idx + 1
                    continue
                inner = scope[lp + 1 : end_rel]
                s1 = extract_dart_string_from(inner, 0)
                if s1 is None:
                    pos = idx + 1
                    continue
                _, after1 = s1
                while after1 < len(inner) and inner[after1] in " \t\n\r,":
                    after1 += 1
                s2 = extract_dart_string_from(inner, after1)
                if s2 is None:
                    pos = idx + 1
                    continue
                lit1, _e1 = s1
                lit2, end2 = s2
                t1 = normalize_interps(dart_unescape(lit1[1:-1]))
                t2 = normalize_interps(dart_unescape(lit2[1:-1]))
                if t1 != title_n or t2 != body_n:
                    pos = idx + 1
                    continue
                abs_idx = offset + idx
                dist = abs(abs_idx - line_byte)
                if dist < best_dist:
                    raw2_un = dart_unescape(lit2[1:-1])
                    vars_pat = re.findall(
                        r"\$\{([^}]+)\}|\$([a-zA-Z_][a-zA-Z0-9_]*)", raw2_un
                    )
                    exprs = [a or b for a, b in vars_pat]
                    tail = inner[end2:].lstrip()
                    if tail.startswith(","):
                        tail = tail[1:]
                    tail = tail.rstrip()
                    if exprs:
                        argstr = ", ".join(exprs)
                        new_call = f"showTrSnackbar('{key}', args: [{argstr}]"
                    else:
                        new_call = f"showTrSnackbar('{key}'"
                    if tail:
                        new_call += ", " + tail
                    new_call += ")"
                    best = (idx, end_rel + 1, new_call)
                    best_dist = dist
                pos = idx + 1
            if best is None:
                return scope, False
            idx, end_excl, new_call = best
            return scope[:idx] + new_call + scope[end_excl:], True

        lo = max(0, ln_idx - 8)
        hi = min(nlines, ln_idx + 40)
        chunk = "".join(lines[lo:hi])
        off = sum(len(lines[i]) for i in range(lo))
        new_chunk, replaced = try_replace_in(chunk, off)
        if not replaced:
            new_text, replaced = try_replace_in(text, 0)
            if replaced:
                new_text = ensure_import(new_text)
                p.write_text(new_text, encoding="utf-8")
                n_ok += 1
                print("patched(full)", key, p.relative_to(REPO))
            continue
        new_text = "".join(lines[:lo]) + new_chunk + "".join(lines[hi:])
        new_text = ensure_import(new_text)
        p.write_text(new_text, encoding="utf-8")
        n_ok += 1
        print("patched", key, p.relative_to(REPO))
    print("snackbar files patched:", n_ok)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
