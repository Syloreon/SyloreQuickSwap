--[[
    Sylore Quick Swap - main.lua
    Entry point. Registers the cycle keybinds and delegates to swap.lua.

    Author: Syloreon Khan <sylore@hotmail.com>
    License: see LICENSE / README
]]

local config   = require("config")
local swap     = require("swap")
local loadouts = require("loadouts")

print("[Sylore Quick Swap] loaded. V=cycle ammo (Shift+V back); F1-F4 apply armor sets, Shift+F1-F4 save.")

-- Wrap callbacks so a Lua error never kills the keybind or the UE4SS mod loader.
local function safe(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then print("[Sylore Quick Swap] error: " .. tostring(err)) end
    end
end

-- Defensive keybind: if `key` is nil (e.g. a Key.* name this UE4SS build doesn't
-- expose), warn and skip instead of letting RegisterKeyBind throw — a load error
-- here would silently kill EVERY keybind in the mod (hard-won lesson, see NAMES.md).
local function bind(label, key, mods, cb)
    if key == nil then
        print("[Sylore Quick Swap] WARNING: key for '" .. label .. "' is nil — binding skipped. Check the Key.* name in config.lua.")
        return
    end
    local ok = pcall(RegisterKeyBind, key, mods or {}, safe(cb))
    if not ok then print("[Sylore Quick Swap] WARNING: failed to bind '" .. label .. "'.") end
end

RegisterKeyBind(config.CycleForwardKey, config.CycleForwardMods, safe(function()
    swap.cycle(1)
end))

RegisterKeyBind(config.CycleBackwardKey, config.CycleBackwardMods, safe(function()
    swap.cycle(-1)
end))

-- ── Armor loadouts (F1-F4 apply, Shift+F1-F4 save) ──────────────────────────
loadouts.load()   -- restore saved sets from disk (no-op if the file doesn't exist)
for slotNum = 1, config.LoadoutSlotCount do
    local key = config.LoadoutApplyKeys[slotNum]
    bind("loadout " .. slotNum .. " apply", key, config.LoadoutApplyMods,
        function() loadouts.applySlot(slotNum) end)
    bind("loadout " .. slotNum .. " save", key, config.LoadoutSaveMods,
        function() loadouts.saveToSlot(slotNum) end)
end

-- ── Phase 1 discovery keybinds (only when config.DiscoveryMode) ─────────────
if config.DiscoveryMode then
    require("discovery")
    print("[Sylore Quick Swap] DISCOVERY MODE on — F8=probe live rune state, F9=dump player, F7=arm rune hooks.")
    RegisterKeyBind(config.DiscoverKey,   {}, safe(function() RQS.probeRunes() end))
    RegisterKeyBind(config.CombatMagicKey,{}, safe(function() RQS.dumpPlayer() end))
    RegisterKeyBind(config.HookKey,       {}, safe(function() RQS.armRuneHooks() end))
end
