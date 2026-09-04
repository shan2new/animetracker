# DECISION: where "same look" stops and "native Android" starts

**Product owner, 2026-09-04.** This sharpens `product-decisions.md` §1. It is not a reversal — it
answers the question that section left implicit: *when iOS and Android disagree about how to render
something, who wins?*

> "I don't want the app to look like an iOS app on Android. I want the UX consistency. What can be
> ported should be, what isn't natively possible in Android, I'd rather use native Android there
> than do heavy Engineering to make it fit."

## The principle

**Port the meaning. Render with native means. Re-tune the numbers.**

| Layer | Rule |
|---|---|
| **Semantics & hierarchy** | Ports **exactly**. Amber means MEANING and STATE, never action. One section-header family. The hero slate grammar: pill → headline → show → fact. Prose is rationed. Library is calm, Today carries urgency. A finished thing is a tick, not the word "Watched". These are the product, and they are platform-independent. |
| **Copy** | Ports **verbatim**. Every string, every temporal expression, every voice law. |
| **Information design** | Ports **exactly**. What is loud, what is quiet, what is one line vs two, what earns art, what earns a shadow. |
| **Rendering mechanics** | Uses the **native Android answer**. Elevation, overscroll, menus, back, ripple where the design allows, system share, notification model. |
| **Numeric values** | **Re-tuned for Android** so they *read* the same. Not matched so they *measure* the same. |

The test to apply when in doubt: *does an Android user, who has never seen the iPhone app,
experience the same product?* If yes, the port is correct — even where a pixel differs. Conversely,
matching an iOS pixel by building machinery Android does not want is a **defect**, not fidelity.

## What this resolves

### Q1 — Blur and shadow calibration: **cancelled as framed**

The plan proposed a half-day of side-by-side capture to make Android's blur and shadow radii match
iOS's numbers, because "Skia's blur and `setShadowLayer` are not on iOS's scale" and this port's
baked blur runs in source pixels before an upscale where iOS's runs in points after one.

That entire problem is an artefact of trying to match iOS numerically. **Do not do it.**

- **Shadows** → use Android's native elevation model (`Modifier.shadow(elevation, shape)` /
  Material elevation), not a hand-rolled Skia shadow reproducing iOS's `(color, radius, y)` triples.
  Keep `ShadowToken`'s **semantic names** — `none` / `card` / `art` / `artHero` / `floating` — and
  the rule that only art large enough to read as an object earns one. Give each a **dp elevation
  chosen to look right on Android**. The iOS radii become historical notes, not targets.
- **Blur** → use `Modifier.blur` / `RenderEffect` directly on API 31+, and the opaque-canvas
  reduce-transparency treatment below (see `minsdk-decision.md`). **No baked-blur pipeline, no
  pre-blurred bitmaps, no upscale trick.** If the native blur cannot produce the exact frosting iOS
  gets, the Android app gets Android's frosting.
- What still needs a human eye is only the ordinary question *"does this read right?"* — a normal
  design review on the two AVDs, not a calibration exercise against iPhone captures.

### Q6 — Hero pull-down stretch: **take option (a), the native one**

The plan recommended (b): intercept `onPreScroll` and reproduce iOS's stretch, on the grounds it is
"more toe-to-toe." That is precisely the heavy engineering this decision rules out. Android already
answers overscroll natively with a stretch effect; use it. The billboard keeps its identity through
its **size, art and copy hierarchy**, which are what actually make it a billboard — not through
reproducing a specific iOS rubber-band curve.

### Q16 — Long-press menus: **`DropdownMenu`**

iOS's blurred lift-and-platter has no Android equivalent. Use the native menu. (Already the plan's
default; now it is settled rather than "confirm with design.")

### Q17 — Reduce Motion: **accept the platform contract**

Under "Remove animations" Android gives no transitions at all rather than iOS's 120 ms fade. That is
Android's contract with its user, and it wins. Keep `pickMotion` only for motion the app drives
itself.

### Q5 — "Leaves the app" glyph: **`open_in_new`**

The Android reflex, not `arrow_outward`'s 1:1 match with SF's `arrow.up.right`.

### Q11 / Q21 — Haptics: **not a blocker, and not a gate**

> "Haptics are not really a blocker. Different devices have different ones unlike iPhones."

Android haptic hardware varies enormously — LRA vs ERM, wildly different amplitude ranges, OEM
remapping — where every iPhone has the same Taptic Engine. So:

- **Accept the collapse of `.commitLight` and `.commitMedium`** onto one grade where composition
  primitives are unavailable. Do not spend the `VIBRATE` permission to preserve two grades.
- **Map to `HapticFeedbackConstants` semantics first** (`CONFIRM`, `REJECT`, `CLOCK_TICK`,
  `CONTEXT_CLICK`, `SEGMENT_TICK`) and let the OEM decide how they feel. Reach for
  `VibrationEffect.Composition` only where a constant genuinely has no analogue.
- **Keep the `FeedbackCoordinator` discipline** — every haptic goes through one place, at most one
  per transaction, with the per-token floor (`.selection` 0.04 s, everything else 0.3 s). That rule
  is about *not buzzing twice for one action*, which is platform-independent and still matters.
- **Physical-device haptic sign-off is no longer a release gate.** A Pixel and a mid-range Samsung
  are still wanted for OEM behaviour generally — battery-killers and alarm reliability, which are
  real — but not to approve haptic feel.

## What this does NOT relax

The design law in `CLAUDE.md` still binds, because it is about meaning rather than mechanics:

- No `MaterialTheme` as the app theme; no dynamic colour; no Material typography; no FAB; no
  `Snackbar` standing in for the custom toast.
- Amber is still never an action colour.
- Bars are still material-to-their-bottom-edge where blur exists, and opaque where it does not —
  never transparent.
- Prose is still rationed; copy is still verbatim.
- Every number is still a token, never a literal at a call site. The *values* change; the
  *discipline* does not.

**The line, stated once:** Android may look different from iOS. Android may not look *arbitrary*.
