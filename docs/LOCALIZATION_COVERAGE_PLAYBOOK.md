# Localization coverage playbook — verification, GetX, and execution tiers

Companion to **`LOCALIZATION_PLAN.md`**. This document defines **how we prove** hardcoded user-facing strings are gone (or intentionally exempt), **how to handle GetX controllers and snackbars**, and **tiered “skill levels”** for systematic execution (human or AI).

---

## Part A — How we ensure hardcoded strings are replaced

### A1. Single definition of “done”

A string counts as **migrated** when:

1. It is **user-visible** (UI label, dialog, snackbar, validation, button, accessibility `semanticsLabel` if used).
2. It lives in **`app_en.arb`** (template) with a **stable key**, and other locales mirror the same keys.
3. Code references **`AppLocalizations`** (or a thin wrapper) — **not** a raw English literal in `lib/app/` production paths.

**Explicitly exempt** (do not translate in ARB):

- `debugPrint` / `print` / internal logs
- Preference keys, JSON keys, route names, asset paths, env keys
- User-generated content (memory text, user-created category names)
- Third-party URLs unchanged

### A2. Baseline inventory (before migration)

1. Run the **inventory scripts** from `LOCALIZATION_PLAN.md` (section 4) and save output to `docs/l10n_inventory_baseline.txt` (or a spreadsheet).
2. Count **unique** English fragments; that number is the **baseline debt**.

### A3. Gates during migration (prevent regression)

| Gate | Purpose |
|------|--------|
| **`flutter gen-l10n`** in CI | Fails if ARB files are invalid or keys mismatch template. |
| **Missing translation check** | Script: every key in `app_en.arb` exists in each `app_*.arb` (allow `@@locale` only in template). |
| **Forbidden pattern lint (optional)** | Custom lint or CI `rg` step: block new `Text('` with ASCII letters in `lib/app/` — **allow-list** files until migrated. |
| **PR checklist** | “No new raw user strings in touched files.” |

### A4. “Done” verification (after each milestone)

1. **Automated:** `rg` for high-risk patterns in **migrated** trees should return **zero** matches (or only allow-listed lines documented in `docs/l10n_allowlist.txt`).
2. **Manual:** Switch locale in app; walk **smoke checklist** (Settings → Memory → Map → Get Started).
3. **Snapshot (optional):** Golden tests for 2–3 critical screens per locale.

### A5. Final sign-off criteria

- Baseline inventory items are **closed** or **marked exempt** with reason.
- CI green on gen-l10n + key parity.
- Product owner accepts **category behavior** (section 5 of main plan).

---

## Part B — GetX, controllers, snackbars, dialogs

### B1. Problem

`AppLocalizations.of(context)` needs a **`BuildContext`**. GetX **controllers** often have **no context** when calling `Get.snackbar`, `Get.dialog`, or setting `statusText`.

### B2. Rules (pick one strategy and enforce it)

| Strategy | When to use | How |
|----------|-------------|-----|
| **A. Pass strings from the View** | Controller only triggers actions; UI owns copy | `controller.showError(AppLocalizations.of(context)!.saveFailed)` or pass `String Function(AppLocalizations l10n)` |
| **B. Root navigator / overlay context** | Rare centralized errors | `Get.key.currentContext` after `GetMaterialApp` is built — fragile; use sparingly. |
| **C. Locale + `lookupAppLocalizations`** | Services that must format messages without widget | Use `lookupAppLocalizations(Locale('en'))` from generated `app_localizations.dart` (Flutter 3.16+ pattern) with **injected locale** from `Get.find<LocaleService>()`. |
| **D. Thin `Messages` / `Strings` facade** | Bridge phase | Single class that wraps generated l10n getters; locale from one place. |

**Recommendation:** **A** for most GetX controllers; **C** only for deep services once `Locale` is stored globally.

### B3. Snackbars and dialogs — standardize

1. Add **two helpers** (names illustrative):
   - `showAppSnackBar(BuildContext? ctx, String message)` — prefers `ScaffoldMessenger` if `ctx` given, else `Get.snackbar` with localized `message` passed in.
   - `showAppDialog(...)` — same idea: **caller supplies already-localized strings**.

2. **Do not** embed English inside controllers:
   - Bad: `Get.snackbar('Error', 'Failed to save');`
   - Good: `Get.snackbar(l10n.errorTitle, l10n.saveFailed);` where `l10n` came from the View or lookup with known `Locale`.

### B4. Reactive `RxString` status text

Fields like `statusText`, `errorMessage` on controllers should hold **either**:

- **Localized** strings (resolved at the time of assignment using known `Locale`), or  
- **Opaque keys** (`'errors.save_failed'`) resolved in the **widget** via `Obx` + `tr` / l10n — prefer fewer moving parts: **resolve in the view**.

