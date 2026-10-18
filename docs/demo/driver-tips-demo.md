# Demo script: Weather-Smart Driver Tips

A 3-minute walkthrough that shows the same driver getting **different,
cargo-aware advice** as the weather changes. Works fully offline: the
forecast is a built-in sample, so there's no dependency on real weather or
the internet.

**The one-line pitch:** *"GreenYield knows what's on the truck and what the
weather will do, so it tells the driver how to protect the produce. Not
generic weather, but advice for **this** load."*

---

## Before the demo (5 min)

- [ ] Sign in as a **driver** account (any driver works; real stops are a bonus).
- [ ] **Driver Home** → the **Today's tips** card is under the green
      route summary (on tablets, at the top of the stop list).
- [ ] Tap **🎛** (top-right of the card) to open **Demo weather**:
  - [ ] If the driver has **no stops today**, turn on **"Use sample cargo
        when there are no stops"**. The card then uses Tomato, Cabbage,
        Carrot and Banana with 3 pending pickups, and says so.
  - [ ] Pick **Rainy afternoon** as your opening scenario.
- [ ] If you've rehearsed before, tap **Show again** on the card so no tips
      are hidden by an earlier *Got it*.
- [ ] Optional: set the phone to **dark mode** or **Sinhala/Tamil** to show
      it off. The tips are fully translated.

Your choices are saved, so they survive an app restart mid-demo.

> **Real cargo vs sample cargo:** with a driver who has real stops today,
> the tips name the crops actually on the route. That's the most convincing
> version if you can set it up (place an order as a buyer and assign it).

---

## The walkthrough

### Act 1: Rainy afternoon (≈60 s)

1. Point to the **forecast strip**: *"6 AM to 8 PM. See the blue
   slots: that's the rain window, 1 PM to 6 PM."*
2. Read the top tip, a **red warning**: *"Rain likely 1 PM–6 PM"*.
3. Tap the amber tip **"Cover the leafy greens"** to expand it. *"It
   knows there's cabbage on board, and wet leafy greens bruise and rot."*
   Point at the **Cabbage** chip.
4. Next tip: **"Do pickups before the rain"**, with *3 pickups pending,
   collect them before 1 PM.* *"It's planning the route around the
   weather."*
5. Tap **Got it** on one tip. It disappears for today: *"Drivers dismiss
   what they've handled."*

### Act 2: Hot and dry (≈45 s)

1. **🎛** → **Hot and dry** (the sheet can stay open; the card updates
   behind it, then close it).
2. The header icon turns to a **sun**, and the strip shows temperatures
   peaking around **35°**.
3. New tips: **"Hot day, up to 35°C"**, then **"Deliver delicate fruit
   first: Tomato, Banana"**. *"Same truck, different weather, and the
   advice flips from 'cover the greens' to 'drop the soft fruit early'."*

### Act 3: Language & honesty (≈30 s)

1. **Profile → Language → සිංහල** (or தமிழ்) and back to Home. The tips
   are now in Sinhala/Tamil, generated from the same rules.
2. Point at the **"Sample forecast"** badge and the disclaimer: *"We
   label it honestly. In production this is the live forecast, and the tips
   are suggestions, not orders."*

### Close (≈15 s)

*"Today this runs on a sample forecast and our rules engine. Next it plugs
into a live free forecast (Open-Meteo) and Gemini for richer wording, with
these same rules as the safety net, so drivers always get advice, even
offline."*

---

## Scenario cheat-sheet

| Scenario | Forecast | Tips you'll see (with sample cargo) |
|---|---|---|
| **Rainy afternoon** | 80 % rain 1–6 PM | Rain warning · Cover the leafy greens · Do pickups before the rain · 6 stops today |
| **Hot and dry** | up to 35 °C, no rain | Hot day · Deliver delicate fruit first · Keep the greens cool · 6 stops today |
| **Windy** | gusts up to 42 km/h | Strong winds, tie down crates · 6 stops today |
| **Clear and mild** | no rain, ≤ 30 °C | Good conditions today · 6 stops today |
| **Automatic** | rotates daily | Stable all day; changes tomorrow |

The **"6 stops today"** tip appears whenever there are 4 or more pending
stops. Cargo tips appear only when that kind of crop is on board: no
leafy crops means no "cover the greens".

---

## If something goes off-script

| Situation | Do this |
|---|---|
| Card says "Tips for your route will appear here when you have stops today" | 🎛 → turn on **sample cargo** |
| A tip you wanted to show is missing | Tap **Show again** at the bottom of the card |
| Only 2 tips visible | Tap **Show N more** (the card shows the top 2 by default) |
| No 🎛 button | It only appears while the forecast is a sample; check `DRIVER_TIPS_MODE=mock` |
| Wrong language | Profile → Language. It switches instantly |

## After the demo

🎛 → **Automatic** and turn **sample cargo off**, so a real driver doesn't
see demo data.
