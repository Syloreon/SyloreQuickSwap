# SyloreQuickSwap — Loaded-Ammo HUD Indicator (design)

**Date:** 2026-06-07
**Author:** Syloreon Khan <sylore@hotmail.com>
**Mod:** SyloreQuickSwap (`F:\claude\runescape\SyloreQuickSwap`)

## Problem

When a bow/crossbow is equipped, the player needs to know **at all times** which
arrow/bolt is currently loaded — specifically whether it is an elemental/status type
(e.g. Fire, Poison) or plain — **without** having to cycle ammo or open the inventory to
find out. The game already draws an ammo icon on the HUD, but it is not distinct enough to
tell the loaded type apart at a glance.

## Hard constraints (from the master HANDOFF.md)

- **`FText` is wholly unusable** on this UE4SS build — no Lua constructor, and
  passing/returning it hard-crashes natively (uncatchable by pcall). ⇒ **No on-screen text
  of any kind.** The indicator must be purely visual (color/image).
- **Mutations and any UI dispatch must run inside `ExecuteInGameThread`** (off-thread UI
  ops hard-crash). Reads on game objects off-thread are fine.
- **`RegisterHook` is a dead end for inventory/loot ops** (they bypass ProcessEvent) ⇒
  **poll on a `LoopAsync` tick, don't hook.**
- **Keybinds are the only reliable trigger.** Proven discovery keys: `F7`/`F9` (+ Shift/
  Ctrl/Alt). `F8` is eaten, `F11` = fullscreen, console commands don't route.
- **`UObject:IsA("string")` hard-crashes** — discriminate by class **leaf name** instead.
- A Lua load error silently kills the whole mod ⇒ each module re-declares its own
  pcall-guarded helpers; verify the file parses (`python luacheck.py <file>`).

## Approach (chosen: Approach A — augment the existing widget in place)

Recolor the **single ammo icon the game already draws** by element. No icon-swapping, no
second/duplicate HUD element (explicit user requirement: "I don't want two items"). Border
is only a fallback if tinting the icon does not read well.

- Fire → warm red, Poison → green, plain → **neutral (the widget's original tint, untouched)**.
- This is lower-risk than swapping a brush texture: setting a `ColorAndOpacity`/tint is
  simpler and safer.

Rejected alternatives: **B** (standalone pinned widget — widget *creation* from Lua is
unproven on this build, highest risk, must solve anchoring + reload-survival ourselves);
**C** (add a child marker — adds an element the user explicitly does not want).

## Architecture

New self-contained module **`scripts/hud_ammo.lua`**, following the §6 architecture pattern:

- Re-declares its own pcall-guarded local helpers (`valid`, `fullName`, `leaf`,
  `classLeaf`, safe `read`/`call`); references only `names.lua` + `config.lua`. Does **not**
  share helpers/state with `swap.lua` (a load error in one must not kill the other).
- Independently resolves "what ammo is loaded right now" the same way `swap.lua` does:
  held weapon (HeldRight/HeldLeft) → matching ammo strategy → loadout slot item → stable
  **asset name** (`ITEM_Arrow_*`). Asset name is the language-neutral identity key (never
  `FText`/player-facing name).
- All widget mutation runs inside `ExecuteInGameThread(function() pcall(...) end)`.

## Phase A — Discovery probe (gated, ships disabled)

Behind `config.DiscoveryMode` and a proven key (**`Shift+F7`**), executed with a ranged
weapon equipped. Writes per-line-flushed output to `discovery-hud.txt` (crash-safe: each
line open-append-close, because a native crash loses the `UE4SS.log` tail).

The probe must answer/produce:

1. **Locate the ammo HUD widget.** Enumerate loaded widget instances (`FindAllOf` on
   candidate HUD/widget classes; walk the player HUD/`GetHUD`/widget tree). Dump each
   candidate widget's class leaf + its image/brush- and tint-bearing properties.
2. **Identify the tint property** (`ColorAndOpacity` / `BrushColor` / equivalent) on the
   ammo icon widget, and record the path to reach it from a findable root.
3. **Probe-write test:** set that tint to an obvious test color inside `ExecuteInGameThread`;
   confirm it is crash-safe AND visibly changes the on-screen icon. Then restore.
4. **Dump ammo asset names:** log the asset name of every arrow/bolt variant currently in
   the bag (so we learn the real Fire/Poison/plain asset names to map to elements).

Findings → constants added to `names.lua`. **No Phase B code is built until the probe
confirms the widget is findable and its tint is safely mutable.** If tint turns out not to
be safely mutable, fall back to Approach C (child marker) or B, re-scoped in a follow-up.

## Phase B — The indicator (built on probe results)

- `LoopAsync(config.HudTickMs ~= nil and config.HudTickMs or 500)` tick:
  1. Resolve the currently-loaded ammo (held-weapon strategy → loadout slot item → asset).
  2. If **no ranged weapon** equipped, or ammo is **plain**, restore the widget's **original
     tint** (captured on first touch) and continue.
  3. Otherwise look up the ammo's element in a `names.lua` data table
     (asset-substring → `{ element, tint = {r,g,b,a} }`) and set the widget's tint inside
     `ExecuteInGameThread` + pcall.
- **Original-tint capture:** on first successful touch of the widget, **read and remember
  its original tint** so "plain"/disabled restores the HUD exactly as the game had it.
- **Self-heal:** if the cached widget reference becomes invalid (world reload / lazy load),
  re-find it on the next tick.

## Data model (in `names.lua`)

- `names.AmmoElements` — ordered list of `{ match = "<asset substring>", element = "Fire",
  tint = { r, g, b, a } }`. Matched by case-insensitive substring against the loaded ammo's
  asset name. First match wins; no match ⇒ treated as plain (no tint). Adding a new
  elemental ammo = one data row, no code change.
- HUD widget class/property names discovered in Phase A get their own named constants here.

## Config additions (`config.lua`)

- `HudIndicatorEnabled` (bool, default true) — master on/off.
- `HudTintColors` — per-element `{ Fire = {r,g,b,a}, Poison = {...}, ... }`, overrides the
  defaults in `names.AmmoElements`.
- `HudTickMs` (default 500) — indicator poll interval.
- Probe reuses the existing discovery wiring (`config.DiscoveryMode` + `Shift+F7`).

## Unknowns — all resolved by the Phase-A probe before any Phase-B build

1. Is the ammo HUD widget reliably findable from Lua?
2. Can its tint be mutated without a crash, and does the change show on screen?
3. What are the real arrow/bolt asset names (to map to elements)?

## Out of scope

- Per-type **icon swapping** (only do it later if trivial and tint proves insufficient).
- Any text label (impossible — `FText`).
- Staff/rune indicator (this feature targets arrows/bolts; the element table can be
  extended to runes later as data rows if wanted).
- Armor-loadout UI changes.

## Success criteria

- With a bow/crossbow equipped and an elemental arrow/bolt loaded, the game's ammo HUD icon
  is visibly tinted to that element's color, updating within one tick of cycling ammo.
- Plain ammo / no ranged weapon / indicator disabled ⇒ HUD icon shows its original,
  untouched tint.
- No crashes; mod parses clean; `swap.lua` and loadouts are unaffected.
