# Snap-to-List (AI listing assistant)

Farmer taps **Snap to List** at the top of Add Harvest → crop step, takes or
picks a photo, and gets a suggested **crop** (from their own crops) and a
short **description**. They edit/confirm in a sheet; "Use these" pre-fills
the wizard (crop, description, photo) and jumps to quantity & price. The
manual flow is unchanged.

## How it works

```
AddHarvestScreen ─▶ listingAssistantProvider
                     └─ FallbackListingAssistant
                          ├─ GeminiListingAssistant ─▶ Edge Function suggest-listing ─▶ Gemini
                          └─ MockListingAssistant   (used on ANY failure, or in mock mode)
```

- **Key never in the app.** The client only calls the `suggest-listing`
  Edge Function; `GEMINI_API_KEY` is a Supabase secret read inside it.
- **Always usable.** Any failure (not deployed, no key, offline, timeout,
  rate limit, cooldown, daily cap, bad output) returns the **sample**
  suggestion — Tomato if the farmer grows it, else their first crop, with a
  fixed description. It is labelled *Sample suggestion* with the reason;
  real results are labelled *AI suggestion*.
- **Only the farmer's own crops.** The function sends Gemini the farmer's
  `farmer_crop` list and rejects any id outside it; low confidence or
  `unknown` → the sheet asks the farmer to pick the crop.
- **Quota guard (free tier).** `claim_ai_request` (migration
  `20261018090000_ai_usage_quota.sql`) enforces a 10 s per-user cooldown and
  25 requests per user per day (Asia/Colombo), atomically.
- **Request format.** The function tries Gemini's current structured-output
  format, then older ones, then plain JSON prompting, and parses the reply
  defensively — the API's schema fields have changed between versions.
- The photo is attached through the normal `_photoBytes` path, so it's
  uploaded via the offline media queue on publish.

Code: `lib/features/listings/assistant/`,
`lib/features/listings/presentation/widgets/snap_to_list_sheet.dart`,
`supabase/functions/suggest-listing/`. Tests:
`test/features/listings/listing_assistant_test.dart`.

## Turning on real AI

1. Get a free API key from Google AI Studio.
2. Apply the migration (`supabase db push`).
3. Set secrets and deploy:
   ```bash
   supabase secrets set GEMINI_API_KEY=your-key
   supabase secrets set GEMINI_MODEL=gemini-2.5-flash   # optional; any free-tier Flash/Flash-Lite model with image input
   supabase functions deploy suggest-listing
   ```
4. App `.env`: `AI_ASSISTANT_MODE=gemini` (also the default when unset).

## Mock mode

`AI_ASSISTANT_MODE=mock` in `.env` → no network calls at all; every photo
gets the sample suggestion (reason: "AI suggestions are turned off").

## Tuning

`COOLDOWN_SECONDS`, `DAILY_CAP`, `MAX_BASE64_CHARS`, `GEMINI_TIMEOUT_MS` at
the top of `supabase/functions/suggest-listing/index.ts`. Note: on the free
tier Google may use prompts/images to improve its products.
