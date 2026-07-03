# SQS Loaded-Ammo Color Dot — Design

Date: 2026-07-03
Status: approved by user (this session)

## Goal

Show a small colored dot near the reticle ammo icon indicating the currently
loaded ammo type (runes for staffs, arrows for bows, bolts for crossbows),
recolored on every V swap.

## History / hard constraints

- **Never mutate a native widget.** June 2026 (branch `feat/ammo-hud-indicator`)
  proved that ANY render mutation on an existing game widget from Lua hard-crashes
  this UE4SS build: UFUNCTION setter, raw property assignment, a bare float
  opacity, and the same op on a plain health-bar widget (isolation test) all
  crashed. Approach abandoned at the A5 gate. Do not retry any variant of it.
- **Never construct FText.** FText construction hard-crashes this UE4SS build
  (proven in Runepot). Any fallback path requiring FText args is dead on arrival.
- Rejected approach: external overlay app (user preference — in-game only).

## Approach A (primary, ONE attempt)

Create our **own** widget — a small colored dot — and never mutate any widget
after creation. Color is set at construction time. Updating the color on swap
= remove the old dot widget, create a fresh one with the new color.

### Behavior

- Dot sits just under the game's ammo icon in the reticle area.
- Visible whenever the dot has been spawned for a loaded ammo; recolored
  (recreated) on every successful V swap.
- **Event-driven only — NO poll loop.** The dot updates solely on V-swap
  events. A background ticker to hide the dot on weapon holster is explicitly
  excluded: poll loops are what caused the V-crash saga (see
  V-CRASH-HANDOVER.md). Accepted v1 trade-off: the dot may linger on screen
  after holstering, until the next swap.
- Color mapping in `config.lua`:
  - `config.ColorMap`: keys are asset-name substrings, values are RGB tables.
    - Runes: `Rune_Fire` = red, `Rune_Water` = blue, `Rune_Earth` = green,
      `Rune_Air` = pale yellow; others fall through to default.
    - Arrows/bolts: `Poison` = green; tier names (Bronze, Iron, ...) get
      distinct colors.
  - `config.ColorDefault`: fallback RGB for unmapped ammo.
  - `config.ShowColorDot`: master enable.
  - `config.DotSize`, `config.DotOffset`: size and screen offset tuning.
- New ammo types are a config edit, not a code change.

### The gate (one in-game session, staged probes)

Save the game first. Each stage is behind its own keypress; tail UE4SS.log
after each stage. **Any hard crash at any stage kills Approach A permanently —
no retries — and we fall back to Approach C.**

- **G1:** create our own widget and add it to the viewport, color set at
  construction. Survive?
- **G2:** position it near the reticle. Positioning our OWN widget is untested
  territory (June only proved native-widget mutation crashes); if positioning
  our own widget also crashes, A dies here.
- **G3:** remove the widget and re-create it with a different color (this IS
  the production update path). Survive?

All three pass → feature is viable; production code is a new `Scripts/hud.lua`
module plus a ~10-line hook at the end of `swap.cycle` in `Scripts/swap.lua`.

### Production shape (post-gate)

- `Scripts/hud.lua`: owns dot lifecycle (spawn/replace/despawn), resolves color
  from `config.ColorMap` by asset-name substring match, all game-object work
  inside `ExecuteInGameThread` + `pcall`, module is inert when
  `config.ShowColorDot` is false.
- `Scripts/swap.lua`: after a successful load, call
  `hud.setDot(target.asset)` (best-effort; failure never blocks the swap).
- Widget creation mechanism (e.g. `UWidgetBlueprintLibrary.Create` vs other)
  is decided during the gate session — whatever survives G1 is the mechanism.

## Approach C (fallback, only if A crashes)

Discover a game-native toast/notification function (BP function scan on HUD /
notification managers) and call it on swap with the ammo name ("Fire runes
loaded").

- Constraint: if the callable requires FText, C is dead too (see hard
  constraints) and we stop at console-print feedback (status quo).
- No persistent color — swap-time text only.

## Testing

- All verification is in-game (no unit-testable surface): gate stages G1–G3,
  then production smoke: V-cycle through runes on a staff and arrows/bolts on
  bow/crossbow, confirm dot color tracks the loaded ammo, confirm ~70-press
  stability (the V-crash saga bar), tail UE4SS.log after every crash or oddity.
- Regression watch: SQS V swap and F1–F4 loadouts must remain crash-free with
  the dot enabled and disabled.

## Out of scope

- Mutating native widgets in any form (proven crash).
- External overlay app (rejected by user).
- SyloreLoot interactions (mod is shelved).
