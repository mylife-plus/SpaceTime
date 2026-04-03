# App localization plan (SpaceTime)

This document is a **plan only**—no implementation. It summarizes how the project handles strings today, how to introduce proper localization, how to **find** user-visible strings, and how to treat **place categories** (a special case).

**Companion:** **`LOCALIZATION_COVERAGE_PLAYBOOK.md`** — how to **prove** strings are migrated, **GetX / snackbar / controller** rules, **tiered execution** (skill levels), and **Part F: full string-source taxonomy** so no UI/GetX/service/native notification strings are missed.

---

## 1. Current state (audit summary)

| Area | What we see |
|------|-------------|
| **Central strings** | `lib/app/config/app_text.dart` (`AppTexts`) holds a **small** set of English labels (settings, security, data, a few hashtag/contact samples). |
| **Most UI** | Large amounts of **inline** English: `Text('...')`, `SnackBar`, dialogs, `Get.snackbar`, button labels, map/memory/get-started flows. |
| **GetX** | Project uses GetX; **no** `GetMaterialApp.translations` / `.tr` pattern is established app-wide. |
| **Flutter gen-l10n** | No `l10n.yaml`, no `lib/l10n/*.arb` in repo today. |
| **Categories** | Place categories are **data-driven**: `PlaceCategoryService` + `DatabaseHelper` + `PlaceCategory` models. Default UI strings like `SearchableCategoryWidget` default `title = 'Place'` are hardcoded in Dart. **Stored category names** in SQLite are user/content data—localization strategy must separate **UI chrome** vs **stored labels**. |
| **Noise** | Thousands of `debugPrint('...')` strings—**exclude** from localization (developer-only). |
| **Legacy / copy** | Folders like `lib/copy/`, `*_backup*.dart`, `example_*` should be **excluded** from first-pass inventory or deleted if unused. |

---

## 2. Goals

1. **Single source of truth** for translatable UI strings (per locale).
2. **Consistent API** in widgets (no scattered raw English in new code).
3. **Categories**: predictable behavior for **picker UI**, **filters**, and **persisted** category text.
4. **Workflow** that scales (designers/translators can work on ARB or CSV without editing Dart).

---

## 3. Recommended technical approach (Flutter)

### Option A — **Official `flutter gen-l10n` (recommended)**

- Add `flutter_localizations` + `intl` (SDK already supports `gen-l10n`).
- Create `l10n.yaml` and `lib/l10n/app_en.arb` (template), then `app_es.arb`, `app_fr.arb`, etc.
- Run `flutter gen-l10n` → generates `AppLocalizations` (or `S` depending on config).
- In `MaterialApp` / `GetMaterialApp`: set `localizationsDelegates`, `supportedLocales`, and `locale` (from `Locale` + user preference in `SharedPreferences` / `UiController`).

**Pros:** Standard, type-safe, good IDE support, plural/gender support via ARB.  
**Cons:** Requires importing `AppLocalizations.of(context)!` (or extension) in widgets; **GetX** routing must still provide a `BuildContext` where needed (dialogs, overlays).

### Option B — **easy_localization** or **GetX translations**

- JSON/CSV per language; access via `.tr` or `tr('key')`.

**Pros:** Familiar to GetX teams; quick key-based migration.  
**Cons:** Less compile-time safety; easier to miss keys or typo keys.

### Recommendation

Use **Option A** for the main app UI, and keep **one** locale resolver (e.g. `UiController.selectedLanguage` mapped to `Locale('en')`, `Locale('es')`, …) so Settings “Language” drives `MaterialApp.locale`.

---

## 4. How to find all hardcoded strings (inventory)

Do this in **phases** so the list stays actionable.

### 4.1 Automated discovery (ripgrep / IDE)

Run from repo root (adjust paths as needed):

```bash
# User-visible Text widgets (high signal)
rg "Text\\(\\s*['\"]" lib --glob "*.dart"

# Snackbars / dialogs / titles
rg "(SnackBar|showDialog|AlertDialog|Get\\.snackbar|Get\\.dialog)" lib --glob "*.dart"

# String literals in UI-heavy modules (tune list)
rg "['\"][A-Za-z].{0,120}['\"]" lib/app/modules/get_started lib/app/modules/memories lib/app/modules/settings --glob "*.dart"
```

**Exclude** from user-facing inventory:

- `debugPrint(` / `print('`
- `lib/copy/`, `*_backup*.dart`, `example_*`, `globe_test` if non-production
- URLs and asset paths (`https://`, `assets/`)
- Keys in `SharedPreferences` / JSON field names (`'dark_mode'`, etc.)

### 4.2 IDE tooling

