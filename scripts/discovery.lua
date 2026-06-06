--[[
    Sylore Quick Swap - discovery.lua  (Phase 1 harness)

    Output strategy (IMPORTANT): every line is written to RQS.LOGFILE with an
    open-append-close per line, which forces a flush to disk. UE4SS's own
    UE4SS.log buffers writes, so a C++ access-violation crash (uncatchable by Lua
    pcall) loses everything since the last flush — making the crash point
    invisible. The flushed file always shows the EXACT last line before a crash.

    Discovery keys (see main.lua / config.lua):
      F8 -> RQS.dumpStaff()        : dump the equipped staff (props then funcs)
      F9 -> RQS.dumpCombatMagic()  : dump the BP_Components_PlayerCombatMagic comp
      F7 -> RQS.armRuneHooks()     : hook candidate set-rune fns; then click a rune

    Props are dumped BEFORE funcs so if the function walk crashes, the rune
    properties + available-runes array are already saved. The discovery-*.txt files
    are written into the mod folder.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
RQS = RQS or {}

-- Output goes into the mod folder (resolved at runtime from this script's path, so
-- there's no machine-specific path). Each command writes its OWN file so dumps don't
-- clobber each other in one session.
local function modRoot()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        local p = src:gsub("^@", "")
        local dir = p:match("^(.*[/\\])")
        if dir and dir ~= "" then return (dir:gsub("[Ss]cripts[/\\]$", "")) end
    end
    return "./"   -- fall back to the process working dir (e.g. when pasted into console)
end
RQS.LOGDIR  = modRoot()
RQS._file   = RQS.LOGDIR .. "discovery-out.txt"

-- ── flushed output ─────────────────────────────────────────────────────────
-- Write one line to console AND to the flushed file (open/append/close = flush),
-- so a later C++ crash can't lose the tail.
local function w(line)
    line = tostring(line)
    print("[RQS] " .. line)
    local ok, f = pcall(io.open, RQS._file, "a")
    if ok and f then f:write(line .. "\n"); f:close() end
end
local function p(s) w(s) end

-- Point at a fresh per-command file, truncate it, and stamp a run header.
local function resetLog(fname, title)
    RQS._file = RQS.LOGDIR .. fname
    local ok, f = pcall(io.open, RQS._file, "w")
    if ok and f then f:write("=== " .. tostring(title) .. " ===\n"); f:close() end
    print("[RQS] (log reset) " .. RQS._file)
end

-- ── safe primitives ────────────────────────────────────────────────────────

function RQS.fq(o)
    if o == nil then return "nil" end
    local ok, name = pcall(function() return o:GetFullName() end)
    return ok and name or tostring(o)
end

local function classOf(o)
    if o == nil then return nil end
    local ok, c = pcall(function() return o:GetClass() end)
    return ok and c or nil
end

local function isValid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o.IsValid ~= nil and o:IsValid() end)
    return ok and v or false
end

local function propType(prop)
    local ok, c = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return ok and c or "?"
end

-- Read obj[name] safely (Lua pcall can't stop a C++ access violation, so only
-- use on properties expected to be safe scalars/objects).
function RQS.read(obj, name)
    local ok, v = pcall(function() return obj[name] end)
    if not ok then return nil end
    return v
end

local KEYWORDS = {
    "equip","inventory","weapon","combat","item","hotbar","loadout","ammo",
    "rune","spell","magic","staff","cast","ability","slot","wield","held",
    "active","current","selected","select","projectile","arrow","bow","quiver",
    "set","cycle","next","prev","swap","switch","change","toggle",
}
local function interesting(s)
    if s == nil then return false end
    s = string.lower(tostring(s))
    for _, k in ipairs(KEYWORDS) do
        if string.find(s, k, 1, true) then return true end
    end
    return false
end

-- Walk the class + its whole superclass chain. UE4SS ForEachProperty/
-- ForEachFunction only cover the EXACT class, so native parent members need this.
-- CRITICAL: stop at real UStruct/UClass objects only. Past CoreUObject.Object,
-- GetSuperStruct can return an unresolved metaclass pointer (fq = "UClass: 0x..")
-- whose ForEachProperty HARD-CRASHES the game. We detect those by the absence of a
-- "/Script/" or "/Game/" path in the full name and stop the walk there.
local function looksLikeRealStruct(id)
    return id ~= "nil"
        and (string.find(id, "/Script/", 1, true) ~= nil
          or string.find(id, "/Game/",   1, true) ~= nil)
end
local function forEachInChain(cls, cb)
    local seen, c, guard = {}, cls, 0
    while c ~= nil and guard < 20 do
        guard = guard + 1
        local id = RQS.fq(c)
        if not looksLikeRealStruct(id) or seen[id] then break end
        seen[id] = true
        cb(c, id)
        -- Root reached? UObject has no real super; anything "above" it is the
        -- engine metaclass and unsafe to enumerate.
        if string.find(id, "/Script/CoreUObject.Object", 1, true) then break end
        local ok, sup = pcall(function() return c:GetSuperStruct() end)
        if not ok then ok, sup = pcall(function() return c:GetSuperClass() end) end
        c = (ok and sup ~= nil) and sup or nil
    end
end

-- ── dumpers (metadata only; never reads arbitrary property VALUES) ───────────

function RQS.dumpProps(obj, label)
    p("## " .. label .. " PROPERTIES: " .. RQS.fq(obj))
    p("   class: " .. RQS.fq(classOf(obj)))
    local cls = classOf(obj)
    if cls == nil then p("   (no class)"); return end
    local seen = {}
    forEachInChain(cls, function(c, id)
        p("   -- from " .. id .. " --")
        pcall(function()
            c:ForEachProperty(function(prop)
                local nm = prop:GetFName():ToString()
                if seen[nm] then return end
                seen[nm] = true
                local mark = interesting(nm) and "  <<" or ""
                p("     ." .. nm .. "  [" .. propType(prop) .. "]" .. mark)
            end)
        end)
    end)
    p("## " .. label .. " PROPERTIES DONE")
end

function RQS.dumpFns(obj, label)
    p("## " .. label .. " FUNCTIONS: " .. RQS.fq(obj))
    local cls = classOf(obj)
    if cls == nil then p("   (no class)"); return end
    local seenF = {}
    forEachInChain(cls, function(c, id)
        -- Flush a marker BEFORE enumerating so a crash pinpoints the exact class.
        p("   -- fns from " .. id .. " --")
        if c.ForEachFunction == nil then return end
        pcall(function()
            c:ForEachFunction(function(fn)
                local nm = fn:GetFName():ToString()
                if seenF[nm] then return end
                seenF[nm] = true
                local mark = interesting(nm) and "  <<" or ""
                p("     :" .. nm .. "()" .. mark)
            end)
        end)
    end)
    p("## " .. label .. " FUNCTIONS DONE")
end

-- ── navigation ──────────────────────────────────────────────────────────────

local function getComponentByName(pawn, substr)
    local cls, found = classOf(pawn), nil
    if cls == nil then return nil end
    pcall(function()
        cls:ForEachProperty(function(prop)
            if found ~= nil then return end
            local nm = prop:GetFName():ToString()
            if string.find(string.lower(nm), string.lower(substr), 1, true) then
                local v = RQS.read(pawn, nm)
                if isValid(v) then found = v end
            end
        end)
    end)
    return found
end

local function getPawn()
    local pc = UEHelpers:GetPlayerController()
    return isValid(pc) and pc.Pawn or nil
end

-- Collect ALL component refs on obj whose property name matches substr, deduped by
-- the component's class (so we dump each distinct subsystem once).
local function collectComponents(obj, substr)
    local out, seen = {}, {}
    local cls = classOf(obj)
    if cls == nil then return out end
    pcall(function()
        cls:ForEachProperty(function(prop)
            local nm = prop:GetFName():ToString()
            local ty = propType(prop)
            if (ty == "ObjectProperty" or ty == "WeakObjectProperty")
               and string.find(string.lower(nm), string.lower(substr), 1, true) then
                local v = RQS.read(obj, nm)
                if isValid(v) then
                    local id = RQS.fq(classOf(v))
                    if not seen[id] then seen[id] = true; out[#out + 1] = { name = nm, obj = v } end
                end
            end
        end)
    end)
    return out
end

function RQS.getStaff()
    local pawn = getPawn()
    if not isValid(pawn) then return nil end
    local equip = getComponentByName(pawn, "PlayerEquipment")
    if not equip then return nil end
    return RQS.read(equip, "HeldEquipmentActorRight")
end

-- ── top-level discovery commands ─────────────────────────────────────────────

-- F8: dump the equipped staff. Props first (where the rune lives), then funcs.
function RQS.dumpStaff()
    resetLog("discovery-staff.txt", "STAFF DUMP")
    local pawn = getPawn()
    p("PAWN: " .. RQS.fq(pawn))
    if not isValid(pawn) then p("!! pawn invalid — are you in-game/spawned?"); return end
    local staff = RQS.getStaff()
    p("STAFF (HeldEquipmentActorRight): " .. RQS.fq(staff))
    if not isValid(staff) then p("!! no staff equipped — equip the battlestaff first."); return end
    RQS.dumpProps(staff, "STAFF")
    RQS.dumpFns(staff, "STAFF")
    p("=== STAFF DUMP COMPLETE ===")
end

-- F9: dump the CombatMagic component (may own the active-rune selection instead).
function RQS.dumpCombatMagic()
    resetLog("discovery-combatmagic.txt", "COMBATMAGIC DUMP")
    local pawn = getPawn()
    p("PAWN: " .. RQS.fq(pawn))
    if not isValid(pawn) then p("!! pawn invalid — are you in-game/spawned?"); return end
    local cm = getComponentByName(pawn, "PlayerCombatMagic")
    p("COMBATMAGIC: " .. RQS.fq(cm))
    if not isValid(cm) then p("!! no PlayerCombatMagic component found."); return end
    RQS.dumpProps(cm, "COMBATMAGIC")
    RQS.dumpFns(cm, "COMBATMAGIC")
    p("=== COMBATMAGIC DUMP COMPLETE ===")
end

-- List every component reference on the pawn (name -> class). Only reads object
-- properties whose name looks like a component, which has been crash-safe so far.
function RQS.listComponents(pawn)
    p("-- pawn components --")
    local cls = classOf(pawn)
    if cls == nil then p("   (no class)"); return end
    forEachInChain(cls, function(c)
        pcall(function()
            c:ForEachProperty(function(prop)
                local nm = prop:GetFName():ToString()
                local ty = propType(prop)
                if (ty == "ObjectProperty" or ty == "WeakObjectProperty")
                   and (string.find(nm, "Component", 1, true)
                        or string.find(nm, "BP_Components", 1, true)) then
                    local v = RQS.read(pawn, nm)
                    if isValid(v) then p("   ." .. nm .. "  ->  " .. RQS.fq(classOf(v))) end
                end
            end)
        end)
    end)
end

-- F9 (new): map the player character + the selection-bearing components. The
-- active-rune ("magic ammo") selection + a set/cycle function should be here.
function RQS.dumpPlayer()
    resetLog("discovery-player.txt", "PLAYER DUMP")
    local pawn = getPawn()
    p("PAWN: " .. RQS.fq(pawn))
    if not isValid(pawn) then p("!! pawn invalid — are you in-game/spawned?"); return end

    RQS.listComponents(pawn)

    -- The character BP itself often holds the high-level input/gameplay API.
    RQS.dumpProps(pawn, "PAWN")
    RQS.dumpFns(pawn, "PAWN")

    -- Other components that plausibly own ammo/rune selection or combat mode.
    for _, substr in ipairs({ "PlayerCombatMode", "PlayerRangedAttack", "PlayerUtilityMagic",
                              "Inventory", "Ammo" }) do
        local comp = getComponentByName(pawn, substr)
        if isValid(comp) then
            p(">>> component match for '" .. substr .. "': " .. RQS.fq(comp))
            RQS.dumpProps(comp, substr)
            RQS.dumpFns(comp, substr)
        else
            p(">>> no component matched '" .. substr .. "'")
        end
    end
    p("=== PLAYER DUMP COMPLETE ===")
end

-- F8 (repurposed): the equip/inventory path. Runes are "magic ammo" equipped via
-- the equipment system, so the swap function lives on the PlayerEquipment component
-- (its FUNCTIONS were never captured — the first crash) or the PlayerController
-- (inventory). Dump both, plus the controller's component list.
function RQS.dumpEquipAndController()
    resetLog("discovery-equip.txt", "EQUIP + CONTROLLER DUMP")
    local pawn = getPawn()
    p("PAWN: " .. RQS.fq(pawn))
    if not isValid(pawn) then p("!! pawn invalid — are you in-game/spawned?"); return end

    local equip = getComponentByName(pawn, "PlayerEquipment")
    p(">>> PlayerEquipment: " .. RQS.fq(equip))
    if isValid(equip) then
        RQS.dumpProps(equip, "EQUIPMENT")
        RQS.dumpFns(equip, "EQUIPMENT")   -- the equip/unequip/set-ammo API we still need
    end

    local pc = UEHelpers:GetPlayerController()
    p(">>> PlayerController: " .. RQS.fq(pc))
    if isValid(pc) then
        p("-- controller components --")
        RQS.listComponents(pc)            -- inventory may be a component on the controller
        RQS.dumpProps(pc, "CONTROLLER")
        RQS.dumpFns(pc, "CONTROLLER")
    end
    p("=== EQUIP + CONTROLLER DUMP COMPLETE ===")
end

-- F8 (repurposed again): the controller-side magic/inventory subsystems. The
-- active-rune ("magic ammo") selection + set/cycle function should live on the
-- Spellcasting component or the Loadout/Inventory components.
function RQS.dumpControllerSubsystems()
    resetLog("discovery-magic.txt", "CONTROLLER SUBSYSTEMS DUMP")
    local pc = UEHelpers:GetPlayerController()
    p("CONTROLLER: " .. RQS.fq(pc))
    if not isValid(pc) then p("!! no controller"); return end
    local dumped = {}
    for _, t in ipairs({ "Spellcasting", "Loadout", "Inventory", "AutoEquip" }) do
        for _, e in ipairs(collectComponents(pc, t)) do
            local id = RQS.fq(classOf(e.obj))
            if not dumped[id] then
                dumped[id] = true
                p(">>> [" .. t .. "] ." .. e.name .. "  =  " .. id)
                RQS.dumpProps(e.obj, e.name)
                RQS.dumpFns(e.obj, e.name)
            end
        end
    end
    p("=== CONTROLLER SUBSYSTEMS DUMP COMPLETE ===")
end

-- ── signature dumper ─────────────────────────────────────────────────────────
-- Hook-tracing the right-click "load rune" is a dead end: UE4SS RegisterHook only
-- fires on ProcessEvent-routed calls, and the actual inventory mutation runs via
-- direct C++ / locally-executed RPC that bypasses it. So instead we CALL the
-- inventory API ourselves. To do that we need each candidate function's exact
-- parameter list (name/type/flags) — all metadata, no value reads, crash-safe.

local SIG_WANT = {
    "moveitem", "useitem", "additem", "removeitem", "removefromslot",
    "getitemfromslot", "getslotindex", "getslotforslot", "getequipmentfromslot",
    "getslotforitem", "getallitems", "isitemallowed", "findslotfromequipment",
    "containsitem", "getnumitems", "additemtoslot",
}
local function sigWanted(nm)
    local s = string.lower(nm)
    for _, k in ipairs(SIG_WANT) do if string.find(s, k, 1, true) then return true end end
    return false
end

-- Decode the CPF_* parameter flags so we can tell inputs / out-params / return value
-- apart (UE4SS Lua 5.4 has bitwise ops; guard everything since the API varies).
local function paramFlags(prop)
    local ok, f = pcall(function() return prop:GetPropertyFlags() end)
    if not ok or f == nil then return "" end
    local tags = {}
    local function has(bit)
        local ok2, r = pcall(function() return (f & bit) ~= 0 end)
        return ok2 and r
    end
    if has(0x0000000000000400) then tags[#tags + 1] = "RETURN" end
    if has(0x0000000000000100) then tags[#tags + 1] = "out" end
    if has(0x0000000000000080) then tags[#tags + 1] = "in" end
    return #tags > 0 and ("  [" .. table.concat(tags, ",") .. "]") or "  [local?]"
end

local function dumpFnParams(fn)
    local any = false
    local ok = pcall(function()
        fn:ForEachProperty(function(prop)
            any = true
            local pn = prop:GetFName():ToString()
            p("        - " .. pn .. " : " .. propType(prop) .. paramFlags(prop))
        end)
    end)
    if not ok then p("        (params unavailable)")
    elseif not any then p("        (no params / void)") end
end

-- Try hard to enumerate a UEnum's entries (the API name varies across UE4SS builds).
local function dumpEnum(enumObj, label)
    p(">>> ENUM " .. label .. " = " .. RQS.fq(enumObj))
    if not isValid(enumObj) then p("   (not found / not an enum)"); return end
    -- 1) ForEachName(name, value) — name comes back as an FName userdata; stringify it.
    if pcall(function()
        enumObj:ForEachName(function(n, v)
            local nm = (pcall(function() return n:ToString() end)) and n:ToString() or tostring(n)
            p("   " .. nm .. " = " .. tostring(v))
        end)
    end) then return end
    -- 2) GetNumEnums + GetNameByIndex/GetValueByIndex
    local okN, num = pcall(function() return enumObj:GetNumEnums() end)
    if okN and num then
        for i = 0, num - 1 do
            local n = (pcall(function() return enumObj:GetNameByIndex(i) end)) and enumObj:GetNameByIndex(i) or "?"
            local v = (pcall(function() return enumObj:GetValueByIndex(i) end)) and enumObj:GetValueByIndex(i) or i
            p("   [" .. i .. "] " .. tostring(n) .. " = " .. tostring(v))
        end
        return
    end
    p("   (enum enumeration API unavailable — will resolve slot index at runtime)")
end

function RQS.dumpSignatures()
    resetLog("discovery-sig.txt", "FUNCTION SIGNATURES (callable inventory API)")
    local pc = UEHelpers:GetPlayerController()
    p("CONTROLLER: " .. RQS.fq(pc))
    if not isValid(pc) then p("!! no controller"); return end

    local dumped, loadout = {}, nil
    for _, t in ipairs({ "Inventory", "Loadout" }) do
        for _, e in ipairs(collectComponents(pc, t)) do
            local id = RQS.fq(classOf(e.obj))
            if not dumped[id] then
                dumped[id] = true
                if t == "Loadout" and loadout == nil then loadout = e.obj end
                p(">>> COMPONENT ." .. e.name .. "  =  " .. id)
                local cls = classOf(e.obj)
                forEachInChain(cls, function(c, cid)
                    if c.ForEachFunction == nil then return end
                    pcall(function()
                        c:ForEachFunction(function(fn)
                            local nm = fn:GetFName():ToString()
                            if sigWanted(nm) then
                                p("   :" .. nm .. "()   (from " .. cid .. ")")
                                dumpFnParams(fn)
                            end
                        end)
                    end)
                end)
                p("## " .. e.name .. " SIGNATURES DONE")
            end
        end
    end

    -- The MagicAmmo1 slot's enum value (input to GetSlotIndexForSlot).
    if isValid(loadout) then
        local enumObj = RQS.read(loadout, "LoadoutSlotEnum")
        dumpEnum(enumObj, "LoadoutSlotEnum")
    end
    p("=== SIGNATURES DUMP COMPLETE ===")
end

-- ── runtime rune probe ───────────────────────────────────────────────────────
-- With the API decoded from Dominion.hpp, this reads the LIVE rune state: the
-- currently-loaded rune (Loadout MagicAmmo1 slot) and the contents of every player
-- inventory, flagging rune items. Tells us which component holds the rune panel and
-- the air/fire slot indices — the last facts needed to write the cycle.

-- Call obj:fn(...) safely; returns (ok, result).
local function call(obj, fn, ...)
    if obj == nil then return false, nil end
    local a = { ... }
    return pcall(function() return obj[fn](obj, table.unpack(a)) end)
end

-- Leaf object name from a full name ("Class /Game/..Foo.Foo" -> "Foo").
local function leafName(fullname)
    local dot = fullname:match("%.([^%.]+)$")
    return dot or fullname
end

-- Best-effort readable item identity. The ItemData ASSET name (e.g. DA_MagicAmmo_Air)
-- is the stable, language-independent key — player-facing FText names come back as
-- "<MISSING STRING TABLE ENTRY>" on a non-English client, so we lead with the asset.
local function itemDesc(item)
    if not isValid(item) then return "(empty)" end
    local data = RQS.read(item, "ItemData")
    local dataFull = isValid(data) and RQS.fq(data) or "nil"
    local dataCls = isValid(data) and leafName(RQS.fq(classOf(data))) or "nil"
    local name = "?"
    local okN, ft = call(item, "GetPlayerFacingName")
    if okN and ft ~= nil then
        local okS, s = pcall(function() return ft:ToString() end)
        if okS then name = s end
    end
    return "asset=" .. leafName(dataFull) .. "  class=" .. dataCls
        .. "  name=\"" .. name .. "\"  (" .. dataFull .. ")"
end

-- Enumerate an inventory using the GAME's own GetItemFromSlot(i) so the printed
-- index is the true slot index that UseItemFromInventory expects (raw array indexing
-- is off-by-one vs the game's slot space). Rune lines (MagicAmmoData) are marked.
local function dumpInventoryItems(inv, label)
    p(">>> " .. label .. " = " .. RQS.fq(inv))
    if not isValid(inv) then p("   (invalid / not found)"); return end
    local slots = RQS.read(inv, "ItemSlots")
    local n = nil
    if slots ~= nil then local ok, c = pcall(function() return slots:GetArrayNum() end); if ok then n = c end end
    if n == nil then local ok, c = call(inv, "GetNumItems"); if ok then n = c end end
    if n == nil then p("   (could not size inventory)"); return end
    p("   slot range = 0.." .. tostring(n - 1) .. " (via GetItemFromSlot)")
    for i = 0, n - 1 do
        local okItem, it = call(inv, "GetItemFromSlot", i)
        if okItem and isValid(it) then
            local desc = itemDesc(it)
            local mark = string.find(desc, "MagicAmmoData", 1, true) and "  <<< RUNE" or ""
            p("   [" .. i .. "] " .. desc .. mark)
        end
    end
end

function RQS.probeRunes()
    resetLog("discovery-runes.txt", "LIVE RUNE STATE PROBE")
    local pc = UEHelpers:GetPlayerController()
    p("CONTROLLER: " .. RQS.fq(pc))
    if not isValid(pc) then p("!! no controller"); return end

    local loadout = (collectComponents(pc, "Loadout")[1] or {}).obj
    local invCtrl = (collectComponents(pc, "InventoryController")[1] or {}).obj
    p("Loadout            = " .. RQS.fq(loadout))
    p("InventoryController = " .. RQS.fq(invCtrl))

    -- Current loaded rune: Loadout:GetItemFromSlot(GetSlotIndexForSlot(MagicAmmo1=6))
    p("--- CURRENT LOADED RUNE (MagicAmmo1 slot) ---")
    local okIdx, slotIdx = call(loadout, "GetSlotIndexForSlot", 6)
    p("GetSlotIndexForSlot(MagicAmmo1=6) -> " .. tostring(okIdx and slotIdx or "ERR"))
    if okIdx and slotIdx ~= nil and slotIdx >= 0 then
        local okItem, item = call(loadout, "GetItemFromSlot", slotIdx)
        p("  loaded item = " .. (okItem and itemDesc(item) or "ERR"))
    end

    -- Every inventory's contents (find where air/fire live + their slot indices).
    p("--- INVENTORY CONTENTS (look for rune items) ---")
    local dumped = {}
    for _, t in ipairs({ "Loadout", "Inventory", "PersonalInventory" }) do
        for _, e in ipairs(collectComponents(pc, t)) do
            local id = RQS.fq(classOf(e.obj))
            if not dumped[id] then
                dumped[id] = true
                dumpInventoryItems(e.obj, t .. " ." .. e.name)
            end
        end
    end
    p("=== RUNE PROBE COMPLETE ===")
end

-- Keep the old name as an alias so nothing breaks if referenced elsewhere.
RQS.discoverEquipment = RQS.dumpStaff

-- ── manual fallbacks (GUI console) ───────────────────────────────────────────

function RQS.find(className)
    local all = FindAllOf(className)
    if all == nil then p("FindAllOf('" .. className .. "') -> nil"); return nil end
    local n = 0
    for _, o in pairs(all) do n = n + 1; if n <= 25 then p(n .. ": " .. RQS.fq(o)) end end
    p("FindAllOf('" .. className .. "') -> " .. n .. " instance(s)")
    return all
end

-- The right-click "load rune" action does NOT use the obvious inventory verbs
-- (UseItemFromInventory/MoveItemBetweenInventories/AddItemToSlot all stayed silent).
-- So instead of guessing names, auto-hook EVERY verb-like function across the
-- inventory / loadout / auto-equip / equipment / magic components and watch which
-- fires on a single rune swap. Optional manual override list:
RQS._candidates = {}

-- Safely turn one hooked arg into a readable string.
local function argStr(a)
    local ok, v = pcall(function() return a:get() end)
    if not ok then return "?" end
    if type(v) == "userdata" then
        local okf, s = pcall(function() return RQS.fq(v) end)
        if okf and s ~= "nil" then return s end
        local okt, t = pcall(function() return v:ToString() end)
        if okt then return t end
        return "<userdata>"
    end
    return tostring(v)
end

-- Strip the "Class "/"BlueprintGeneratedClass " prefix from a full name to get the
-- path UE4SS RegisterHook wants (e.g. "/Script/Dominion.InventoryController").
local function classPath(c)
    local id = RQS.fq(c)
    local sp = string.find(id, " ", 1, true)
    return sp and string.sub(id, sp + 1) or id
end

-- HOOK-ALL strategy: two prior traces (include-keyword filtered) only ever caught the
-- DOWNSTREAM notification (OnReceiveInventoryChanged / OnInventoryChanged_LoadoutFTUE),
-- never the mutator. The mutator's name doesn't match our guessed verbs. So: hook
-- EVERYTHING on a tight target set (PlayerController + its inventory components, NOT the
-- pawn) and exclude only known noise. The cause = the fn that fires ONCE just before the
-- OnInventoryChanged storm. A sequence counter (RQS._seq) preserves call order.
local HOOK_EXCLUDE = {
    -- pure getters / queries (never the mutator)
    "get", "is", "has", "find", "compute", "can", "contains", "num", "query",
    "sort", "calculate", "weight", "space",
    -- replication + the notification storms we already identified (kill the noise)
    "onrep", "onreceive", "inventorychanged", "loadoutchanged", "ftue", "changed",
    "replicat", "marknetdirty",
    -- per-frame / cosmetic / unrelated systems
    "tick", "update", "anim", "montage", "sound", "audio", "vfx", "cosmetic",
    "predict", "interp", "camera", "rotation", "location", "velocity", "input",
    "cursor", "mouse", "hover", "tooltip", "widget", "notification", "display",
    "debug", "telemetry",
    -- unrelated gameplay verbs
    "craft", "sell", "repair", "compost", "split", "rejected",
}
local function wantHook(nm)
    local s = string.lower(nm)
    for _, e in ipairs(HOOK_EXCLUDE) do if string.find(s, e, 1, true) then return false end end
    return true
end

-- Collect hookable "Class:Func" names from obj's whole class chain into out/seen.
local function collectHookNames(obj, out, seen)
    local cls = classOf(obj)
    if cls == nil then return end
    forEachInChain(cls, function(c)
        if c.ForEachFunction == nil then return end
        local path = classPath(c)
        pcall(function()
            c:ForEachFunction(function(fn)
                local nm = fn:GetFName():ToString()
                if wantHook(nm) then
                    local full = path .. ":" .. nm
                    if not seen[full] then seen[full] = true; out[#out + 1] = full end
                end
            end)
        end)
    end)
end

function RQS.armRuneHooks(candidates)
    resetLog("discovery-hooks.txt", "HOOKS ARMED — now swap ONE rune (right-click load), then come back")
    local names, seen = {}, {}

    if candidates and #candidates > 0 then
        for _, f in ipairs(candidates) do if not seen[f] then seen[f] = true; names[#names + 1] = f end end
    else
        -- Gather target components and auto-collect their verb functions.
        local pc = UEHelpers:GetPlayerController()
        local pawn = getPawn()
        local objs = {}
        if isValid(pc) then
            -- The controller ITSELF is a Dominion.InventoryController subclass — its own
            -- class chain holds the Server_ RPCs the right-click-load actually calls.
            -- (Previous traces only hooked its child components and caught nothing.)
            objs[#objs + 1] = pc
            for _, t in ipairs({ "Inventory", "Loadout", "AutoEquip", "Spellcasting" }) do
                for _, e in ipairs(collectComponents(pc, t)) do objs[#objs + 1] = e.obj end
            end
        end
        -- NOTE: pawn deliberately EXCLUDED — its Actor/Character chain floods the trace
        -- with per-frame movement calls. The rune load is controller/inventory-side.
        for _, o in ipairs(objs) do collectHookNames(o, names, seen) end
    end

    p("hooking " .. #names .. " candidate function(s)...")
    RQS._seq = 0
    local hooked = 0
    for _, fname in ipairs(names) do
        local ok = pcall(function()
            RegisterHook(fname, function(self, ...)
                local args = { ... }
                local parts = {}
                for i = 1, #args do parts[i] = argStr(args[i]) end
                RQS._seq = RQS._seq + 1
                p("[" .. RQS._seq .. "] HOOK FIRED: " .. fname)
                p("   self = " .. RQS.fq(self and self:get()))
                p("   args[" .. #args .. "] = " .. table.concat(parts, "  |  "))
            end)
        end)
        if ok then hooked = hooked + 1 else p("FAILED to hook: " .. fname) end
    end
    p("armed " .. hooked .. "/" .. #names .. " hooks. Now right-click-load a different rune.")
    if #names == 0 then p("(no functions matched — are you in-game/spawned?)") end
end

p("discovery.lua loaded. F8=probeRunes, F9=dumpPlayer, F7=armRuneHooks(broad)")
