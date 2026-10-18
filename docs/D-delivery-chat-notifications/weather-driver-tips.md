# Weather-Smart Driver Tips

A **Today's tips** card on the driver Home: a forecast strip for the working
day (6 AM–8 PM) and up to 5 practical tips that combine the weather with the
**cargo on today's route**. Examples: *"Rain likely 1 PM–6 PM"*, *"Cover the
leafy greens (Cabbage)"*, *"Hot day: deliver delicate fruit first (Tomato,
Banana)"*.

**Status: Phase A (mock).** The forecast is a labelled *Sample forecast*;
no weather or AI service is called. The cargo is real.

## How it works

```
driver_home_screen ─▶ DriverTipsCard(stops)
                        └─ driverTipsServiceProvider ─▶ MockDriverTipsService
                              ├─ mockWeatherFor(scenario)    sample hourly forecast
                              ├─ cargoFromStops(stops)       real crops from today's stops
                              └─ buildTipDrafts(...)         deterministic rules → tips
```

- **Cargo** comes from each stop's `crop_names` (already aggregated by the
  `get_driver_today_stops` RPC, so no extra queries). Completed stops are
  excluded. Crops are classified as *leafy*, *delicate* or *hardy* by name
  (`classifyCrop`), which decides the cargo-specific tips.
- **Weather scenario:** automatic (rotates daily, stable all day) or chosen
  in the demo sheet: rainy afternoon, hot & dry, windy, clear & mild.
- **Rules** (`driver_tip_rules.dart`, pure Dart, unit-tested): rain ≥ 60 %,
  heat ≥ 33 °C, wind ≥ 35 km/h; cargo tips only when that cargo is on
  board; at most 5 tips, most severe first. This becomes the production
  **fallback** in Phase B.
- **Got it** dismisses a tip for the rest of the day (per-day key in
  `SharedPreferences`); "Show again" restores them.
- **Isolated:** the card only reads the stops it's given. The map, shift
  and GPS logic on the driver Home are untouched.

## Config

| Flag (`.env`) | Values | Default |
|---|---|---|
| `DRIVER_TIPS_MODE` | `mock` (only option for now) | `mock` |

The demo controls (🎛 on the card) appear **only while the forecast is a
sample**, so they'll disappear automatically once real weather is used.

## Phase B (not built yet)

Same `DriverTipsService` interface with a real implementation: Open-Meteo
forecast for the route area (cached per day + area), a Gemini Edge Function
grounded strictly in that forecast and cargo, and the rules above as the
fallback. See `GreenYield_Implementation_Brief.md` §8.

Code: `lib/features/driver_tips/`. Tests:
`test/features/driver_tips/driver_tip_rules_test.dart`. Demo script:
[`docs/demo/driver-tips-demo.md`](../demo/driver-tips-demo.md).
