--[[
    Sylore Quick Swap - hud.lua
    Loaded-ammo color dot: a tiny square of OUR OWN widgetry near the reticle,
    recolored on each V swap by DESTROY + RECREATE (never mutate a live widget
    beyond the ops proven safe by gates G1-G3, see hudgate.lua / the 2026-07-03
    plan). Native game widgets are never touched — that path hard-crashes.

    Public surface:
      hud.applyDot(assetName, iconTex) — replace the dot NOW; caller MUST already be on the game thread (this is what swap.lua calls from inside its load closure). iconTex is optional (a live Texture2D, e.g. ItemData.AmmoCounterIcon); nil (or config.ShowIconOverlay=false) falls back to the plain color square.
      hud.setDot(assetName)   — same, safe from any thread (queues onto the game thread); no icon (used by nothing today).
    Both are best-effort and never throw.

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
-- tex is optional (a live Texture2D); when readable it's applied via the
-- G4-proven op (img.Brush.ResourceObject = tex, on OUR OWN image, pre-viewport)
-- and the widget is sized as an icon instead of a square.
local function createDot(col, tex)
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

    local usedIcon = false
    if tex ~= nil and valid(tex) then
        -- G4-proven on OWN image, pre-viewport; individually pcall'd so a bad
        -- texture degrades to the plain square instead of suppressing the dot.
        usedIcon = pcall(function() img.Brush.ResourceObject = tex end)
    end

    setColorFields(img, col)
    w:AddToViewport(100)
    state.widget = w   -- track the instant it's on the viewport, so a later throw can't orphan it

    local size = usedIcon and (config.IconSize or 32.0) or (config.DotSize or 16.0)
    local px, py = dotPosition(pc)
    w:SetDesiredSizeInViewport({ X = size, Y = size })
    w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
    w:SetPositionInViewport({ X = px, Y = py }, false)
    return w
end

-- True when the current world is networked (dedicated server client, co-op,
-- etc.). Replicated worlds can hand us icon textures the renderer can't
-- safely draw — drawing one hard-crashed a dedicated-server client on
-- 2026-07-03 (and showed garbage icons on another machine). So the icon
-- overlay is single-player only; networked worlds always get the square.
-- Fails SAFE: if we can't tell, we assume networked (cosmetic loss only).
local function worldIsNetworked()
    local ok, networked = pcall(function()
        local world = UEHelpers:GetWorld()
        if world == nil or not world:IsValid() then return true end
        local nd = world.NetDriver
        return nd ~= nil and nd.IsValid ~= nil and nd:IsValid()
    end)
    if not ok then return true end
    return networked
end

-- Public: replace the dot NOW — caller must ALREADY be on the game thread
-- (swap's load closure calls this). Best-effort: fully pcall'd, never throws.
-- iconTex is optional (nil -> plain color square, forwarded only when
-- config.ShowIconOverlay is true AND the world is single-player).
function hud.applyDot(assetName, iconTex)
    if not config.ShowColorDot then return end
    if not config.ShowIconOverlay then iconTex = nil end
    if iconTex ~= nil and worldIsNetworked() then
        log("networked world — icon overlay suppressed (square fallback)")
        iconTex = nil
    end
    local okCol, col = pcall(colorFor, assetName)
    if not okCol or col == nil then col = config.ColorDefault end
    local ok, err = pcall(function()
        if valid(state.widget) then
            state.widget:RemoveFromParent()   -- G3-proven on OWN widgets
        end
        state.widget = nil
        state.widget = createDot(col, iconTex)
    end)
    if not ok then log("applyDot failed: " .. tostring(err)) end
end

-- Public: same, but safe from any thread (queues onto the game thread).
-- No icon — used by nothing today; stays a thread-safe wrapper.
function hud.setDot(assetName)
    if not config.ShowColorDot then return end
    ExecuteInGameThread(function() hud.applyDot(assetName, nil) end)
end

return hud