- **Dart analyzer** custom lint (optional): `avoid_escaping_inner_quotes` won’t catch English; consider **`flutter_lints`** + manual review.
- **VS Code / Android Studio**: search for `Text(` with regex, export results to a spreadsheet.

### 4.3 Build a “string inventory” spreadsheet

Columns: **file**, **line**, **current English**, **ARB key**, **context** (screen), **notes** (category vs chrome).

**Target order for migration** (high user impact first):

1. Get Started + download flow  
2. Settings / Security / UI / Data  
3. Memory create/edit + validation messages  
4. Map / filters / location picker  
5. Remaining modules  

---

## 5. Categories — special handling

Categories touch **three** different concepts—do **not** mix them into one ARB file without a design:

| Concept | Source | Localization approach |
|--------|--------|-------------------------|
| **UI labels** | “Place”, “Search categories”, “Add new”, “See all” in `SearchableCategoryWidget`, `category_picker_widget`, `add_place_category_popup`, etc. | Move to **ARB** keys; translate with the rest of the UI. |
| **System / seed category names** | Rows in SQLite (`place_categories` or equivalent) populated from DB helper / migrations | **Either** (a) store a **stable key** (`cafe`) and map to ARB `category_cafe`, **or** (b) add per-row **locale columns** (`name_en`, `name_es`)—heavier for DB. Prefer **key + ARB** for maintainability. |
| **User-created categories** | User-added strings in DB | **Do not** auto-translate; they are user content. |

**Migration plan for categories (when you implement):**

1. Define **canonical category keys** in DB (or map from existing English names to keys with a one-time migration script).  
2. Add ARB entries: `categoryFood`, `categoryFoodCafe`, …  
3. At display time: `AppLocalizations.of(context)!.categoryFood` if key is known; else show raw user string.  
4. Filters: store **keys** in filter state where possible; resolve to localized label in the UI layer.

---

## 6. Implementation phases (suggested)

### Phase 0 — Hygiene

- Remove or quarantine dead code (`lib/copy/`, unused `*_backup.dart`) to reduce string inventory noise.
- Decide **supported locales** (e.g. `en` first, then `es`).

### Phase 1 — Tooling

- Add `flutter_localizations` + `intl`; add `l10n.yaml` + `app_en.arb`.
- Wire `GetMaterialApp` / `MaterialApp` with delegates and `locale` resolution.
- Persist `Locale` in `SharedPreferences` and connect to existing **Language** UI in `UiController` / `ui_view.dart`.

### Phase 2 — Migrate `AppTexts`

- Replace `AppTexts.*` usages with `AppLocalizations` (or keep `AppTexts` as thin wrappers delegating to `AppLocalizations` during transition).

### Phase 3 — Screen-by-screen migration

- Replace hardcoded `Text('...')` with `Text(context.l10n.xxx)` (or generated getter names).
- For **controllers** without `BuildContext`: pass translated strings from the **view**, or inject a `Locale`/`AppLocalizations` facade (avoid duplicating English in services).

### Phase 4 — Categories

- UI strings for widgets (section 5).  
- DB/category key strategy + migration.  
- QA: switching language updates pickers; **filters** still match memories (define behavior for mixed-language data).

### Phase 5 — QA & process

- Golden tests optional for critical screens.  
- **Translation handoff**: export `app_en.arb` → translators → merge `app_xx.arb`.  
- CI: `flutter gen-l10n` in build pipeline; fail if ARB missing keys vs template.

---

## 7. Files and folders to touch first (reference)

| Location | Role |
|----------|------|
| `lib/app/config/app_text.dart` | Replace with / align to generated l10n |
| `lib/main.dart` | `localizationsDelegates`, `supportedLocales`, `locale` |
| `lib/app/modules/ui/` | Language + locale persistence |
| `lib/app/modules/get_started/` | Many user-facing strings |
| `lib/app/modules/memories/` | Memory flow, validation, category UI |
| `lib/app/shared/widgets/searchable_category_widget.dart` | Default titles / buttons |
| `lib/app/services/place_category_service.dart` + DB helpers | Category keys vs display names |

---

## 8. Out of scope for “strings”

- **Mapbox / style** labels (tiles) — separate from app UI l10n.  
- **Server or R2** JSON — only if you serve per-locale assets.  
- **Legal / privacy** — may need separate PDF/Web flow.

---

## 9. Success criteria

- **Zero** new raw English user strings in `lib/app/` (enforce in code review).  
- All supported locales have **complete** ARB keys (CI check).  
- Language switch applies without restart (or with one restart if you accept limitation—prefer **no restart**).  
- Category pickers show **localized** system categories; user-created names unchanged.

---

*Generated as a planning document for the SpaceTime codebase structure as of the audit date.*