---

## Part C — Execution tiers (“skill levels”) for systematic rollout

Use these tiers to split work so nothing is missed. Higher tiers assume lower tiers are done.

### Tier 0 — Foundation (blocking)

- Add `gen-l10n`, `app_en.arb`, `locale` resolution, Settings language → `Locale`.
- Add **`LocaleController` / `UiController` extension** to expose `Locale` for optional `lookupAppLocalizations`.
- Document **B2/B3** pattern in `CONTRIBUTING.md` (one paragraph).

**Exit:** App can switch EN ↔ one pilot locale; one screen uses ARB end-to-end.

### Tier 1 — Static settings & chrome

- `AppTexts` migration, Settings / Security / Data / UI / Feedback tiles.
- `CustomAppBar` titles, list section headers.

**Exit:** No raw English in `lib/app/modules/settings`, `security`, `data`, `ui`, `feedback` (verify with `rg`).

### Tier 2 — High-traffic flows (views first)

- Get Started (view strings; delegate long messages to ARB).
- Memory create/edit **widgets** (`memory_view`, `memory_info_widget`, pickers).
- Map **widgets** (FAB, overlays, non-debug user strings).

**Exit:** Controllers still may pass strings **only** if supplied from views in Tier 2; start replacing `Get.snackbar` in controllers touched here.

### Tier 3 — Controllers & services (strings only)

- `GetStartedController`, `MemoryController`, `MapControllerNew` (user-facing messages, snackbars, dialog copy).
- Apply **B2**: pass `l10n` or localized `String` from binding/view, or `lookupAppLocalizations(locale)`.

**Exit:** Grep for `Get.snackbar`, `SnackBar`, `AlertDialog` in `lib/app/modules/**/controllers` returns only allowed patterns.

### Tier 4 — Categories, filters, DB-backed labels

- Implement category **key → ARB** mapping; migration for seed data if needed.
- Filter chips, searchable category UI, add-place dialogs.

**Exit:** Align with section 5 of **`LOCALIZATION_PLAN.md`**.

### Tier 5 — Polish & enforcement

- Remove `l10n_allowlist.txt` entries; enable stricter CI grep.
- Full manual QA matrix (locales × core flows).

---

## Part D — Agent / self-checklist (for AI-assisted passes)

When editing a file in **Tier N**, answer:

1. **Visibility:** Is this string shown to the user? If yes → ARB.
2. **Context:** Do I have `BuildContext`? If yes → `AppLocalizations.of(context)!`.
3. **Controller:** If no context → am I passing the string **from** the View, or using **lookup** with stored `Locale`?
4. **Duplicate:** Does this English already exist? → **Reuse** key; don’t fork wording.
5. **Plural / count:** Use ARB **plural** / `ICU` if needed — avoid string concatenation.
6. **GetX `.tr`:** If team uses `.tr`, keys must exist in **all** language JSONs — same parity rule as ARB.

---

## Part E — Artifact list (recommended repo files)

| File | Purpose |
|------|--------|
| `docs/LOCALIZATION_PLAN.md` | Strategy, categories, phases |
| `docs/LOCALIZATION_COVERAGE_PLAYBOOK.md` | This file — guarantees + GetX + tiers |
| `docs/l10n_inventory_baseline.txt` | Frozen grep output before migration |
| `docs/l10n_allowlist.txt` (optional) | Files/lines still allowed to contain raw English until migrated |
| `l10n.yaml` + `lib/l10n/*.arb` | Source of truth |

---

## Part F — Complete string-source taxonomy (verify nothing is missed)

Use this as a **checklist**. A migration is incomplete if any row below still contains **user-visible** English outside ARB (or your chosen catalog), except **exempt** rows.

### F1 — Flutter widget tree (in `lib/app/`)

| # | Source | Examples / notes | Verify with (ripgrep ideas) |
|---|--------|------------------|----------------------------|
| 1 | `Text`, `AutoSizeText`, `SelectableText` | Inline `'...'` or `"..."` | `rg "Text\\(\\s*['\`]" lib/app` |
| 2 | `AppBar` / `CustomAppBar` `title` | String or `Text(...)` | Search `title:` in views |
| 3 | `ListTile` `title` / `subtitle` | | `rg "ListTile\\(" lib/app` |
| 4 | `InputDecoration` | `hintText`, `labelText`, `helperText`, `errorText` | `rg "InputDecoration\\(" lib/app` |
| 5 | `validator:` | Form validation messages | `rg "validator:" lib/app` |
| 6 | Buttons | `ElevatedButton`, `TextButton`, `child: Text('...')` | |
| 7 | `SnackBar` / `MaterialBanner` | | `rg "SnackBar\\(" lib/app` |
| 8 | Dialogs | `AlertDialog`, `SimpleDialog`, `showDialog`, `CupertinoAlertDialog` | `rg "showDialog\\(|AlertDialog\\(" lib/app` |
| 9 | Bottom sheets | `showModalBottomSheet`, `Get.bottomSheet` | |
| 10 | Tabs / segmented | `Tab(text:)`, `TabBar` | |
| 11 | `Tooltip`, `Semantics` | `label`, `hint` | `rg "Tooltip\\(|Semantics\\(" lib/app` |
| 12 | `DropdownButton` / menus | `DropdownMenuItem` child text | |
| 13 | Empty / error placeholders | `Center(child: Text(...))` in loading states | |
| 14 | `RefreshIndicator` | `semanticsLabel` if set | |

