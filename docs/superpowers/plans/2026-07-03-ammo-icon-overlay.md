# Ammo Icon Overlay Implementation Plan (color dot v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The v1 color square becomes the loaded ammo's actual icon, tinted with its ColorMap color — behind a read-only discovery probe and ONE G4 gate session.

**Architecture:** Extend the gate-module pattern: a new `scripts/icongate.lua` (discovery scan + G4 probe, disarmed by default like `hudgate.lua`). If G4 passes, `scripts/hud.lua`'s `createDot` gains an icon-brush step with silent fallback to the square.

**Tech Stack:** UE4SS Lua, UMG reflection. No test harness; staged in-game gates with flushed file logs (repo convention).

**Spec:** `docs/superpowers/specs/2026-07-03-ammo-icon-overlay-design.md`

## Global Constraints

Identical to the v1 plan's (see `2026-07-03-ammo-color-dot.md` Global Constraints) plus:
- **One-attempt rule for G4** (user-set): a hard crash anywhere in the G4 keypress permanently closes v2; the v1 square stays. The discovery scan (I-scan) is read-only and exempt.
- New op classes under test: ItemData icon-property read / soft-reference load / own-widget `Brush.ResourceObject` write. None of these may enter production code except via the exact shapes G4 proves.
- Environment: F9 never reaches keybinds; no hot-reload (full restart per config change); the gate keys reuse F7 (scan) and F8 (G4) under a new `config.IconGateMode` flag, mutually exclusive with `HudGateMode`/`DiscoveryMode`.

---

### Task I1: `icongate.lua` — read-only icon scan + G4 probe, config + wiring

**Files:**
- Create: `scripts/icongate.lua`
- Modify: `scripts/config.lua` (append IconGate section before `return config`)
- Modify: `scripts/main.lua` (append wiring after the hudgate block)

**Interfaces:**
- Consumes: same globals as `hudgate.lua`; file-local helper idioms copied from `swap.lua` (loadout-slot read) and `hudgate.lua` (modRoot/flog/createDot shape).
- Produces: `icongate.scan()` (read-only ItemData property dump → `sqs-icongate.txt`), `icongate.g4()` (one-shot tinted-icon widget probe). Task I3 reuses the exact code shape G4 proves.

Key content requirements (full code authored at dispatch time, following hudgate.lua conventions exactly):
- `scan()`: resolve PlayerController → Loadout component → first occupied ammo slot among MagicAmmo1=6, Ammo=5, CrossbowBolts=9 (enum values verified in `scripts/names.lua`) → item.ItemData; `ForEachProperty` dump: property name + property class + (for object-ref properties whose name matches Icon/Brush/Texture/Thumbnail/Sprite/Image, case-insensitive) the value's `GetFullName()`. All reads pcall'd, all lines flushed. CALLS NOTHING mutating.
- `g4()`: staged inside one keypress, flog before each dangerous op: resolve icon object from the property name recorded by scan (name read from `config.IconGateProp`, set by hand after reading the scan output); if the value is not a live UObject (soft ref), ONE `StaticLoadObject` attempt (flagged DANGEROUS); then the hudgate `createDot` shape with `img.Brush.ResourceObject = tex` inserted pre-tint; tint from ColorMap red for visibility; viewport size/position as v1.
- config: `IconGateMode=false`, `IconGateScanKey=Key.F7`, `IconGateG4Key=Key.F8`, `IconGateProp=""`.
- main.lua wiring mirrors the hudgate block, guarded `config.IconGateMode and not config.HudGateMode and not config.DiscoveryMode`.
- Commit: `feat(icon): icongate — read-only ItemData icon scan + one-shot G4 brush probe`

### Task I2: In-game session (USER AT KEYBOARD — decision point)

1. Arm `IconGateMode=true`, full restart, load world.
2. **F7 scan** (read-only, repeatable): review `sqs-icongate.txt` together; pick the icon property; set `config.IconGateProp`; restart.
3. **Save the game.** **F8 = G4, ONE SHOT.** Tinted icon appears → PASS. Hard crash → v2 permanently closed (record verdict, clean up branch, keep square).
4. Record verdict in this plan; commit.

### Task I3: Production integration (ONLY if G4 passes)

- `scripts/hud.lua`: `createDot(col)` → `createDot(col, assetIconTex)`; resolve the texture in `applyDot`'s caller context from the landed item's ItemData (swap.lua already holds the verified item — pass its ItemData icon through; exact plumbing decided from G4's proven shape). Any nil/failure → plain square (current behavior).
- `config.ShowIconOverlay = true` toggle.
- Disarm IconGateMode. Commit: `feat(icon): tinted ammo-icon dot with square fallback`

### Task I4: Smoke + wrap-up

- In-game: icon tracks ammo across bolts/arrows/runes; tint matches ColorMap; refused-rune auto-skip still truthful; V-spam; F1–F4; `ShowIconOverlay=false` → square.
- README bullet update; final branch review; merge via finishing-a-development-branch.

## Gate verdicts (appended during execution)

*(empty)*

**2026-07-03 Task I2 verdict: G4 PASS (18:42).**
- Scan found `AmmoCounterIcon : ObjectProperty` on AmmoData (shared parent of MagicAmmoData/RangedAmmoData) holding a live Texture2D (e.g. T_Icons_Rune_Water) — no soft-ref load needed.
- `Icon`/`CategoryClassIcon` are SoftObjectProperty = UNREADABLE on this UE4SS build (throws catchable "no registered handler" — safe, but a closed path).
- G4 clean: property read → valid UObject → createIconDot with `img.Brush.ResourceObject = tex` pre-tint → tint → AddToViewport → viewport sizing. Red-tinted rune icon visible in-game. Both new op classes now gate-proven.
- ForEachProperty note: leaf classes declare nothing; superclass-chain walk with discovery.lua's metaclass stop-guards is required (commit 3f4dfb0).
