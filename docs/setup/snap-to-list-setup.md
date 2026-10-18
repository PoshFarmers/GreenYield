# Snap-to-List: setup guide

How to switch Snap-to-List from the built-in **sample suggestion** to real
**Gemini** AI. Until you finish these steps the feature still works: every
photo gets a clearly labelled *Sample suggestion*.

> **Why the key isn't in the app:** anything in the Flutter app (including
> `.env`) can be extracted from the installed APK. The Gemini key is stored
> as a **Supabase secret** and only the `suggest-listing` Edge Function can
> read it. The app calls the function and never sees the key.

```
App ──(photo, signed-in user)──▶ Edge Function "suggest-listing" ──(key)──▶ Gemini
 ▲                                      │
 └──── crop + description ◀─────────────┘   any failure → app shows the sample suggestion
```

---

## 1. Prerequisites

| You need | Check |
|---|---|
| Supabase CLI | `supabase --version` |
| Logged in | `supabase login` |
| This repo linked to your project | `supabase link --project-ref <your-project-ref>` (ref = the id in your project URL) |
| A Google account | for the free Gemini key |

## 2. Get a free Gemini API key

1. Open **Google AI Studio** → *Get API key* → *Create API key*.
2. Copy the key (starts with `AIza…`). **Don't** paste it into `.env` or
   any file in this repo.

Free-tier notes: requests are rate-limited per minute/day, and on the
free tier Google may use prompts and images to improve its products.

## 3. Apply the database migration

Creates the quota table and the `claim_ai_request` function (cooldown +
daily limit per farmer).

```bash
supabase db push
```

✅ Verify (Supabase dashboard → SQL editor):

```sql
select proname from pg_proc where proname = 'claim_ai_request';
```

## 4. Store the key as a secret

```bash
supabase secrets set GEMINI_API_KEY=AIza...your-key...
# optional: choose the model (any free-tier Flash / Flash-Lite with image input)
supabase secrets set GEMINI_MODEL=gemini-2.5-flash
```

✅ Verify: `supabase secrets list` shows `GEMINI_API_KEY` (value hidden).

## 5. Deploy the Edge Function

```bash
supabase functions deploy suggest-listing
```

✅ Verify: dashboard → *Edge Functions* lists `suggest-listing`.

## 6. App configuration

In the app's `.env` (non-secret flag only):

```
AI_ASSISTANT_MODE=gemini
```

`gemini` is also the default when the line is missing. Then **fully
restart** the app (not hot reload).

## 7. Try it

1. Sign in as a **farmer** who has at least one crop on their profile.
2. **Harvest** tab → **+** → the green **Snap to List** card at the top.
3. Take or pick a photo of produce the farmer grows.
4. Expect the **✨ AI suggestion** badge, the crop pre-selected
   ("Very likely Tomato"), and a short description in the app's language.
5. **Use these** → you land on quantity & price with the crop, description
   and photo filled in.

If you see **🧪 Sample suggestion** instead, the grey note under it says
why. See troubleshooting below.

---

## Troubleshooting

The sample note's first sentence tells you what failed:

| Message in the app | Cause | Fix |
|---|---|---|
| "AI suggestions are turned off." | `AI_ASSISTANT_MODE=mock` | Set it to `gemini`, restart the app |
| "AI suggestions aren't available right now." | Function not deployed, no `GEMINI_API_KEY`, Gemini error/timeout, or invalid model name | Re-check steps 4–5; check function logs (below); try `GEMINI_MODEL=gemini-2.5-flash-lite` |
| "You're offline." | No connection | Expected — the manual flow still works |
| "Please wait a few seconds between photos." | 10-second per-farmer cooldown | Wait and retry |
| "You've reached today's limit for AI suggestions." | 25 per farmer per day (Sri Lanka time) | Resets at midnight, or raise `DAILY_CAP` |
| "That photo is too large to analyse." | Image over ~1.5 MB | Retake; the app already resizes, so this is rare |
| AI badge, but "We couldn't identify this for sure" | Photo isn't produce, or not one of the farmer's crops | Expected — farmer picks the crop manually |

**Function logs:** dashboard → *Edge Functions* → `suggest-listing` →
*Logs*, or `supabase functions logs suggest-listing`. Errors are logged as
`gemini error <status>`; images and keys are never logged.

**Error codes** the function returns (shown in logs / network inspector):
`unauthorized`, `bad_request`, `image_too_large`, `no_crops`, `cooldown`,
`daily_cap`, `not_configured` (no key), `rate_limited` (Gemini quota),
`timeout`, `invalid_output`, `upstream_error`.

---

## Tuning & maintenance

| Setting | Where | Default |
|---|---|---|
| Cooldown between requests | `COOLDOWN_SECONDS` in `supabase/functions/suggest-listing/index.ts` | 10 s |
| Requests per farmer per day | `DAILY_CAP` (same file) | 25 |
| Gemini timeout | `GEMINI_TIMEOUT_MS` (same file) | 15 s |
| Model | `GEMINI_MODEL` secret | `gemini-2.5-flash` |

After editing the function, redeploy: `supabase functions deploy suggest-listing`.

**Rotating the key:** create a new key in AI Studio → `supabase secrets set
GEMINI_API_KEY=...` (takes effect immediately, no redeploy) → delete the old key.

**Model retired or renamed?** Google renames free models from time to time.
If suggestions suddenly fall back to the sample, set `GEMINI_MODEL` to a
current free Flash model from the Gemini pricing page. The function already
copes with changes to the structured-output request format.

**Turning it off:** `AI_ASSISTANT_MODE=mock` in `.env` (no network calls at
all), or remove the secret to make every request fall back to the sample.

See also: [`docs/B-marketplace/snap-to-list.md`](../B-marketplace/snap-to-list.md) (how it works).
