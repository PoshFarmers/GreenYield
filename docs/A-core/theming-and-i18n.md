# Theming and Internationalisation

**Owner:** Author A (Core)
**Reviewers:** Author D (notification/chat strings)
**Last verified against:** `lib/core/theme/*`, `lib/core/localization/*`, `assets/translations/en/common.json` only

## 1. Purpose

Where theme and language configuration live and how they load. UI widgets are out of scope.

## 2. Theming

- `AppColors` holds every colour constant; widgets are meant to use `Theme.of(context).colorScheme`.
- `AppTheme.light` / `AppTheme.dark` call one `_build(...)` with per-mode tokens (background, surface, border, text, tint, accent, error). Material 3, custom input/button/card/dialog/app bar themes.
- Dark mode uses a lifted green (`darkPrimary`) for text/icons because the brand green has about 3.2:1 contrast on dark backgrounds.
- `_textTheme` is built from `ThemeData.light().textTheme` for both modes; `google_fonts` is a dependency but not used in these files.

| Provider | Behaviour |
|---|---|
| `themeModeProvider` (`NotifierProvider<ThemeModeNotifier, ThemeMode>`) | Default `ThemeMode.system`; `loadSavedTheme()` reads `SharedPreferences['theme_mode']` (`light`/`dark`/else system) and is awaited in `main()` before `runApp`; `setThemeMode` persists `mode.name` |

`MaterialApp` wires `theme`, `darkTheme`, `themeMode`.

## 3. Internationalisation

- `easy_localization`: supported locales `en`, `si`, `ta`; fallback `en`; path `assets/translations`.
- `MultiFileAssetLoader` merges `assets/translations/<lang>/<file>.json` for the fixed list: `common, auth, farmer, buyer, driver, notifications, listings, marketplace, cart, checkout, chat`.
- Merge is `merged.addAll(...)` in list order, so **later files override duplicate keys** from earlier ones.
- Any load or JSON parse error is swallowed by `catch (_) {}` (comment: "Expected for now"), so a missing or malformed file silently drops all its keys.
- `pubspec.yaml` declares the three language directories as assets (plus `.env`).
- `common.json` conventions seen: `error_*`, `transaction_type_*` (matches wallet txn types), `month_short_*`, `theme_*`. Other keys referenced in code: `day_short_mon..sun` (driver route weekdays), driver task keys (`pickup_at`, `delivery_to`, `crop_summary`, `order_total`).
- DB side: `profile.preferred_language` (`language_code` enum: en/si/ta), mirrored as `preferred_language_text`.

> ⚠ Unverified: only `en/common.json` was provided. Confirm how locale changes are persisted and whether they update `profile.preferred_language`, and that `si`/`ta` files exist for every entry in `_files`.

## 4. Offline behaviour

Both are fully local (assets and `SharedPreferences`).

## 5. Edge cases

- A typo in a translation file removes the whole file without an error.
- Key collisions between files are resolved silently by list order.
- Server-generated notification text (`title`, `body` from SQL) is **English only** and not translated.

## 6. How to extend safely

- New feature strings: add `<feature>.json` in all three language folders **and** append the name to `_files`.
- Use unique key prefixes per file to avoid override collisions.
- New colours go in `AppColors`, and mode-specific values through `_build` parameters.

## Source files

`lib/core/theme/app_colors.dart`, `app_theme.dart`, `theme_provider.dart`; `lib/core/localization/multi_file_asset_loader.dart`; `lib/main.dart`; `pubspec.yaml`; `assets/translations/en/common.json`; `lib/models/driver_profile.dart`, `driver_task.dart`; migration `20260815155858_generic_profile`.