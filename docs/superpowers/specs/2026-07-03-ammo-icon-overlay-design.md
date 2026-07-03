# SQS Ammo Icon Overlay (color dot v2) — Design

Date: 2026-07-03
Status: approved by user (this session)

## Goal

Upgrade the v1 color square: the dot becomes the actual ammo's icon (bolt/
arrow/rune image), tinted with the v1 ColorMap color. Transparency comes from
the icon's alpha.

## Hard constraints (inherited from v1 + June/Runepot scars)

- Never mutate native widgets; never construct FText; no poll loops; no
  IsA(string); all game-object work in ExecuteInGameThread + pcall; flushed
  file-log line before every dangerous op.
- v1's gate proofs (see plans/2026-07-03-ammo-color-dot.md verdict) cover:
  own-widget create/tint/viewport-set/remove. They do NOT cover the two new
  op classes here:
  1. reading an icon/texture reference off ItemData (and, if it is a soft
     reference, loading it);
  2. writing our own UImage's Brush fields (ResourceObject etc.).
- **One-attempt rule (user-set):** ONE G4 gate session. Any hard crash → v2
  is dead permanently, v1 square stays. No retries.

## Approach

1. **Icon discovery (read-only, zero risk):** keybound probe dumps the loaded
   ammo's ItemData properties (names, types, and values for icon-ish
   candidates: Icon/Brush/Texture/Thumbnail/Sprite) to a flushed file. Calls
   nothing, writes nothing to game state.
2. **G4 gate (one shot):** staged, save first — resolve the icon texture
   object from the discovered property; construct the v1 dot widget but point
   `img.Brush.ResourceObject` at the texture (pre-viewport, field writes,
   never a whole-struct table); keep the ColorAndOpacity tint. Survive with a
   visible tinted icon = pass.
3. **Production (only if G4 passes):** `hud.createDot` gains the icon lookup
   (from the live loaded item's ItemData, resolved per swap; falls back to
   the plain square whenever the texture can't be resolved). No new config
   surface beyond `config.ShowIconOverlay` (default true post-gate).

## Failure handling

- Discovery finds no icon-ish property, or the reference needs an op we
  can't gate safely → stop before G4, keep square (v2 closed, no crash risk
  taken).
- G4 hard-crashes → v2 closed permanently, keep square.
- Production: any per-swap icon resolution failure silently falls back to
  the square (never blocks the swap; same best-effort contract as v1).

## Testing

In-game only, as v1: discovery output review → G4 gate → smoke (icon tracks
ammo across bolts/arrows/runes, tint correct, auto-skip still truthful,
V-spam stable, F1-F4 regression).
