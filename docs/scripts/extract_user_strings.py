#!/usr/bin/env python3
"""
Extract user-visible string literals from lib/ (app, widgets, services, main.dart).
Run from repo root: python3 docs/scripts/extract_user_strings.py
"""
from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass
from typing import List, Optional, Tuple

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIB = os.path.join(REPO, "lib")
LIB_APP = os.path.join(LIB, "app")
LIB_WIDGETS = os.path.join(LIB, "widgets")
LIB_SERVICES = os.path.join(LIB, "services")

SKIP_SUBSTR = (
    "backup",
    "/copy/",
    "_old",
    "map_controller_new copy",
    "temp_screen",
    "globe_test",
    "search_utils_example",
    "searchable_category_widget_examples",
    "map_controller_backup",
    "map_controller_old",
)


def skip_path(path: str) -> bool:
    p = path.replace("\\", "/")
    return any(s in p for s in SKIP_SUBSTR)


def line_number(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def skip_ws(s: str, i: int) -> int:
    while i < len(s) and s[i] in " \t\n\r":
        i += 1
    return i


def skip_optional_const(s: str, i: int) -> int:
    i = skip_ws(s, i)
    if s.startswith("const", i) and (i + 5 == len(s) or not (s[i + 5].isalnum() or s[i + 5] == "_")):
        return skip_ws(s, i + 5)
    return i


def parse_string_literal(s: str, start: int) -> Optional[Tuple[str, int]]:
    """Parse a Dart string starting at or after whitespace from start; returns (value, end_index)."""
    i = skip_optional_const(s, start)
    i = skip_ws(s, i)
    if i >= len(s):
        return None
    # raw
    if s[i] == "r" and i + 1 < len(s) and s[i + 1] in "'\"":
        i += 1
    # triple quoted
    if i + 2 < len(s) and s[i : i + 3] in ("'''", '"""'):
        q = s[i : i + 3]
        j = i + 3
        while j + 2 < len(s):
            if s[j : j + 3] == q:
                return s[i + 3 : j], j + 3
            j += 1
        return None
    q = s[i]
    if q not in "'\"":
        return None
    i += 1
    buf: List[str] = []
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            buf.append(c + s[i + 1])
            i += 2
            continue
        if c == q:
            return "".join(buf), i + 1
        buf.append(c)
        i += 1
    return None


def text_widget_follows(s: str, pos: int) -> bool:
    """True if `title:` / `subtitle:` value is a Text(...) widget, not a string literal."""
    i = skip_ws(s, pos)
    if i < len(s) and s.startswith("const", i) and (
        i + 5 == len(s) or not (s[i + 5].isalnum() or s[i + 5] == "_")
    ):
        i = skip_ws(s, i + 5)
    i = skip_ws(s, i)
    return i < len(s) and s.startswith("Text", i) and (i + 4 == len(s) or s[i + 4] in "(.")


def extract_paren_inner_balanced(s: str, open_paren_index: int) -> Optional[Tuple[str, int]]:
    """From index of '(', return (inner content before matching ')', end index after ')'). Skips strings."""
    if open_paren_index >= len(s) or s[open_paren_index] != "(":
        return None
    depth = 1
    i = open_paren_index + 1
    start = i
    while i < len(s):
        c = s[i]
        if c in "'\"":
            q = c
            if i + 2 < len(s) and s[i : i + 3] == q * 3:
                delim = q * 3
                i += 3
                while i + 2 < len(s):
                    if s[i : i + 3] == delim:
                        i += 3
                        break
                    i += 1
                continue
            i += 1
            while i < len(s):
                if s[i] == "\\" and i + 1 < len(s):
                    i += 2
                    continue
                if s[i] == q:
                    i += 1
                    break
                i += 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return s[start:i], i + 1
        i += 1
    return None


def skip_string_inner_simple(s: str, i: int) -> int:
    """Skip a non-interpolated '...' or \"...\" starting at i."""
    if i >= len(s) or s[i] not in "'\"":
        return i
    q = s[i]
    i += 1
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            i += 2
            continue
        if s[i] == q:
            return i + 1
        i += 1
    return len(s)


def skip_dart_string_with_interpolation(s: str, i: int) -> int:
    """Skip string starting at quote index i; handles '${ ... }' with nested '...' inside."""
    if i >= len(s) or s[i] not in "'\"":
        return i
    q = s[i]
    i += 1
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            i += 2
            continue
        if s[i] == q:
            return i + 1
        if s[i] == "$" and i + 1 < len(s) and s[i + 1] == "{":
            i += 2
            b = 1
            while i < len(s) and b > 0:
                if s[i] in "'\"":
                    i = skip_string_inner_simple(s, i)
                    continue
                if s[i] == "{":
                    b += 1
                elif s[i] == "}":
                    b -= 1
                i += 1
            continue
        i += 1
    return len(s)


def tokenize_get_snackbar_args(inner: str) -> List[str]:
    """Top-level comma args inside Get.snackbar(...); strings may contain '${}'."""
    args: List[str] = []
    i = skip_ws(inner, 0)
    n = len(inner)
    while i < n:
        start = i
        if inner[i] in "'\"":
            end = skip_dart_string_with_interpolation(inner, i)
            args.append(inner[start:end])
            i = skip_ws(inner, end)
        else:
            depth = 0
            while i < n:
                if inner[i] in "'\"":
                    i = skip_dart_string_with_interpolation(inner, i)
                    continue
                if inner[i] == "(":
                    depth += 1
                elif inner[i] == ")":
                    depth -= 1
                elif inner[i] == "," and depth == 0:
                    break
                i += 1
            chunk = inner[start:i].strip()
            if chunk:
                args.append(chunk)
        if i < n and inner[i] == ",":
            i += 1
        i = skip_ws(inner, i)
    return args


def extract_quoted_arg_content(a: str) -> Optional[str]:
    """Content of a leading '...' or \"...\" arg, including \\' and ${...} regions."""
    a = a.strip()
    if not a or a[0] not in "'\"":
        return None
    end = skip_dart_string_with_interpolation(a, 0)
    if end < 2:
        return None
    return a[1 : end - 1]


def snackbar_title_message(inner: str) -> Optional[Tuple[str, str]]:
    """First two string-literal arguments (positional), skipping named params like duration:."""
    str_vals: List[str] = []
    for arg in tokenize_get_snackbar_args(inner):
        a = arg.strip()
        raw = extract_quoted_arg_content(a)
        if raw is None:
            continue
        str_vals.append(raw)
        if len(str_vals) >= 2:
            return str_vals[0], str_vals[1]
    if len(str_vals) == 1:
        return str_vals[0], ""
    return None


def match_in_line_comment(s: str, pos: int) -> bool:
    line_start = s.rfind("\n", 0, pos) + 1
    slash = s.find("//", line_start, pos)
    return slash != -1 and slash < pos


@dataclass
class Row:
    source_kind: str
    rel_path: str
    line: int
    english_label: str
    note: str = ""


def rel_from_abs(path: str) -> str:
    """Path relative to lib/ (unambiguous: app/services/ vs top-level services/)."""
    path = os.path.normpath(path)
    lib = os.path.normpath(LIB)
    if path == os.path.join(lib, "main.dart"):
        return "main.dart"
    return os.path.relpath(path, lib).replace("\\", "/")


def collect_file(path: str) -> List[Row]:
    rel = rel_from_abs(path)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return []
    rows: List[Row] = []

    def add(kind: str, line: int, label: str, note: str = ""):
        if not label or label.isspace():
            return
        rows.append(Row(kind, rel, line, label.replace("\t", " "), note.replace("\t", " ")))

    # Text( '...' or multiline
    for m in re.finditer(r"(?:const\s+)?Text\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            val, _ = parsed
            add("Text", line_number(text, m.start()), val, "")

    for m in re.finditer(r"AutoSizeText\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("AutoSizeText", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"SelectableText\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("SelectableText", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"hintText\s*:\s*", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("hintText", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"tooltip\s*:\s*", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("tooltip", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"label\s*:\s*(?:const\s+)?Text\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("label", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"title\s*:\s*(?:const\s+)?Text\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("title_text", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"subtitle\s*:\s*(?:const\s+)?Text\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("subtitle_text", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"content\s*:\s*(?:const\s+)?Text\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("dialog_content", line_number(text, m.start()), parsed[0], "")

    # SnackBar( ... content: Text('
    for m in re.finditer(r"SnackBar\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        sub = text[m.end() : m.end() + 12000]
        cm = re.search(r"content\s*:\s*(?:const\s+)?Text\s*\(", sub, re.MULTILINE)
        if cm:
            pos = m.end() + cm.end()
            parsed = parse_string_literal(text, pos)
            if parsed:
                add("snackbar_widget", line_number(text, m.start()), parsed[0], "")

    # Get.snackbar — positional first OR named args before strings (balance parens, take first two literals)
    for m in re.finditer(r"Get\.snackbar\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        open_idx = m.end() - 1  # '('
        blk = extract_paren_inner_balanced(text, open_idx)
        if not blk:
            continue
        inner, _ = blk
        ln = line_number(text, m.start())
        sm = snackbar_title_message(inner)
        if sm:
            t, msg = sm
            add(
                "snackbar",
                ln,
                t,
                msg if msg else "(2nd arg not a string literal — check same catch block / ternary)",
            )

    # Text.rich marker + pull inline TextSpan text: '...'
    for m in re.finditer(r"Text\.rich\s*\(", text, re.MULTILINE):
        if match_in_line_comment(text, m.start()):
            continue
        line = line_number(text, m.start())
        add("text_rich", line, "(Text.rich widget)", f"line {line}; scan TextSpan children in {rel}")
        # Heuristic: string after text: (balance parens for Text.rich( ... ) args)
        depth = 1
        i = m.end()
        end_paren = m.end()
        while i < len(text):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    end_paren = i
                    break
            i += 1
        block = text[m.end() : end_paren]
        for tm in re.finditer(r"text\s*:\s*", block):
            parsed = parse_string_literal(block, tm.end())
            if parsed:
                add("text_span", line, parsed[0], "inside Text.rich")

    # title: '...' / subtitle: '...' (not Text widget) — e.g. Get.defaultDialog, ListTile, ExpansionTile
    for m in re.finditer(r"\btitle\s*:\s*", text):
        if match_in_line_comment(text, m.start()):
            continue
        if text_widget_follows(text, m.end()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("title_literal", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"\bsubtitle\s*:\s*", text):
        if match_in_line_comment(text, m.start()):
            continue
        if text_widget_follows(text, m.end()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("subtitle_literal", line_number(text, m.start()), parsed[0], "")

    for m in re.finditer(r"\bsemanticLabel\s*:\s*", text):
        if match_in_line_comment(text, m.start()):
            continue
        parsed = parse_string_literal(text, m.end())
        if parsed:
            add("semanticLabel", line_number(text, m.start()), parsed[0], "")

    # Dynamic hints (explicit)
    # (handled in post: static list merged)

    return rows


# Explicit dynamic / non-literal rows (must not be empty)
DYNAMIC_ROWS = [
    Row("hint_dynamic", "app/shared/widgets/searchable_category_widget.dart", 758, "hintText ← widget.title", "Caller passes title"),
    Row("hint_dynamic", "app/shared/widgets/searchable_contact_widget.dart", 538, "hintText ← widget.title", "Caller passes title"),
    Row("hint_dynamic", "app/shared/widgets/searchable_hashtag_widget.dart", 543, "hintText ← widget.title", "Caller passes title"),
    Row("hint_dynamic", "app/modules/map/views/mini_widgets/filter_fields.dart", 104, "hintText ← hint variable", "Parent supplies hint"),
    Row("hint_dynamic", "app/modules/add_memories/views/mini_widgets/filter_fileds.dart", 412, "hintText ← widget.hint", "Per-field hint"),
    Row("hint_dynamic", "app/modules/add_memories/views/mini_widgets/filter_dropdown.dart", 212, "hintText ← widget.hint", "From filter config"),
    Row("hint_dynamic", "app/shared/widgets/add_edit_group_popup.dart", 216, "hintText ← widget.isMainGroup (ternary)", "See file"),
    Row("hint_dynamic", "app/shared/widgets/add_edit_group_pop_new.dart", 1976, "hintText ← widget.isMainCategory (ternary)", "See file"),
    Row("hint_dynamic", "app/shared/widgets/add_place_category_popup.dart", 1159, "Place Category | Place Name", "widget.isMainCategory"),
    Row("hint_dynamic", "app/shared/widgets/add_place_category_popup.dart", 2322, "Place Category | Place Name", "widget.isMainCategory"),
    Row("hint_dynamic", "app/modules/memories/views/mini_widgets/mention_bottom_sheet_widget.dart", 1541, "Enter new Hashtag Group name | Enter new Contact Group name", "widget.isTagMode"),
    Row("param_dialog", "app/shared/widgets/permission_open_settings_dialog.dart", 8, "title, message ← caller", "showPermissionOpenSettingsDialog(context, title:, message:)"),
    # Second Get.snackbar arg is variable `message` (ternary above); capture literal branches
    Row(
        "snackbar_message_branch",
        "app/modules/memories/views/mini_widgets/mention_bottom_sheet_widget.dart",
        1096,
        "Hashtag Group with this name already exists.",
        "DUPLICATE_HASHTAG_NAME snackbar when editParentId==null",
    ),
    Row(
        "snackbar_message_branch",
        "app/modules/memories/views/mini_widgets/mention_bottom_sheet_widget.dart",
        1097,
        "Hashtag with this name already exists.",
        "DUPLICATE_HASHTAG_NAME snackbar when editParentId!=null",
    ),
    Row(
        "snackbar_message_branch",
        "app/modules/memories/views/mini_widgets/mention_bottom_sheet_widget.dart",
        1129,
        "Contact Group with this name already exists.",
        "DUPLICATE_CONTACT_NAME when editParentId==null",
    ),
    Row(
        "snackbar_message_branch",
        "app/modules/memories/views/mini_widgets/mention_bottom_sheet_widget.dart",
        1130,
        "Contact with this name already exists.",
        "DUPLICATE_CONTACT_NAME when editParentId!=null",
    ),
]


def main() -> int:
    all_rows: List[Row] = []
    for root_dir in (LIB_APP, LIB_WIDGETS, LIB_SERVICES):
        if not os.path.isdir(root_dir):
            continue
        for dirpath, _, files in os.walk(root_dir):
            for f in files:
                if not f.endswith(".dart"):
                    continue
                path = os.path.join(dirpath, f)
                if skip_path(path):
                    continue
                all_rows.extend(collect_file(path))

    main_dart = os.path.join(LIB, "main.dart")
    if os.path.isfile(main_dart) and not skip_path(main_dart):
        all_rows.extend(collect_file(main_dart))

    all_rows.extend(DYNAMIC_ROWS)

    # AppTexts + supported_languages as fixed rows
    app_texts = os.path.join(LIB_APP, "config", "app_text.dart")
    if os.path.isfile(app_texts):
        t = open(app_texts, encoding="utf-8").read()
        for m in re.finditer(r"static const String\s+(\w+)\s*=\s*['\"]([^'\"]*)['\"]", t):
            line = line_number(t, m.start())
            all_rows.append(Row("AppTexts", "app/config/app_text.dart", line, m.group(2), f"key={m.group(1)}"))

    sup = os.path.join(LIB_APP, "config", "supported_languages.dart")
    if os.path.isfile(sup):
        t = open(sup, encoding="utf-8").read()
        for m in re.finditer(
            r"SupportedLanguage\s*\(\s*code:\s*['\"]([^'\"]+)['\"]\s*,\s*nativeName:\s*['\"]([^'\"]*)['\"]",
            t,
        ):
            line = line_number(t, m.start())
            all_rows.append(
                Row(
                    "supported_language",
                    "app/config/supported_languages.dart",
                    line,
                    m.group(2),
                    f"code={m.group(1)}",
                )
            )

    # Dedupe: exact row
    seen = set()
    uniq: List[Row] = []
    for r in all_rows:
        k = (r.source_kind, r.rel_path, r.line, r.english_label, r.note)
        if k in seen:
            continue
        seen.add(k)
        uniq.append(r)

    # One row per (file, line, same string): prefer structured kinds over bare Text(...)
    prio = {
        "dialog_content": 0,
        "title_text": 1,
        "subtitle_text": 2,
        "snackbar_widget": 3,
        "Text": 10,
    }
    grouped: dict = {}
    rest: List[Row] = []
    for r in uniq:
        p = prio.get(r.source_kind)
        if p is None:
            rest.append(r)
            continue
        key = (r.rel_path, r.line, r.english_label)
        if key not in grouped:
            grouped[key] = r
        elif prio[r.source_kind] < prio[grouped[key].source_kind]:
            grouped[key] = r
    uniq = rest + list(grouped.values())

    uniq.sort(key=lambda r: (r.rel_path, r.line, r.source_kind, r.english_label))

    from collections import defaultdict

    slug_counts: defaultdict = defaultdict(int)

    def proposed_key(r: Row) -> str:
        base = re.sub(r"[^a-z0-9]+", "_", (r.source_kind + "_" + r.english_label).lower())[:56].strip("_")
        slug_counts[base] += 1
        n = slug_counts[base]
        return f"{base}_{n}" if n > 1 else base

    out_path = os.path.join(REPO, "docs", "user_visible_strings.tsv")
    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.write("proposed_key\tsource_kind\tfile:line\tenglish_label\tnote\n")
        for r in uniq:
            pk = proposed_key(r)
            f.write(
                f"{pk}\t{r.source_kind}\t{r.rel_path}:{r.line}\t{r.english_label}\t{r.note}\n"
            )

    print(f"Wrote {len(uniq)} rows to {out_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
