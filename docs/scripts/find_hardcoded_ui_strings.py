#!/usr/bin/env python3
"""
Scan Dart sources for likely hardcoded user-visible strings (popups, labels, hints).

Heuristic line-based scan — expect false positives (debugPrint, regex, routes) and
some false negatives (multi-line Text). Use with code review.

Usage:
  python3 docs/scripts/find_hardcoded_ui_strings.py
  python3 docs/scripts/find_hardcoded_ui_strings.py --root lib/app --min-len 4
  python3 docs/scripts/find_hardcoded_ui_strings.py --json docs/hardcoded_ui_strings.json

Output default: docs/hardcoded_ui_strings.tsv
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Skip paths matching any of these substrings
DEFAULT_EXCLUDE_SUBSTR = (
    "backup.dart",
    "_old.dart",
    " copy.dart",
    "/copy/",
    "_examples.dart",
    "example_usage",
    "search_utils_example",
    "temp_screen.dart",
    "globe_test_view.dart",
)

# Widget / API names that usually wrap user-facing copy
CONTEXT_REGEX = re.compile(
    r"\b(Text|RichText|hintText|label|tooltip|semanticLabel|"
    r"title|subtitle|message|helperText|counterText|errorText|"
    r"placeholder|AppBar|SnackBar|Get\.snackbar|ListTile)\b",
    re.I,
)

# Single-line string after opening paren or after "name:"
STRING_PATTERNS = [
    # Text( '...' ) or Text( "..." ) — same line only
    (
        "Text_string",
        re.compile(
            r"\bText\s*\(\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))\s*[,)]"
        ),
    ),
    (
        "hintText_string",
        re.compile(
            r"hintText\s*:\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
    (
        "label_string",
        re.compile(
            r"\blabel\s*:\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
    (
        "tooltip_string",
        re.compile(
            r"tooltip\s*:\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
    (
        "title_string",
        re.compile(
            r"\btitle\s*:\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
    (
        "subtitle_string",
        re.compile(
            r"\bsubtitle\s*:\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
    (
        "message_string",
        re.compile(
            r"\bmessage\s*:\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
    (
        "Get_snackbar_string",
        re.compile(
            r"Get\.snackbar\s*\(\s*((?:'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"))"
        ),
    ),
]


def strip_quotes(s: str) -> str:
    if len(s) >= 2 and s[0] in "'\"" and s[0] == s[-1]:
        return s[1:-1]
    return s


def unescape_dart_string(s: str) -> str:
    return (
        s.replace(r"\'", "'")
        .replace(r"\"", '"')
        .replace(r"\n", "\n")
        .replace(r"\t", "\t")
    )


def should_skip_line(line: str) -> bool:
    t = line.strip()
    if not t or t.startswith("//"):
        return True
    if ".tr" in line or "trKey(" in line or "showTrSnackbar(" in line:
        return True
    if "Text.rich" in line or "TextSpan(" in line:
        return True
    return False


def is_likely_user_string(inner: str, min_len: int) -> bool:
    if len(inner) < min_len:
        return False
    if not re.search(r"[A-Za-z]", inner):
        return False
    # Dart string interpolation
    if re.search(r"\$\{|\$[a-zA-Z_]", inner):
        return False
    if inner.startswith("assets/") or inner.startswith("packages/"):
        return False
    if inner.startswith("http://") or inner.startswith("https://"):
        return False
    # common non-UI
    if inner.startswith("lib/") or inner.endswith(".dart"):
        return False
    return True


def scan_file(path: Path, min_len: int) -> list[dict]:
    rel = path.relative_to(REPO)
    rows: list[dict] = []
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return rows
    for lineno, line in enumerate(text.splitlines(), start=1):
        if should_skip_line(line):
            continue
        if not CONTEXT_REGEX.search(line):
            continue
        for kind, rx in STRING_PATTERNS:
            for m in rx.finditer(line):
                raw = m.group(1)
                inner = unescape_dart_string(strip_quotes(raw))
                if not is_likely_user_string(inner, min_len):
                    continue
                rows.append(
                    {
                        "file": str(rel).replace("\\", "/"),
                        "line": lineno,
                        "kind": kind,
                        "preview": inner[:200] + ("…" if len(inner) > 200 else ""),
                        "raw": raw[:120],
                    }
                )
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="Find hardcoded UI strings in Dart.")
    ap.add_argument(
        "--root",
        default="lib/app",
        help="Directory under repo root to scan (default: lib/app)",
    )
    ap.add_argument("--min-len", type=int, default=4, help="Min string length")
    ap.add_argument(
        "--out-tsv",
        default="docs/hardcoded_ui_strings.tsv",
        help="Output TSV path (under repo)",
    )
    ap.add_argument(
        "--json",
        dest="json_path",
        default="",
        help="Also write JSON array to this path (under repo)",
    )
    ap.add_argument(
        "--include-tooltips",
        action="store_true",
        help="Include tooltip: ... hits (omitted by default; tooltips stay English)",
    )
    args = ap.parse_args()

    root = (REPO / args.root).resolve()
    if not root.is_dir():
        print(f"Not a directory: {root}", file=sys.stderr)
        return 1

    all_rows: list[dict] = []
    for path in sorted(root.rglob("*.dart")):
        sp = str(path)
        if any(x in sp for x in DEFAULT_EXCLUDE_SUBSTR):
            continue
        all_rows.extend(scan_file(path, args.min_len))

    if not args.include_tooltips:
        all_rows = [r for r in all_rows if r["kind"] != "tooltip_string"]

    out_tsv = REPO / args.out_tsv
    out_tsv.parent.mkdir(parents=True, exist_ok=True)
    with out_tsv.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["file", "line", "kind", "preview", "raw"])
        w.writeheader()
        for r in sorted(all_rows, key=lambda x: (x["file"], x["line"], x["kind"])):
            w.writerow(r)

    if args.json_path:
        out_json = REPO / args.json_path
        out_json.parent.mkdir(parents=True, exist_ok=True)
        out_json.write_text(json.dumps(all_rows, indent=2), encoding="utf-8")

    print(f"Wrote {out_tsv} — {len(all_rows)} hits (heuristic)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
