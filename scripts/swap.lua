--[[
    Sylore Quick Swap - swap.lua
    Core logic: cycle the held weapon's loaded ammo by one hotkey.

    Verified model (Phase 1, see NAMES.md):
      * "Ammo" = inventory items: runes (MagicAmmoData), arrows/bolts (RangedAmmoData).
      * The ACTIVE ammo for a weapon is the item in a specific Loadout slot
        (MagicAmmo1=6 for staves, Ammo=5 for bows, CrossbowBolts=9 for crossbows).
      * Loading ammo is the right-click "use" action:
            InventoryController:UseItemFromInventory(SourceInventory, SlotIndex)
        The item stays in the bag (reference-counted), so "loading" just re-points the
        loadout slot.

    Which ammo V cycles is chosen by the HELD WEAPON: we read the weapon in the
    HeldRight slot, match its Category against names.AmmoStrategies, and cycle that
    strategy's ammo. Staff -> runes, bow -> arrows, crossbow -> bolts.

    Everything is resolved LIVE each press (the user can rearrange the bag), and ammo
    is ordered by stable asset name, never by slot position. All game-specific symbols
    come from names.lua; adding a weapon/ammo type is a data change there, not here.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
local names     = require("names")
local config    = require("config")
local hud       = require("hud")

local swap = {}

-- ── small helpers ─────────────────────────────────────────────────────────

local function log(msg)
    if config.Verbose then print("[Sylore Quick Swap] " .. tostring(msg)) end
end

local function valid(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj.IsValid ~= nil and obj:IsValid() end)
    return ok and v or false
end

local function fullName(obj)
    if obj == nil then return "nil" end
    local ok, n = pcall(function() return obj:GetFullName() end)
    return ok and n or tostring(obj)
end

-- Leaf token of a full path/name: "Class /Game/..Foo.Foo" -> "Foo".
local function leaf(s)
    return (s and s:match("[%.%s]([^%.%s]+)$")) or s
end

-- Class leaf name of a UObject, via metadata only (never IsA(string) — that can
-- hard-crash this UE4SS build; see NAMES.md).
local function classLeaf(obj)
    if not valid(obj) then return "nil" end
    local ok, c = pcall(function() return obj:GetClass() end)
    if not ok or c == nil then return "nil" end
    return leaf(fullName(c))
end

-- Strip the asset prefix for friendly logs: "ITEM_Rune_Fire" -> "Rune_Fire".
local function pretty(asset)
    if asset == nil then return "?" end
    local p = names.AssetPrefix
    if p and asset:sub(1, #p) == p then return asset:sub(#p + 1) end
    return asset
end

-- ── item inspection (all proven crash-safe in the Phase-1 probe) ───────────

-- An item's ItemData, or nil.
local function itemData(item)
    if not valid(item) then return nil end
    local ok, data = pcall(function() return item.ItemData end)
    if ok and valid(data) then return data end
    return nil
end

-- Stable asset name of an item's ItemData ("ITEM_Rune_Fire"), or nil.
local function assetOf(item)
    local data = itemData(item)
    return data and leaf(fullName(data)) or nil
end

-- Item's Category gameplay tag as a string ("Item.Equipment.Ammo.Arrow.Bronze"), or "".
local function categoryOf(item)
    local data = itemData(item)
    if data == nil then return "" end
    local cat = ""
    pcall(function()
        local c = data.Category
        if c ~= nil then
            cat = (c.TagName ~= nil) and c.TagName:ToString() or tostring(c)
        end
    end)
    return cat or ""
end

-- Does this item qualify as candidate ammo for the given strategy?
local function matchesStrategy(item, strat)
    local data = itemData(item)
    if data == nil then return false end
    if classLeaf(data) ~= strat.dataClass then return false end
    if strat.ammoTag then
        if string.find(categoryOf(item), strat.ammoTag, 1, true) == nil then return false end
    end
    return true
end

-- ── object graph resolution (live, every press) ────────────────────────────

local function getController()
    local pc = UEHelpers:GetPlayerController()
    return valid(pc) and pc or nil
end

-- First valid component property on `owner` whose name contains `want` and none of
-- the `excludes` (case-insensitive). Components are declared on the BP controller's
-- own class, so the leaf class is enough.
local function findComponent(owner, want, excludes)
    if not valid(owner) then return nil end
    local ok, cls = pcall(function() return owner:GetClass() end)
    if not ok or cls == nil then return nil end
    want = string.lower(want)
    local found = nil
    pcall(function()
        cls:ForEachProperty(function(prop)
            if found ~= nil then return end
            local pname = prop:GetFName():ToString()
            local nm = string.lower(pname)
            if string.find(nm, want, 1, true) == nil then return end
            if excludes then
                for _, ex in ipairs(excludes) do
                    if string.find(nm, string.lower(ex), 1, true) then return end
                end
            end
            local okv, v = pcall(function() return owner[pname] end)
            if okv and valid(v) then found = v end
        end)
    end)
    return found
end

-- The item in a given loadout slot (by ELoadoutSlot value), or nil.
local function itemInLoadoutSlot(loadout, slotEnum)
    if not valid(loadout) then return nil end
    local okIdx, idx = pcall(function() return loadout:GetSlotIndexForSlot(slotEnum) end)
    if not okIdx or idx == nil or idx < 0 then return nil end
    local okIt, item = pcall(function() return loadout:GetItemFromSlot(idx) end)
    if okIt and valid(item) then return item end
    return nil
end

-- Size (slot count) of an inventory component.
local function inventorySize(inv)
    local ok, slots = pcall(function() return inv.ItemSlots end)
    if ok and slots ~= nil then
        local okn, n = pcall(function() return slots:GetArrayNum() end)
        if okn and n then return n end
    end
    local okN, n = pcall(function() return inv:GetNumItems() end)
    if okN and n then return n end
    return 0
end

-- Walk an inventory by the GAME's slot space (GetItemFromSlot, so the index matches
-- what UseItemFromInventory expects), collecting strategy-matching ammo as
-- { asset=..., inv=inv, slot=i }, deduped by asset name.
local function collectAmmoFrom(inv, strat, out, seenAsset)
    if not valid(inv) then return end
    local n = inventorySize(inv)
    for i = 0, n - 1 do
        local ok, item = pcall(function() return inv:GetItemFromSlot(i) end)
        if ok and valid(item) and matchesStrategy(item, strat) then
            local asset = assetOf(item)
            if asset and not seenAsset[asset] then
                seenAsset[asset] = true
                out[#out + 1] = { asset = asset, inv = inv, slot = i }
            end
        end
    end
end

-- Pick the strategy for the currently-held weapon. Returns (strategy, weaponCategory).
local function resolveStrategy(loadout)
    local weapon = nil
    for _, slotEnum in ipairs(names.HeldWeaponSlots) do
        weapon = itemInLoadoutSlot(loadout, slotEnum)
        if valid(weapon) then break end
    end
    if not valid(weapon) then return nil, nil end
    local cat = categoryOf(weapon)
    for _, s in ipairs(names.AmmoStrategies) do
        if string.find(cat, s.weaponTag, 1, true) then return s, cat end
    end
    return nil, cat
end

-- ── public: snapshot the ordered, deduped ammo list for a strategy ─────────

-- Returns: orderedAmmo (array of {asset,inv,slot}), currentAsset (string|nil)
function swap.snapshot(pc, loadout, strat)
    -- Currently-loaded ammo for this weapon = its loadout slot's item.
    local current = itemInLoadoutSlot(loadout, strat.slot)
    local currentAsset = current and assetOf(current) or nil

    -- Candidate ammo from the bag (and personal inventory as a fallback location).
    local ammo, seen = {}, {}
    collectAmmoFrom(findComponent(pc, "Inventory", { "Controller", "Personal" }), strat, ammo, seen)
    collectAmmoFrom(findComponent(pc, "Personal"), strat, ammo, seen)

    -- Order: explicit config.AmmoOrder first (match with or without the asset prefix),
    -- then any remaining alphabetically by asset name (stable, language-neutral).
    table.sort(ammo, function(a, b) return a.asset < b.asset end)
    local order = config.AmmoOrder or config.RuneOrder
    if order and #order > 0 then
        local rank = {}
        for i, key in ipairs(order) do rank[string.lower(key)] = i end
        local function rankOf(asset)
            return rank[string.lower(asset)] or rank[string.lower(pretty(asset))] or 1000
        end
        table.sort(ammo, function(a, b)
            local ra, rb = rankOf(a.asset), rankOf(b.asset)
            if ra ~= rb then return ra < rb end
            return a.asset < b.asset
        end)
    end

    return ammo, currentAsset
end

-- ── public: cycle in a direction (+1 forward, -1 backward) ─────────────────

function swap.cycle(direction)
    local pc = getController()
    if pc == nil then log("No player controller."); return end
    local loadout = findComponent(pc, "Loadout")
    if not valid(loadout) then log("Loadout component not found."); return end

    local strat, weaponCat = resolveStrategy(loadout)
    if strat == nil then
        log("Held weapon has no cyclable ammo (category: " .. tostring(weaponCat) .. ").")
        return
    end

    local ammo, currentAsset = swap.snapshot(pc, loadout, strat)
    if #ammo < 2 then
        log(strat.label .. ": fewer than 2 available - nothing to cycle.")
        return
    end

    -- Index of the currently-loaded ammo within the ordered list.
    local cur = 1
    for i, a in ipairs(ammo) do
        if currentAsset and a.asset == currentAsset then cur = i; break end
    end

    local nextIdx = cur + direction
    if nextIdx < 1 then
        nextIdx = config.WrapAround and #ammo or 1
    elseif nextIdx > #ammo then
        nextIdx = config.WrapAround and 1 or #ammo
    end
    if nextIdx == cur then return end

    -- Candidates in cycle order starting at nextIdx: the game can REFUSE a
    -- load (e.g. level-gated runes), so V hops onward until one sticks — at
    -- most once around, never landing back on the current ammo.
    local tries = {}
    do
        local idx, steps = nextIdx, 0
        while steps < #ammo and idx ~= cur do
            tries[#tries + 1] = ammo[idx]
            idx = idx + direction
            if idx > #ammo then
                if not config.WrapAround then break end
                idx = 1
            elseif idx < 1 then
                if not config.WrapAround then break end
                idx = #ammo
            end
            steps = steps + 1
        end
    end
    if #tries == 0 then return end

    local invCtrl = findComponent(pc, "InventoryController")
    if not valid(invCtrl) then
        log("InventoryController not found - cannot load " .. strat.label .. ".")
        return
    end

    -- ONE game-thread closure: attempt candidates in order, verifying each by
    -- re-reading the loadout slot (it re-points synchronously on accept; a
    -- refused load leaves it untouched). Feedback and the color dot use the
    -- VERIFIED result — never the attempt (a lying dot is worse than none).
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local landed = nil
            for _, cand in ipairs(tries) do
                invCtrl:UseItemFromInventory(cand.inv, cand.slot)
                local now = itemInLoadoutSlot(loadout, strat.slot)
                local nowAsset = now and assetOf(now) or nil
                if nowAsset == cand.asset then landed = cand.asset; break end
            end
            if landed then
                if config.ShowOnScreenFeedback then
                    swap.onScreen(strat.label .. ": " .. pretty(landed))
                end
            else
                log(strat.label .. ": no other loadable option (kept "
                    .. pretty(currentAsset) .. ").")
            end
            local shown = landed or currentAsset
            if shown then hud.applyDot(shown) end   -- already on the game thread
        end)
        if not ok then
            print("[Sylore Quick Swap] load failed: " .. tostring(err))
        end
    end)
end

-- Best-effort feedback. UE4SS has no universal toast, so we log; a HUD hook can go here.
function swap.onScreen(text)
    print("[Sylore Quick Swap] " .. text)
end

return swap
