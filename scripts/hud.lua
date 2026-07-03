--[[
    Sylore Quick Swap - hud.lua
    Loaded-ammo color dot: a tiny square of OUR OWN widgetry near the reticle,
    recolored on each V swap by DESTROY + RECREATE (never mutate a live widget
    beyond the ops proven safe by gates G1-G3, see hudgate.lua / the 2026-07-03
    plan). Native game widgets are never touched — that path hard-crashes.

    Public surface: hud.setDot(assetName) — best-effort, never throws.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
local config    = require("config")

local hud = {}

local function log(msg)
    if config.Verbose then print("[Sylore Quick Swap] hud: " .. tostring(msg)) end
end

local function valid(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj.IsValid ~= nil and obj:IsValid() end)
    return ok and v or false
end

local state = { widget = nil }

-- First matching ColorMap entry (case-insensitive substring, in order) or default.
local function colorFor(asset)
    local hay = string.lower(asset or "")
    for _, entry in ipairs(config.ColorMap or {}) do
        if string.find(hay, string.lower(entry.match), 1, true) then return entry.color end
    end
    return config.ColorDefault
end

-- Center-bottom-ish position: viewport center + DotOffsetY, DPI-corrected.
local function dotPosition(pc)
    local x, y = 960.0, 590.0  -- sane fallback (1080p center-ish)
    pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local vs = wll:GetViewportSize(pc)
        local scale = wll:GetViewportScale(pc)
        if scale and scale > 0 then
            x = (vs.X / scale) / 2.0
            y = (vs.Y / scale) / 2.0 + (config.DotOffsetY or 50.0)
        end
    end)
    return x, y
end

-- Field-by-float tint (never marshal a table into a color struct).
local function setColorFields(image, col)
    local c = image.ColorAndOpacity
    c.R = col.R
    c.G = col.G
    c.B = col.B
    c.A = 1.0
end

-- The G1-proven creation path: UserWidget shell + UImage root, tinted
-- pre-viewport, then sized/positioned (G2-proven) after AddToViewport.
local function createDot(col)
    local pc = UEHelpers:GetPlayerController()
    if not valid(pc) then return nil end
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    local imageClass  = StaticFindObject("/Script/UMG.Image")
    local wbl         = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if widgetClass == nil or imageClass == nil or wbl == nil then return nil end

    local w = wbl:Create(pc, widgetClass, pc)
    if not valid(w) then return nil end
    local img = StaticConstructObject(imageClass, w.WidgetTree, FName("SQSDotImage"))
    if not valid(img) then return nil end
    w.WidgetTree.RootWidget = img
    setColorFields(img, col)
    w:AddToViewport(100)

    local size = config.DotSize or 16.0
    local px, py = dotPosition(pc)
    w:SetDesiredSizeInViewport({ X = size, Y = size })
    w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
    w:SetPositionInViewport({ X = px, Y = py }, false)
    return w
end

-- Public: replace the dot NOW — caller must ALREADY be on the game thread
-- (swap's load closure calls this). Best-effort: fully pcall'd, never throws.
function hud.applyDot(assetName)
    if not config.ShowColorDot then return end
    local okCol, col = pcall(colorFor, assetName)
    if not okCol or col == nil then col = config.ColorDefault end
    local ok, err = pcall(function()
        if valid(state.widget) then
            state.widget:RemoveFromParent()   -- G3-proven on OWN widgets
        end
        state.widget = nil
        state.widget = createDot(col)
    end)
    if not ok then log("applyDot failed: " .. tostring(err)) end
end

-- Public: same, but safe from any thread (queues onto the game thread).
function hud.setDot(assetName)
    if not config.ShowColorDot then return end
    ExecuteInGameThread(function() hud.applyDot(assetName) end)
end

return hud
