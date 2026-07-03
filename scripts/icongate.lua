--[[
    Sylore Quick Swap - icongate.lua
    Icon-overlay v2: probes for the ammo-icon overlay feature.

    scan() is a READ-ONLY, repeatable dump of the loaded ammo's ItemData
    properties (name + property class for every property; value too for any
    property whose name looks icon/brush/texture-related). It never mutates
    game state and never constructs a widget — safe to press F7 as often as
    you like.

    g4() is the ONE-SHOT probe: given a property name (config.IconGateProp,
    filled in by hand from scan's log output), it re-reads that property off
    the loaded ammo's ItemData, resolves it to a UTexture2D (directly, or via
    one StaticLoadObject attempt if it's a soft reference), and — only if a
    texture was obtained — builds ONE widget using the exact hudgate
    createDot shape, with a single extra insertion (img.Brush.ResourceObject
    = tex) between image construction and the tint. Survives => the whole
    icon-overlay feature is viable; hard-crashes => back to the color dot.

    Every dangerous op is preceded by a FLUSHED line to sqs-icongate.txt so a
    hard crash still identifies the killer op.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
local names     = require("names")
local config    = require("config")

local icongate = {}

-- Flushed file log: the last line before a crash is the diagnosis. Resolve
-- the mod folder from this script's own path (same proven trick as
-- hudgate.lua/discovery.lua) — a CWD-relative path would silently land nowhere.
local function modRoot()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        local p = src:gsub("^@", "")
        local dir = p:match("^(.*[/\\])")
        if dir and dir ~= "" then return (dir:gsub("[Ss]cripts[/\\]$", "")) end
    end
    return "./"
end
local LOGFILE = modRoot() .. "sqs-icongate.txt"
local function flog(msg)
    print("[SQS icongate] " .. msg)
    local f = io.open(LOGFILE, "a")
    if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n") f:close() end
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

-- ── loadout/component resolution (idioms copied from swap.lua) ────────────

-- First valid component property on `owner` whose name contains `want` and none of
-- the `excludes` (case-insensitive). Read-only.
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

-- An item's ItemData, or nil.
local function itemData(item)
    if not valid(item) then return nil end
    local ok, data = pcall(function() return item.ItemData end)
    if ok and valid(data) then return data end
    return nil
end

-- Ammo loadout slots to try, in order (names.lua is the one source of truth
-- for these enum values — see names.ELoadoutSlot / names.AmmoStrategies).
local AMMO_SLOTS = {
    names.ELoadoutSlot.MagicAmmo1,
    names.ELoadoutSlot.Ammo,
    names.ELoadoutSlot.CrossbowBolts,
}

-- Resolve the loaded ammo (item, ItemData) exactly as swap.lua does: first
-- valid item across the ammo slots, in order. Read-only. Returns (nil, nil)
-- if no ammo is loaded in any tracked slot.
local function resolveLoadedAmmo()
    local pc = UEHelpers:GetPlayerController()
    if not valid(pc) then return nil, nil end
    local loadout = findComponent(pc, "Loadout")
    if not valid(loadout) then return nil, nil end
    for _, slotEnum in ipairs(AMMO_SLOTS) do
        local item = itemInLoadoutSlot(loadout, slotEnum)
        if valid(item) then
            local data = itemData(item)
            if data ~= nil then return item, data end
        end
    end
    return nil, nil
end

-- ── scan: read-only ItemData icon property dump ────────────────────────────

local ICON_KEYWORDS = { "icon", "brush", "texture", "thumbnail", "sprite", "image" }

local function looksIconish(pname)
    local lower = string.lower(pname)
    for _, kw in ipairs(ICON_KEYWORDS) do
        if string.find(lower, kw, 1, true) then return true end
    end
    return false
end

-- Property class name via the codebase's proven idiom (discovery.lua propType):
-- prop:GetClass():GetFName():ToString(), one pcall, "?" on any failure.
local function propClassName(prop)
    local ok, c = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return ok and c or "?"
end

-- Dump every property name + property class on ItemData's class; for anything
-- icon/brush/texture-ish, also pcall-read the VALUE off ItemData and flog it.
-- Strictly read-only: no writes, no calls other than GetClass/GetFName/ForEachProperty
-- and plain property reads. Never throws (every risky read is individually pcall'd).
local function scanIconProperties(data)
    local okCls, cls = pcall(function() return data:GetClass() end)
    if not okCls or cls == nil then
        flog("scan: ItemData:GetClass() failed")
        return
    end
    local okEach, err = pcall(function()
        cls:ForEachProperty(function(prop)
            local okName, pname = pcall(function() return prop:GetFName():ToString() end)
            if not okName or pname == nil then pname = "?" end
            local pclass = propClassName(prop)
            flog(pname .. " : " .. pclass)

            if pname ~= "?" and looksIconish(pname) then
                local okv, v = pcall(function() return data[pname] end)
                if not okv then
                    flog("  -> " .. pname .. " value read FAILED: " .. tostring(v))
                elseif valid(v) then
                    flog("  -> " .. pname .. " value: " .. fullName(v))
                elseif v == nil then
                    flog("  -> " .. pname .. " value: nil")
                else
                    local okStr, s = pcall(function() return tostring(v) end)
                    flog("  -> " .. pname .. " value: " .. (okStr and s or "<unprintable>"))
                end
            end
        end)
    end)
    if not okEach then flog("scan: ForEachProperty error: " .. tostring(err)) end
end

-- F7: read-only ItemData icon property scan. Repeatable — press as often as needed.
function icongate.scan()
    flog("=== scan begin (read-only ItemData icon property dump) ===")
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local item, data = resolveLoadedAmmo()
            if data == nil then
                flog("scan: no loaded ammo item/ItemData found (load ammo onto the weapon first)")
                return
            end
            flog("scan: item = " .. fullName(item) .. ", ItemData = " .. fullName(data))
            scanIconProperties(data)
        end)
        if not ok then flog("scan: pcall error: " .. tostring(err)) end
        flog("=== scan end ===")
    end)
end

-- ── g4: one-shot brush probe ────────────────────────────────────────────────

-- Set an FLinearColor property FIELD BY FIELD (floats only — table->struct
-- marshalling into render properties crashed the renderer in June; see hudgate.lua).
local function setColorFields(image, r, g, b, a)
    local c = image.ColorAndOpacity
    c.R = r
    c.G = g
    c.B = b
    c.A = a
end

-- The exact hudgate createDot shape (UserWidget shell -> UImage root -> tint
-- pre-viewport -> AddToViewport), with ONE extra insertion after the image is
-- constructed and BEFORE the tint: img.Brush.ResourceObject = tex.
local function createIconDot(tex, r, g, b)
    local pc = UEHelpers:GetPlayerController()
    if not valid(pc) then flog("createIconDot: no player controller") return nil, nil end

    flog("createIconDot: resolving UMG classes")
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    local imageClass  = StaticFindObject("/Script/UMG.Image")
    local wbl         = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if widgetClass == nil or imageClass == nil or wbl == nil then
        flog("createIconDot: missing class (widget=" .. tostring(widgetClass ~= nil)
            .. " image=" .. tostring(imageClass ~= nil) .. " wbl=" .. tostring(wbl ~= nil) .. ")")
        return nil, nil
    end

    flog("createIconDot: DANGEROUS - WidgetBlueprintLibrary.Create(UserWidget)")
    local w = wbl:Create(pc, widgetClass, pc)
    if not valid(w) then flog("createIconDot: Create returned invalid") return nil, nil end
    flog("createIconDot: created " .. fullName(w))

    flog("createIconDot: DANGEROUS - StaticConstructObject(Image, outer=WidgetTree)")
    local img = StaticConstructObject(imageClass, w.WidgetTree, FName("SQSIconGateImage"))
    if not valid(img) then flog("createIconDot: image construct failed") return nil, nil end

    flog("createIconDot: DANGEROUS - WidgetTree.RootWidget = image")
    w.WidgetTree.RootWidget = img

    flog("createIconDot: DANGEROUS - img.Brush.ResourceObject = tex")
    img.Brush.ResourceObject = tex

    flog("createIconDot: DANGEROUS - tint OWN image pre-viewport, field floats")
    setColorFields(img, r, g, b, 1.0)

    flog("createIconDot: DANGEROUS - AddToViewport")
    w:AddToViewport(100)
    flog("createIconDot: SURVIVED - widget is live")
    return w, img
end

-- Try to pull a loadable asset path string off a non-UObject property value
-- (soft object path / soft object ptr shapes vary by build) — pcall-probed,
-- read-only, never throws. Returns a path string or nil.
local function tryExtractAssetPath(value)
    local okAp, ap = pcall(function() return value.AssetPathName end)
    if okAp and ap ~= nil then
        local okAps, aps = pcall(function() return tostring(ap) end)
        if okAps and type(aps) == "string" and aps ~= "" and aps ~= "None" then return aps end
    end
    local okStr, s = pcall(function() return tostring(value) end)
    if okStr and type(s) == "string" and string.find(s, "/Game/", 1, true) then return s end
    return nil
end

-- F8: ONE-SHOT probe. At most one StaticLoadObject and one widget construction.
function icongate.g4()
    flog("=== G4 begin (one-shot brush probe) ===")
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            if config.IconGateProp == "" then
                flog("G4: config.IconGateProp is empty - set it from the scan output first")
                return
            end

            local item, data = resolveLoadedAmmo()
            if data == nil then
                flog("G4: no loaded ammo item/ItemData found (load ammo onto the weapon first)")
                return
            end
            flog("G4: item = " .. fullName(item) .. ", ItemData = " .. fullName(data))

            local okv, value = pcall(function() return data[config.IconGateProp] end)
            if not okv then
                flog("G4: reading ItemData." .. tostring(config.IconGateProp) .. " FAILED: " .. tostring(value))
                return
            end

            local tex = nil
            if valid(value) then
                tex = value
                flog("G4: property value is a valid UObject: " .. fullName(tex))
            else
                flog("G4: property value is NOT a UObject: " .. tostring(value))
                local path = tryExtractAssetPath(value)
                if path == nil then
                    flog("G4: no usable asset path on the property value - aborting (no widget constructed)")
                    return
                end
                flog("G4: candidate asset path: " .. path)

                flog("G4: DANGEROUS - StaticFindObject(/Script/Engine.Texture2D)")
                local texClass = StaticFindObject("/Script/Engine.Texture2D")
                if texClass == nil then
                    flog("G4: Texture2D class not found - aborting (no widget constructed)")
                    return
                end

                flog("G4: DANGEROUS - StaticLoadObject(Texture2D, nil, " .. path .. ")")
                local okLoad, loaded = pcall(function() return StaticLoadObject(texClass, nil, path) end)
                if not okLoad or not valid(loaded) then
                    flog("G4: StaticLoadObject failed or returned invalid - aborting (no widget constructed)")
                    return
                end
                tex = loaded
                flog("G4: StaticLoadObject SURVIVED - loaded " .. fullName(tex))
            end

            if not valid(tex) then
                flog("G4: no usable texture - aborting (no widget constructed)")
                return
            end

            local w, img = createIconDot(tex, 1.0, 0.1, 0.1)
            if not valid(w) or not valid(img) then
                flog("G4: widget construction failed")
                return
            end

            flog("G4: DANGEROUS - SetDesiredSizeInViewport({48,48}) table arg")
            w:SetDesiredSizeInViewport({ X = 48.0, Y = 48.0 })
            flog("G4: DANGEROUS - SetAlignmentInViewport({0.5,0.5}) table arg")
            w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
            flog("G4: DANGEROUS - SetPositionInViewport(960,590) table arg")
            w:SetPositionInViewport({ X = 960.0, Y = 590.0 }, false)

            flog("G4 SURVIVED — tinted icon should be visible")
        end)
        if not ok then flog("G4: pcall error: " .. tostring(err)) end
        flog("=== G4 end ===")
    end)
end

return icongate
