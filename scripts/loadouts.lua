--[[
    Sylore Quick Swap - loadouts.lua
    Armor loadouts: save the currently-worn armor as a named set, then re-equip a
    whole set with one hotkey. Cycle saved sets with [ and ].

    Model (same proven mechanism as the ammo cycle, see swap.lua / NAMES.md):
      * Worn armor lives in the Loadout component's slots Head/Body/Legs/Cape/Trinket
        (names.ArmorSlots). Each is read with GetItemFromSlot(GetSlotIndexForSlot(slot)).
      * A "loadout" = the stable ASSET name of the piece worn in each of those slots
        (asset names are language-neutral; player-facing FText is missing on this client).
      * Applying a set = for each recorded piece, find that item in the bag and
        InventoryController:UseItemFromInventory(bag, slotIndex) — the same right-click
        "use/equip" action; the game routes the piece into its correct loadout slot.
      * Sets persist to a text file (config.LoadoutsFile) so they survive restarts.

    Weapon and ammo are intentionally left untouched — the V-cycle already owns ammo.

    Self-contained (mirrors swap.lua): only references names.lua / config.lua, so the
    working ammo file is never edited. Adding a slot to a loadout is a data change in
    names.ArmorSlots, not here.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
local names     = require("names")
local config    = require("config")

local loadouts = {}

-- In-memory state: fixed slots 1..config.LoadoutSlotCount (sparse — a slot is nil
-- until saved). Each set = { name = "Set 1", pieces = { [loadoutSlotEnum] = asset } }.
loadouts.sets = {}

-- ── small helpers (kept local, like swap.lua, so swap.lua stays untouched) ──

local function log(msg)
    if config.Verbose then print("[Sylore Quick Swap] " .. tostring(msg)) end
end

local function note(msg)   -- always-on, user-facing line
    print("[Sylore Quick Swap] " .. tostring(msg))
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

-- Class leaf name via metadata only (never IsA(string) — that hard-crashes this build).
local function classLeaf(obj)
    if not valid(obj) then return "nil" end
    local ok, c = pcall(function() return obj:GetClass() end)
    if not ok or c == nil then return "nil" end
    return leaf(fullName(c))
end

-- Strip the asset prefix for friendly logs: "ITEM_Armour_IronHelm" -> "Armour_IronHelm".
local function pretty(asset)
    if asset == nil then return "?" end
    local p = names.AssetPrefix
    if p and asset:sub(1, #p) == p then return asset:sub(#p + 1) end
    return asset
end

local function itemData(item)
    if not valid(item) then return nil end
    local ok, data = pcall(function() return item.ItemData end)
    if ok and valid(data) then return data end
    return nil
end

-- Stable asset name of an item's ItemData ("ITEM_Armour_IronHelm"), or nil.
local function assetOf(item)
    local data = itemData(item)
    return data and leaf(fullName(data)) or nil
end

-- Is this item an armor piece (Wearable or Trinket)? Loose class filter.
local function isArmor(item)
    local data = itemData(item)
    if data == nil then return false end
    return names.ArmorDataClasses[classLeaf(data)] == true
end

-- ── object graph (resolved live each press) ────────────────────────────────

local function getController()
    local pc = UEHelpers:GetPlayerController()
    return valid(pc) and pc or nil
end

-- First valid component property on `owner` whose name contains `want` and none of
-- the `excludes` (case-insensitive).
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

-- Find an armor item by asset name across the player's bags. Returns (inv, slotIndex)
-- or nil. Uses GetItemFromSlot so the index matches what UseItemFromInventory expects.
local function findArmorInBags(pc, asset)
    local bags = {
        findComponent(pc, "Inventory", { "Controller", "Personal" }),
        findComponent(pc, "Personal"),
    }
    for _, inv in ipairs(bags) do
        if valid(inv) then
            local n = inventorySize(inv)
            for i = 0, n - 1 do
                local ok, item = pcall(function() return inv:GetItemFromSlot(i) end)
                if ok and valid(item) and isArmor(item) and assetOf(item) == asset then
                    return inv, i
                end
            end
        end
    end
    return nil, nil
end

-- ── persistence (one slot per line) ─────────────────────────────────────────
-- Format:  <slotNum>|<name>|<loadoutSlot>=<asset>,<loadoutSlot>=<asset>,...
-- e.g.     1|Set 1|0=ITEM_Armour_IronHelm,1=ITEM_Armour_IronPlate,4=ITEM_Trinket_Ring

-- Portable file location: by default the sets are saved next to the mod (resolved at
-- runtime from THIS script's path, so there's no machine-specific absolute path). Set
-- config.LoadoutsFile to a full path only if you want them somewhere specific.
local function modRoot()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        local p = src:gsub("^@", "")
        local dir = p:match("^(.*[/\\])")            -- ".../SyloreQuickSwap/scripts/"
        if dir and dir ~= "" then
            return (dir:gsub("[Ss]cripts[/\\]$", "")) -- strip "scripts/" -> mod root
        end
    end
    return ""   -- fall back to the process working dir
end

local function loadoutsPath()
    local p = config.LoadoutsFile
    if p and p ~= "" then return p end
    return modRoot() .. "loadouts.txt"
end

local function countSets()
    local c = 0
    for i = 1, config.LoadoutSlotCount do if loadouts.sets[i] then c = c + 1 end end
    return c
end

local function persist()
    local path = loadoutsPath()
    if not path or path == "" then log("could not resolve a loadouts path — not persisting."); return end
    local ok, f = pcall(io.open, path, "w")
    if not ok or not f then note("could not write loadouts file: " .. tostring(path)); return end
    f:write("# Sylore Quick Swap armor loadouts (auto-generated; <slotNum>|<name>|<slot>=<asset>,...)\n")
    for i = 1, config.LoadoutSlotCount do
        local set = loadouts.sets[i]
        if set then
            local parts = {}
            for _, row in ipairs(names.ArmorSlots) do
                local asset = set.pieces[row.slot]
                if asset then parts[#parts + 1] = tostring(row.slot) .. "=" .. asset end
            end
            f:write(i .. "|" .. set.name .. "|" .. table.concat(parts, ",") .. "\n")
        end
    end
    f:close()
    log("saved " .. countSets() .. " loadout(s) to " .. path)
end

function loadouts.load()
    loadouts.sets = {}
    local path = loadoutsPath()
    if not path or path == "" then return end
    local ok, f = pcall(io.open, path, "r")
    if not ok or not f then return end   -- no file yet = no saved sets (fine)
    for line in f:lines() do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local slotStr, name, body = line:match("^(%d+)|(.-)|(.*)$")
            local slotNum = slotStr and tonumber(slotStr)
            if slotNum and slotNum >= 1 and slotNum <= config.LoadoutSlotCount then
                local pieces = {}
                for s, asset in body:gmatch("(%d+)=([^,]+)") do
                    pieces[tonumber(s)] = asset
                end
                loadouts.sets[slotNum] = { name = name, pieces = pieces }
            end
        end
    end
    f:close()
    log("loaded " .. countSets() .. " loadout(s) from " .. path)
end

-- ── snapshot the currently-worn armor ───────────────────────────────────────

local function readWornArmor(loadout)
    local pieces, count = {}, 0
    for _, row in ipairs(names.ArmorSlots) do
        local item = itemInLoadoutSlot(loadout, row.slot)
        local asset = item and assetOf(item) or nil
        if asset then pieces[row.slot] = asset; count = count + 1 end
    end
    return pieces, count
end

local function describeSet(set)
    local parts = {}
    for _, row in ipairs(names.ArmorSlots) do
        local a = set.pieces[row.slot]
        if a then parts[#parts + 1] = row.label .. "=" .. pretty(a) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "(empty)"
end

-- ── public: save the current outfit into a fixed slot (overwrites) ──────────

function loadouts.saveToSlot(slotNum)
    if not slotNum or slotNum < 1 or slotNum > config.LoadoutSlotCount then
        note("save: invalid slot " .. tostring(slotNum)); return
    end
    local pc = getController()
    if pc == nil then note("save: no player controller."); return end
    local loadout = findComponent(pc, "Loadout")
    if not valid(loadout) then note("save: Loadout component not found."); return end

    local pieces, count = readWornArmor(loadout)
    if count == 0 then note("save: no armor currently worn — nothing to save."); return end

    local name = "Set " .. tostring(slotNum)
    local existed = loadouts.sets[slotNum] ~= nil
    loadouts.sets[slotNum] = { name = name, pieces = pieces }
    persist()
    note((existed and "overwrote " or "saved ") .. name .. " (" .. count .. " pieces): "
        .. describeSet(loadouts.sets[slotNum]))
end

-- ── public: apply the set in a fixed slot ───────────────────────────────────

function loadouts.applySlot(slotNum)
    local set = loadouts.sets[slotNum]
    if set == nil then
        note("Slot " .. tostring(slotNum) .. " is empty — Shift+F" .. tostring(slotNum) .. " saves your current armor there.")
        return
    end

    local pc = getController()
    if pc == nil then note("apply: no player controller."); return end
    local loadout = findComponent(pc, "Loadout")
    if not valid(loadout) then note("apply: Loadout component not found."); return end
    local invCtrl = findComponent(pc, "InventoryController")
    if not valid(invCtrl) then note("apply: InventoryController not found."); return end

    -- Equip is a game-object mutation: run the whole set on the game thread, resolving
    -- each piece's CURRENT bag slot right before use (equipping shuffles bag slots as
    -- the previously-worn piece returns to the bag, so never cache indices up front).
    ExecuteInGameThread(function()
        local equipped, skipped, missing = 0, 0, 0
        for _, row in ipairs(names.ArmorSlots) do
            local wantAsset = set.pieces[row.slot]
            if wantAsset then
                -- Already wearing the right piece? Skip — avoids a needless re-equip.
                local worn = itemInLoadoutSlot(loadout, row.slot)
                if worn and assetOf(worn) == wantAsset then
                    skipped = skipped + 1
                else
                    local inv, slot = findArmorInBags(pc, wantAsset)
                    if inv and slot then
                        local ok, err = pcall(function()
                            invCtrl:UseItemFromInventory(inv, slot)
                        end)
                        if ok then equipped = equipped + 1
                        else missing = missing + 1; note("equip failed for " .. pretty(wantAsset) .. ": " .. tostring(err)) end
                    else
                        missing = missing + 1
                        log(row.label .. ": '" .. pretty(wantAsset) .. "' not found in bags — skipped.")
                    end
                end
            end
        end
        note("applied " .. set.name .. " — " .. equipped .. " equipped, "
            .. skipped .. " already on" .. (missing > 0 and (", " .. missing .. " missing") or ""))
    end)
end

return loadouts
