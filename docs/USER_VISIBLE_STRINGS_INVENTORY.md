# User-visible strings inventory (labels, `Text`, hints)

## Files

| File | Contents |
|------|----------|
| **`docs/user_visible_strings.tsv`** | **880 data rows** + header. Columns: `proposed_key`, `source_kind`, `file:line`, `english_label`, `note`. |
| **`docs/scripts/extract_user_strings.py`** | Regenerates the TSV — run: `python3 docs/scripts/extract_user_strings.py` from the repo root. |

### Path column (`file:line`)

Every path is **relative to `lib/`** (prepend `lib/` for the full file path):

| Prefix | Directory |
|--------|-----------|
| `app/…` | `lib/app/…` |
| `widgets/…` | `lib/widgets/…` |
| `services/…` | `lib/services/…` |
| `main.dart` | `lib/main.dart` |

## `AppTexts` — `lib/app/config/app_text.dart`

| Proposed key (use `AppTexts` name or `app_<name>`) | Label | Line |
|----------------------------------------------------|-------|------|
| `settings` | Settings | 3 |
| `security` | Security | 4 |
| `ui` | Ui | 5 |
| `data` | Data | 6 |
| `hashTagGroups` | Hashtag Groups | 7 |
| `contactGroups` | Contact Groups | 8 |
| `places` | Places | 9 |
| `feedBack` | Feedback | 10 |
| `activePhoneVerification` | Active phone verification pin | 13 |
| `language` | Language | 16 |
| `eng` | (English) | 17 |
| `darkMode` | Dark Mode | 18 |
| `mainColor` | Main Color | 19 |
| `blue` | (blue) | 20 |
| `uploadGPS` | Upload GPS Points | 23 |
| `uploadMedia` | Upload Media with GPS | 24 |
| `backupMemories` | Backup Memories | 25 |
| `uploadMemories` | Upload Memories | 26 |
| `eraseAllData` | Erase All Data | 27 |
| `sport` | Sport | 30 |
| `exercise` | Exercise | 31 |
| `family` | Family | 34 |
| `homes` | Homes | 35 |
| `discoverIntegration` | Discourse integration (webview) | 38 |
| `web` | https://discourse.org/ | 39 |

*(The TSV also lists each `AppTexts` value as rows with `source_kind` = `AppTexts`.)*

## Language display names — `lib/app/config/supported_languages.dart`

| Code | Label (native name) | Line |
|------|---------------------|------|
| en | English | 14 |
| es | Español | 15 |
| fr | Français | 16 |
| de | Deutsch | 17 |
| zh | 中文 | 18 |
| ur | اردو | 19 |

*(Also in the TSV as `source_kind` = `supported_language`.)*

## What the extractor includes (same TSV)

Scans **`lib/app/`**, **`lib/widgets/`**, **`lib/services/`**, and **`lib/main.dart`**, skipping backups/copies/old controllers/examples (`*backup*`, `*_old*`, `lib/copy/`, `globe_test`, `*_example*.dart`, `temp_screen`, `map_controller_new copy`, etc.).

| `source_kind` | Meaning |
|---------------|---------|
| `Text` | Literal inside `Text('…')` / `const Text('…')` (incl. multiline string after `(`). |
| `title_text` / `subtitle_text` | `title:` / `subtitle:` followed by `Text('…')`. |
| `title_literal` / `subtitle_literal` | `title:` / `subtitle:` string args (e.g. `Get.defaultDialog`, `ListTile`), **not** a `Text` widget. |
| `dialog_content` | `content: Text('…')` / `const Text('…')` (incl. multiline). |
| `hintText` | `hintText: '…'`. |
| `tooltip` | `tooltip: '…'`. |
| `label` | `label: Text('…')` / `const Text('…')`. |
| `semanticLabel` | `semanticLabel: '…'`. |
| `AutoSizeText` | `AutoSizeText('…')` (literal only; variables are skipped). |
| `SelectableText` | `SelectableText('…')` when present. |
| `snackbar` | `Get.snackbar(...)` — tokenizes args (named args like `duration:` allowed); **`note`** = second string or placeholder if the 2nd arg is a variable. |
| `snackbar_message_branch` | Literal strings used as the snackbar **body** when the 2nd argument is a variable (e.g. ternary `message`). |
| `snackbar_widget` | `SnackBar(… content: Text('…')` within the next ~12k chars. |
| `text_rich` | Marker for each `Text.rich(`; **`text_span`** rows pull `TextSpan` `text: '…'` in that block. |
| `hint_dynamic` / `param_dialog` | Hand-listed dynamic/caller-driven UI copy (see `note`). |
| `AppTexts` / `supported_language` | Central config files (duplicates literal text used in UI). |

Duplicate **same file + line + same string** from both `Text(` and `dialog_content` / `title_text` is collapsed to the more specific kind.

## Not represented as fixed literals (verify manually)

- **`Text(variable)`** / **`Text(message)`** where the string is **only** a parameter (e.g. `showDeleteConfirmationDialog` title/message, `Get.defaultDialog` with variables).
- **Platform / native** strings, **method channels**, **notifications** not built in Dart UI.
- **WebView** remote HTML; **AutoSizeText(variable)** (DB-driven labels).
- **`DropdownMenuItem`** when `child:` is not a literal `Text('…')`.
- **`test/`** (not scanned).

Absolute completeness isn’t possible for dynamic UI; the script plus **`snackbar_message_branch`** / **`hint_dynamic`** / **`param_dialog`** rows cover the usual gaps. Re-run `extract_user_strings.py` after UI changes.
