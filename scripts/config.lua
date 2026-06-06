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

return config
