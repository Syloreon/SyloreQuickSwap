--[[
    Sylore Quick Swap - hudgate.lua
    ONE-ATTEMPT gate probes for the loaded-ammo color dot (Approach A).

    Proves (or kills) the claim that widgets WE create from Lua are safe to
    create (G1), position (G2), and destroy+recreate (G3) on this UE4SS build.
    June 2026 proved mutating NATIVE widgets always hard-crashes; these gates
    only ever touch widgets constructed here.

    Every dangerous op is preceded by a FLUSHED line to sqs-hudgate.txt so a
    hard crash still identifies the killer op. Any hard crash at any gate =>
    Approach A is permanently dead (fall back to toast text, Approach C).

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")

local hudgate = {}

-- Flushed file log: the last line before a crash is the diagnosis.
local LOGFILE = "Mods/SyloreQuickSwap/sqs-hudgate.txt"
local function flog(msg)
    print("[SQS hudgate] " .. msg)
    local f = io.open(LOGFILE, "a")
    if f then f:write(os.date("%H:%M:%S ") .. msg .. "\n") f:close() end
end

local function valid(obj)
    if obj == nil then return false end
    local ok, v = pcall(function() return obj.IsValid ~= nil and obj:IsValid() end)
    return ok and v or false
end

-- Gate state: the one live widget + its image, shared across G1/G2/G3.
local state = { widget = nil, image = nil }

-- Set an FLinearColor property FIELD BY FIELD (floats only — table->struct
-- marshalling into render properties crashed the renderer in June).
local function setColorFields(image, r, g, b, a)
    local c = image.ColorAndOpacity
    c.R = r
    c.G = g
    c.B = b
    c.A = a
end

-- Shared creation path (also the shape hud.lua will reuse if gates pass):
-- UserWidget shell -> UImage as its root -> tint pre-viewport -> AddToViewport.
local function createDot(r, g, b)
    local pc = UEHelpers:GetPlayerController()
    if not valid(pc) then flog("createDot: no player controller") return nil, nil end

    flog("createDot: resolving UMG classes")
    local widgetClass = StaticFindObject("/Script/UMG.UserWidget")
    local imageClass  = StaticFindObject("/Script/UMG.Image")
    local wbl         = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if widgetClass == nil or imageClass == nil or wbl == nil then
        flog("createDot: missing class (widget=" .. tostring(widgetClass ~= nil)
            .. " image=" .. tostring(imageClass ~= nil) .. " wbl=" .. tostring(wbl ~= nil) .. ")")
        return nil, nil
    end

    flog("createDot: DANGEROUS - WidgetBlueprintLibrary.Create(UserWidget)")
    local w = wbl:Create(pc, widgetClass, pc)
    if not valid(w) then flog("createDot: Create returned invalid") return nil, nil end
    flog("createDot: created " .. w:GetFullName())

    flog("createDot: DANGEROUS - StaticConstructObject(Image, outer=WidgetTree)")
    local img = StaticConstructObject(imageClass, w.WidgetTree, FName("SQSDotImage"))
    if not valid(img) then flog("createDot: image construct failed") return nil, nil end

    flog("createDot: DANGEROUS - WidgetTree.RootWidget = image")
    w.WidgetTree.RootWidget = img

    flog("createDot: DANGEROUS - tint OWN image pre-viewport, field floats")
    setColorFields(img, r, g, b, 1.0)

    flog("createDot: DANGEROUS - AddToViewport")
    w:AddToViewport(100)
    flog("createDot: SURVIVED - widget is live (unsized: may cover the screen until G2)")
    return w, img
end

-- G1: create our own widget (red), add to viewport. WARNING shown to user:
-- until G2 sizes it, the image may tint a large area — that is EXPECTED.
function hudgate.g1()
    flog("=== G1 begin (create own widget, red, AddToViewport) ===")
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            state.widget, state.image = createDot(1.0, 0.1, 0.1)
        end)
        if not ok then flog("G1: pcall error: " .. tostring(err)) end
        flog("=== G1 end (if you can read this in the log, no hard crash) ===")
    end)
end

-- G2: size + position OUR OWN widget near the reticle. First try the concise
-- table-arg form; if the table form errors SOFTLY (pcall), retry with a
-- field-write fallback. A HARD crash here = gate failed, Approach A dead.
function hudgate.g2()
    flog("=== G2 begin (size + position own widget) ===")
    ExecuteInGameThread(function()
        local w = state.widget
        if not valid(w) then flog("G2: no live widget - run G1 first") return end
        local ok, err = pcall(function()
            flog("G2: DANGEROUS - SetDesiredSizeInViewport({16,16}) table arg")
            w:SetDesiredSizeInViewport({ X = 16.0, Y = 16.0 })
            flog("G2: DANGEROUS - SetAlignmentInViewport({0.5,0.5}) table arg")
            w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
            flog("G2: DANGEROUS - SetPositionInViewport(center-ish) table arg")
            w:SetPositionInViewport({ X = 960.0, Y = 590.0 }, false)
            flog("G2: SURVIVED - dot should be a small red square just below center")
        end)
        if not ok then flog("G2: soft pcall error (NOT a hard crash): " .. tostring(err)) end
        flog("=== G2 end ===")
    end)
end

-- G3: the production update path — remove the old widget, create a fresh one
-- in a different color (blue). Survives => the whole feature is viable.
function hudgate.g3()
    flog("=== G3 begin (remove + recreate in blue) ===")
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            local w = state.widget
            if valid(w) then
                flog("G3: DANGEROUS - RemoveFromParent on OWN widget")
                w:RemoveFromParent()
                flog("G3: removed old widget")
            else
                flog("G3: no live widget to remove (run G1 first for a fair test)")
            end
            state.widget, state.image = nil, nil
            state.widget, state.image = createDot(0.1, 0.3, 1.0)
            if valid(state.widget) then
                flog("G3: DANGEROUS - SetDesiredSizeInViewport on recreated widget")
                state.widget:SetDesiredSizeInViewport({ X = 16.0, Y = 16.0 })
                flog("G3: DANGEROUS - SetAlignmentInViewport on recreated widget")
                state.widget:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
                flog("G3: DANGEROUS - SetPositionInViewport on recreated widget")
                state.widget:SetPositionInViewport({ X = 960.0, Y = 590.0 }, false)
                flog("G3: SURVIVED - dot should now be BLUE. ALL GATES PASS.")
            end
        end)
        if not ok then flog("G3: soft pcall error (NOT a hard crash): " .. tostring(err)) end
        flog("=== G3 end ===")
    end)
end

return hudgate