### F2 — GetX-specific

| # | Source | Notes |
|---|--------|--------|
| 15 | `Get.snackbar` title + message | Very common in controllers — **high risk** |
| 16 | `Get.dialog` / `Get.defaultDialog` | Title, middle text, confirm/cancel |
| 17 | `GetMaterialApp` | `title`, `unknownRoute` message if any |
| 18 | Reactive `RxString` shown in UI | `statusText`, `errorMessage`, etc. — resolve in **view** or assign localized string from context |

### F3 — Controllers & services (non-UI files that still surface copy)

| # | Source | Notes |
|---|--------|--------|
| 19 | `GetStartedController`, `MemoryController`, `MapControllerNew`, `FilterController`, download services | Assignments to `statusText`, `errorMessage`, snackbars |
| 20 | `MbtilesDownloadService` / `StyleJsonDownloadService` | Default `statusText` and **notification** `TaskNotification(...)` strings |
| 21 | `main.dart` | `FileDownloader().configureNotification(TaskNotification(...))` — **user-visible** in notifications |
| 22 | `AppLockController` | `localizedReason`, `authError` messages |
| 23 | `PermissionService` / permission copy | User-facing rationale if shown |
| 24 | `ConnectivityService` | Any user-visible status (if not debug-only) |

### F4 — Platform & native (outside Dart UI but user-visible)

| # | Source | Notes |
|---|--------|--------|
| 25 | `ios/Runner/Info.plist` | `NS*UsageDescription` — already English; **localize** via localized `InfoPlist.strings` per locale if you ship multi-language iOS |
| 26 | Android `strings.xml` | Same idea for `android/app/src/main/res/values*/strings.xml` |
| 27 | `local_auth` | `localizedReason` in Dart — must be ARB |

### F5 — Data / categories (special)

| # | Source | Notes |
|---|--------|--------|
| 28 | `SearchableCategoryWidget` defaults | e.g. `title = 'Place'` |
| 29 | `PlaceCategory` display | Seed DB / JSON keys → map to ARB (see main plan) |
| 30 | Hashtag / contact group **defaults** | `AppTexts.sport` etc. — replace with l10n |

### F6 — Explicitly **exempt** (do not count as “missed”)

- `debugPrint`, `print`, log tags
- `lib/copy/`, `*_backup*.dart`, `*_old*.dart`, `example_*`, `globe_test` if non-production
- URLs, asset paths, `SharedPreferences` keys
- Generated or vendor code under `.pub-cache/`
- User-authored memory text, user-created category names

### F7 — “Closure” procedure before declaring 100% done

1. Run **each** grep in F1–F3 against `lib/app/` (and `lib/services/` if in scope); paste outputs into `docs/l10n_inventory_final.txt`.
2. For every remaining match, either **migrate** or add a one-line entry to **`docs/l10n_allowlist.txt`** with reason (e.g. “debug-only”, “deprecated file”).
3. Confirm **main.dart** notification strings and **download** `TaskNotification` strings are in ARB or allowlisted.
4. Re-run **Tier 5** manual matrix (locales × flows).

### F8 — Repo snapshot (indicative counts — re-run after changes)

Rough pattern frequency under `lib/` (not excluding tests/copy): dialogs/snackbars appear in **many** feature files; `Text('...')` appears in **dozens** of files; reactive `statusText`/`errorMessage` assignments appear in **controllers + services** broadly. **Do not** rely on counts alone — use **F7** grep closure.

---

## Summary

- **Ensure replacement:** baseline inventory + CI key parity + milestone `rg` gates + manual smoke + optional goldens.
- **GetX:** avoid English in controllers; **views** supply `AppLocalizations` or use **locale-aware lookup** in a dedicated service.
- **Tiers:** Foundation → Settings → Big views → Controllers/services → Categories → Enforcement.
- **Nothing missed:** complete **Part F** taxonomy + **F7** closure procedure + allowlist for intentional exceptions.

This playbook is the operational contract for “nothing left hardcoded” without relying on memory alone.
