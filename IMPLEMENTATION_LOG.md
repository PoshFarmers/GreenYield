# Implementation log — GreenYield_Implementation_Brief.md

## Feature 1: Snap-to-List — done (real + mock fallback)

**Deviation from the brief's staging:** the user asked for Snap-to-List
only, with the real Gemini call straight away and mock data whenever the
call fails — so Phase A and B of Feature 1 were built together, and
Features 2–4 are not started.

**Decisions**
- Gemini key is a Supabase secret used only by the `suggest-listing` Edge
  Function (brief §3 rule 3); the client `.env` only has the non-secret
  `AI_ASSISTANT_MODE` flag. Default is `gemini` (user wants the API used);
  any unknown value → `mock`.
- `FallbackListingAssistant` returns the mock on *any* failure, labelled
  "Sample suggestion" with the reason (honest-AI rule, §3.10).
- Gemini may only pick from the **farmer's own crops** (a listing must be
  on their menu — composite FK), not the whole catalogue.
- No `ImageCompressor` yet (that's Feature 2): the photo is already
  resized by `image_picker` (1600px, q85, same as the manual path); the
  client refuses >1.5 MB and the function >~1.5 MB decoded.
- Quota: server-side cooldown (10 s) + daily cap (25/user) via
  `ai_usage` + `claim_ai_request` (service-role only, not synced).
- Gemini's structured-output request fields changed recently
  (`responseSchema` deprecated); the function tries current → legacy →
  prompt-only formats and parses JSON defensively. Model configurable via
  `GEMINI_MODEL` (default `gemini-2.5-flash`, free tier as of Oct 2026).

**Files**
- New: `lib/core/config/app_config.dart`,
  `lib/features/listings/assistant/{listing_assistant,gemini_listing_assistant}.dart`,
  `lib/features/listings/presentation/widgets/snap_to_list_sheet.dart`,
  `supabase/functions/suggest-listing/{index.ts,deno.json}`,
  `supabase/migrations/20261018090000_ai_usage_quota.sql`,
  `test/features/listings/listing_assistant_test.dart`,
  `docs/B-marketplace/snap-to-list.md`.
- Changed: `add_harvest_screen.dart` (Snap card + flow),
  `listings.json` ×3, `supabase/config.toml`, `.env.example` (also added
  the missing `POWERSYNC_URL`).

**Follow-up for humans**
- Deploy: migration, `GEMINI_API_KEY` secret, `supabase functions deploy suggest-listing`
  (step-by-step: `docs/setup/snap-to-list-setup.md`).
- The Edge Function was not type-checked/run locally (no Deno installed).
- Review Sinhala/Tamil for the `snap_*` keys in `listings.json`.

## Feature 3: Weather-Smart Driver Tips — Phase A (mock) done

**Decisions**
- `DriverTipsService` interface + `MockDriverTipsService`; mode flag
  `DRIVER_TIPS_MODE` (default `mock`; `real` not built yet).
- Tips are cargo-aware from the start: the mock uses the **real** crops of
  today's pending stops (`crop_names` from `get_driver_today_stops`, no
  N+1). The RPC has no per-stop quantities, so tips use crop types, not
  weights.
- Crop kinds (leafy / delicate / hardy) are classified by name keywords —
  no schema change. Unknown crops count as hardy (no special tip).
- Rule engine is pure Dart (`driver_tip_rules.dart`) and unit-tested; it is
  intended to become the Phase B fallback unchanged.
- Mock text is translated via keys with parameters (`tip_*`), as the brief
  requires; times are locale-formatted (`DateFormat.j`).
- **Demo support (user request):** a 🎛 *Demo weather* sheet (shown only
  for the sample forecast) picks the scenario and can supply sample cargo
  when the driver has no stops; persisted in `SharedPreferences`.
  "Automatic" rotates the scenario per day.
- Dismissals ("Got it") are stored per day.
- Placement: under the route summary on phones; top of the stop list on
  wide layouts, so the map keeps its height. Card is isolated from the
  map/shift/GPS code.
- Visual check: rendered the card at 360 px in en (light), si, ta (dark);
  fixed a Tamil header overflow (title + badge now wrap).

**Files**
- New: `lib/features/driver_tips/{driver_tips_models,driver_tip_rules,driver_tips_service}.dart`,
  `lib/features/driver_tips/presentation/driver_tips_card.dart`,
  `test/features/driver_tips/driver_tip_rules_test.dart`,
  `docs/D-delivery-chat-notifications/weather-driver-tips.md`,
  `docs/demo/driver-tips-demo.md`.
- Changed: `driver_home_screen.dart` (card placement), `app_config.dart`
  (`driverTipsMode`), `driver.json` ×3 (38 keys), `.env.example`.

**Follow-up for humans**
- Review Sinhala/Tamil for the `tips_*`, `tip_*` and `weather_*` keys in `driver.json`.
- Phase B (Open-Meteo + Gemini Edge Function + caching) when requested.
