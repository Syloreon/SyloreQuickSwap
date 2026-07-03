--[[
    Sylore Quick Swap - config.lua
    User-tunable settings. Edit these freely; no other file needs changing to retune.
    After editing in-game, press the UE4SS hot-reload key (default Ctrl+R) to apply.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local config = {}

-- ── Keybinds ──────────────────────────────────────────────────────────────
-- Key + ModifierKey names come from the UE4SS Lua API (globals `Key` / `ModifierKey`).
-- Defaults use V / Shift+V because they are unbound by default in Dragonwilds.
-- VERIFY these don't clash with your own keybinds before relying on them.
config.CycleForwardKey      = Key.V
config.CycleForwardMods     = {}                    -- e.g. { ModifierKey.CONTROL }
config.CycleBackwardKey     = Key.V
config.CycleBackwardMods    = { ModifierKey.SHIFT } -- Shift+V cycles backward

-- ── Armor loadouts (equipment sets) ───────────────────────────────────────
-- Four fixed loadout slots, each on a function key:
--   F1-F4         -> apply (equip) the armor set saved in slot 1-4
--   Shift+F1-F4   -> save your currently-worn armor into that slot (overwrites)
-- Saving over a slot replaces it, so there's no separate delete. Weapon & ammo are
-- left untouched (the V-cycle owns ammo). One apply key per slot = LoadoutApplyKeys.
config.LoadoutSlotCount     = 4
config.LoadoutApplyKeys     = { Key.F1, Key.F2, Key.F3, Key.F4 } -- slot 1..4 apply
config.LoadoutApplyMods     = {}                                 -- bare F-key applies
config.LoadoutSaveMods      = { ModifierKey.SHIFT }              -- Shift+F-key saves
-- Where saved sets persist (survives restarts). Leave EMPTY to auto-save next to the
-- mod (portable — no machine-specific path). Set a full path only to override.
config.LoadoutsFile         = ""

-- ── Behavior ──────────────────────────────────────────────────────────────
-- Wrap from the last rune back to the first (and vice-versa). Also wraps loadouts.
config.WrapAround           = true

-- Optional explicit cycle order for ANY ammo (runes, arrows, bolts), by asset name
-- with or without the "ITEM_" prefix. Anything not listed is appended alphabetically.
-- Leave empty for plain alphabetical order. Examples:
--   { "Rune_Fire", "Rune_Air" }                      -- runes in this order
--   { "Arrow_Bronze", "Arrow_Iron", "Arrow_Steel" }  -- arrow tiers low->high
config.AmmoOrder           = {}
config.RuneOrder           = {}   -- legacy alias; AmmoOrder takes precedence if set

-- ── Feedback / debugging ──────────────────────────────────────────────────
config.ShowOnScreenFeedback = true   -- brief on-screen note of the new ammo (if supported)
config.Verbose              = false  -- log details to the UE4SS console

-- ── Phase 1 discovery (TEMPORARY — kept for future re-mapping) ────────────
-- When true, main.lua loads discovery.lua and binds:
--   F8 -> RQS.probeRunes()   (live rune state: loaded rune + inventory contents)
--   F9 -> RQS.dumpPlayer()   (list components + dump pawn & mode/ranged/ammo comps)
--   F7 -> RQS.armRuneHooks() (broad ProcessEvent hook trace; see NAMES.md caveats)
-- Output is written (flushed per line) to discovery-*.txt in the mod folder.
-- Leave OFF for normal play; flip on only to re-discover names after a game update.
config.DiscoveryMode        = false
config.DiscoverKey          = Key.F8   -- probe live rune state
config.CombatMagicKey       = Key.F9   -- dump player + components
config.HookKey              = Key.F7   -- arm rune hooks (trace)

-- ── HUD color-dot gate (TEMPORARY — one-attempt probe, see plans/2026-07-03) ──
-- When true, main.lua loads hudgate.lua and binds F7/F8/F9 to gates G1/G2/G3.
-- MUTUALLY EXCLUSIVE with DiscoveryMode (same keys). Leave OFF for normal play.
config.HudGateMode          = false
config.HudGateG1Key         = Key.F7   -- G1: create own widget (red)
config.HudGateG2Key         = Key.F9   -- G2: size + position it (PASSED 2026-07-03; F9 eats keypresses on this setup)
config.HudGateG3Key         = Key.F8   -- G3: remove + recreate (blue) — moved to F8, proven to fire

-- ── Loaded-ammo color dot ─────────────────────────────────────────────────
-- A small square of color near the reticle showing the loaded ammo type.
-- Recolored on every V swap (the dot is destroyed and recreated — never
-- mutated — see docs/superpowers/specs/2026-07-03-ammo-color-dot-design.md).
-- Known v1 wart: the dot lingers after holstering until your next swap.
config.ShowColorDot         = true
-- First matching substring (case-insensitive, checked in order) wins. Poison is intentionally listed BEFORE tier names so poison ammo stays green — don't re-sort alphabetically.
-- Keys match the ItemData asset name, e.g. "ITEM_Rune_Fire", "ITEM_Arrow_Poison".
config.ColorMap = {
    { match = "Poison",     color = { R = 0.20, G = 0.90, B = 0.20 } }, -- green
    { match = "Rune_Fire",  color = { R = 1.00, G = 0.15, B = 0.10 } }, -- red
    { match = "Rune_Water", color = { R = 0.15, G = 0.40, B = 1.00 } }, -- blue
    { match = "Rune_Earth", color = { R = 0.20, G = 0.80, B = 0.20 } }, -- green
    { match = "Rune_Air",   color = { R = 1.00, G = 1.00, B = 0.60 } }, -- pale yellow
    { match = "Bronze",     color = { R = 0.80, G = 0.50, B = 0.20 } },
    { match = "Iron",       color = { R = 0.55, G = 0.55, B = 0.60 } },
    { match = "Steel",      color = { R = 0.85, G = 0.85, B = 0.90 } },
    { match = "Mithril",    color = { R = 0.35, G = 0.45, B = 1.00 } },
    { match = "Adamant",    color = { R = 0.10, G = 0.60, B = 0.35 } },
}
config.ColorDefault         = { R = 1.0, G = 1.0, B = 1.0 }  -- unmapped ammo
config.DotSize              = 16.0     -- square edge, px
config.DotOffsetY           = 50.0     -- px below screen center (reticle area)

-- ── Icon-overlay gate (TEMPORARY — v2 one-shot probe, see plans/2026-07-03-ammo-icon-overlay) ──
-- F7 = read-only ItemData icon scan (repeatable); F8 = G4 one-shot brush probe.
-- Set IconGateProp to the icon property name found in sqs-icongate.txt before F8.
-- MUTUALLY EXCLUSIVE with HudGateMode and DiscoveryMode. Leave OFF for normal play.
config.IconGateMode         = true   -- ARMED for the v2 gate session (disarm after Task I2)
config.IconGateScanKey      = Key.F7
config.IconGateG4Key        = Key.F8
config.IconGateProp         = ""

return config
