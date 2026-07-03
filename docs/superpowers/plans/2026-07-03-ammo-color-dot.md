# Loaded-Ammo Color Dot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A small colored dot near the reticle showing the currently loaded ammo type (rune/arrow/bolt), recolored on every V swap — built as our OWN widget, never mutating a native one.

**Architecture:** A gated probe module (`hudgate.lua`) proves in ONE in-game session that creating/positioning/recreating our own UMG widget from Lua is crash-safe (gates G1–G3). If all gates pass, a production `hud.lua` module owns the dot lifecycle (spawn → replace-on-swap), called from a one-line hook in `swap.cycle`. If ANY gate hard-crashes, Approach A is dead permanently and we fall back to Approach C (game-native toast text).

**Tech Stack:** UE4SS Lua (RE-UE4SS), UMG via `/Script/UMG.*` reflection, RuneScape: Dragonwilds. No unit-test harness exists or is possible here — this repo's proven convention is staged in-game gates with flushed file logs (see `NAMES.md`, the A5 gate history).

**Spec:** `docs/superpowers/specs/2026-07-03-ammo-color-dot-design.md`

## Global Constraints

- **NEVER mutate a native (game-owned) widget** — any render mutation from Lua hard-crashes this build (proven June 2026, branch `feat/ammo-hud-indicator`). Only widgets WE create may be touched, and even that is exactly what gates G1–G3 exist to prove.
- **NEVER construct FText** — hard-crashes this UE4SS build (proven in Runepot).
- **NO poll loops / background tickers** — poll loops caused the V-crash saga (`F:\claude\runescape\V-CRASH-HANDOVER.md`). Everything here is event-driven (keypress or swap).
- **NEVER call `IsA(string)`** — can hard-crash this build (see `NAMES.md`); use class-leaf-name comparison.
- **NO table→struct args to render functions** — `{R=,G=,B=,A=}` marshalled into `SetColorAndOpacity` crashed the renderer in June. Write struct fields one float at a time (`c.R = 1.0`) instead. Table args to NON-render functions (e.g. `SetPositionInViewport`) are unproven — that's part of gate G2, with a field-write fallback.
- **All game-object work inside `ExecuteInGameThread` + `pcall`.**
- **Flush a file-log line BEFORE every dangerous op** so a hard crash still tells us which op died (pattern from `discovery.lua`).
- **One attempt rule:** the first hard crash in any gate permanently kills Approach A. No retries, no variants. Fall back to Task C1.
- Author identity in file headers/commits: `Syloreon Khan <sylore@hotmail.com>` — never the real name/gmail.
- Play stays on `main`; all work on branch `feat/ammo-color-dot`.

---

### Task 0: Create the feature branch

**Files:** none (git only)

- [ ] **Step 1: Branch from main**

```bash
cd F:\claude\runescape\SyloreQuickSwap
git checkout -b feat/ammo-color-dot
```

Run: `git status -sb`
Expected: `## feat/ammo-color-dot`

---

### Task 1: Gate probe module (`hudgate.lua`) + config + wiring

**Files:**
- Create: `Scripts/hudgate.lua`
- Modify: `Scripts/config.lua` (append HUD-gate section before `return config`)
- Modify: `Scripts/main.lua` (append gate wiring at end of file)

**Interfaces:**
- Consumes: `UEHelpers:GetPlayerController()`, globals `StaticFindObject`, `StaticConstructObject`, `FName`, `ExecuteInGameThread`, `RegisterKeyBind` (via main.lua `bind`).
- Produces: `hudgate.g1()`, `hudgate.g2()`, `hudgate.g3()` (no args, no returns — results are observed in-game and in `sqs-hudgate.txt`). Task 3's `hud.lua` reuses the exact code shapes that survive these gates.

- [ ] **Step 1: Write `Scripts/hudgate.lua`**

```lua
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
                flog("G3: DANGEROUS - re-apply G2 sizing to recreated widget")
                state.widget:SetDesiredSizeInViewport({ X = 16.0, Y = 16.0 })
                state.widget:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
                state.widget:SetPositionInViewport({ X = 960.0, Y = 590.0 }, false)
                flog("G3: SURVIVED - dot should now be BLUE. ALL GATES PASS.")
            end
        end)
        if not ok then flog("G3: soft pcall error (NOT a hard crash): " .. tostring(err)) end
        flog("=== G3 end ===")
    end)
end

return hudgate
```

- [ ] **Step 2: Append the HUD-gate section to `Scripts/config.lua`** (insert immediately before the final `return config` line)

```lua
-- ── HUD color-dot gate (TEMPORARY — one-attempt probe, see plans/2026-07-03) ──
-- When true, main.lua loads hudgate.lua and binds F7/F8/F9 to gates G1/G2/G3.
-- MUTUALLY EXCLUSIVE with DiscoveryMode (same keys). Leave OFF for normal play.
config.HudGateMode          = false
config.HudGateG1Key         = Key.F7   -- G1: create own widget (red)
config.HudGateG2Key         = Key.F8   -- G2: size + position it
config.HudGateG3Key         = Key.F9   -- G3: remove + recreate (blue)
```

- [ ] **Step 3: Append the gate wiring to `Scripts/main.lua`** (at end of file, after the discovery block)

```lua
-- ── HUD color-dot gate (only when config.HudGateMode; TEMPORARY) ────────────
if config.HudGateMode and not config.DiscoveryMode then
    local hudgate = require("hudgate")
    print("[Sylore Quick Swap] HUD GATE on — F7=G1 create dot, F8=G2 position, F9=G3 recreate. SAVE FIRST.")
    bind("hudgate G1", config.HudGateG1Key, {}, function() hudgate.g1() end)
    bind("hudgate G2", config.HudGateG2Key, {}, function() hudgate.g2() end)
    bind("hudgate G3", config.HudGateG3Key, {}, function() hudgate.g3() end)
end
```

- [ ] **Step 4: Static sanity check (no game needed)**

Run (PowerShell, from the repo root): `lua -e "assert(loadfile('Scripts/hudgate.lua'))"`
Expected: silent exit 0 (syntax OK).

If no `lua` is on PATH, skip — syntax is proven at UE4SS load in Task 2: a load error prints to the UE4SS console AND kills every SQS keybind (loud and unambiguous; V would stop working).

- [ ] **Step 5: Commit**

```bash
git add Scripts/hudgate.lua Scripts/config.lua Scripts/main.lua
git commit -m "feat(hud): one-attempt gate probes G1-G3 for own-widget color dot"
```

---

### Task 2: In-game gate session (USER AT KEYBOARD — decision point)

**Files:** none (in-game verification; produces `sqs-hudgate.txt`)

**Interfaces:**
- Consumes: Task 1's F7/F8/F9 binds.
- Produces: a PASS/FAIL verdict that selects Task 3 (pass) or Task C1 (fail). This is the plan's only branch point.

- [ ] **Step 1: Arm the gate**

Set `config.HudGateMode = true` (and confirm `config.DiscoveryMode = false`) in `Scripts/config.lua`. Copy the mod to the game's `Mods/SyloreQuickSwap/` folder the same way previous sessions did (or play from the dev folder if that's the existing setup).

- [ ] **Step 2: Protocol (read fully BEFORE launching)**

1. Launch game, load world, **save the game** (one-attempt rule: protect progress).
2. Press **F7** (G1). Expect: a RED tint appears (possibly LARGE/fullscreen — expected until G2) and the game keeps running. Alt-tab: check `sqs-hudgate.txt` ends with `G1 end`.
3. Press **F8** (G2). Expect: the red thing becomes a ~16px square just below screen center. Check log ends with `G2 end` (a *soft pcall error* line is a finding, not a failure — report it).
4. Press **F9** (G3). Expect: square turns BLUE. Log ends with `ALL GATES PASS`.
5. Any HARD CRASH at any step: note which key, quit, and save the last lines of `sqs-hudgate.txt` and the tail of `UE4SS.log`. **Approach A is now permanently dead — proceed to Task C1, never retry A.**

- [ ] **Step 3: Record the verdict**

Append the verdict (PASS / FAIL at Gx, with the killer op line from the log) to the bottom of this plan file, commit:

```bash
git add docs/superpowers/plans/2026-07-03-ammo-color-dot.md
git commit -m "docs(plan): record hudgate G1-G3 verdict"
```

---

### Task 3: Production `hud.lua` + color config + swap hook (ONLY if Task 2 = PASS)

**Files:**
- Create: `Scripts/hud.lua`
- Modify: `Scripts/config.lua` (append color-dot section before `return config`)
- Modify: `Scripts/swap.lua` (require + one call in `swap.cycle`)

**Interfaces:**
- Consumes: the exact creation/positioning code shapes that survived G1–G3 (if the gate session revealed a different working variant — e.g. field-write positioning — mirror THAT variant here).
- Produces: `hud.setDot(assetName)` — best-effort, never throws (all pcall'd), no return value. Called by `swap.cycle` after a successful load.

- [ ] **Step 1: Append the color-dot section to `Scripts/config.lua`** (before `return config`)

```lua
-- ── Loaded-ammo color dot ─────────────────────────────────────────────────
-- A small square of color near the reticle showing the loaded ammo type.
-- Recolored on every V swap (the dot is destroyed and recreated — never
-- mutated — see docs/superpowers/specs/2026-07-03-ammo-color-dot-design.md).
-- Known v1 wart: the dot lingers after holstering until your next swap.
config.ShowColorDot         = true
-- First matching substring (case-insensitive, checked in order) wins.
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
```

- [ ] **Step 2: Write `Scripts/hud.lua`**

```lua
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

-- Public: show/replace the dot for this ammo asset. Best-effort: any failure
-- logs (if Verbose) and leaves the game untouched — never blocks the swap.
function hud.setDot(assetName)
    if not config.ShowColorDot then return end
    local col = colorFor(assetName)
    ExecuteInGameThread(function()
        local ok, err = pcall(function()
            if valid(state.widget) then
                state.widget:RemoveFromParent()   -- G3-proven on OWN widgets
            end
            state.widget = nil
            state.widget = createDot(col)
        end)
        if not ok then log("setDot failed: " .. tostring(err)) end
    end)
end

return hud
```

- [ ] **Step 3: Hook `swap.cycle` in `Scripts/swap.lua`**

Add the require near the top (after `local config    = require("config")`):

```lua
local hud       = require("hud")
```

Then in `swap.cycle`, immediately after the `ExecuteInGameThread(...)` block that calls `UseItemFromInventory` (before the final `log(...)` line), add:

```lua
    -- Color-dot feedback (own-widget HUD; best-effort, never blocks the swap).
    hud.setDot(target.asset)
```

- [ ] **Step 4: Disarm the gate**

In `Scripts/config.lua` set `config.HudGateMode = false`. Keep `hudgate.lua` on disk (same convention as `discovery.lua` — future re-gating after game updates).

- [ ] **Step 5: In-game smoke test**

1. Hot-reload (Ctrl+R) or relaunch; load world.
2. Staff out: V-cycle runes — dot appears and tracks Fire=red, Water=blue, Earth=green, Air=pale yellow.
3. Bow out: V-cycle arrows — tier colors track; poison variant (if owned) = green.
4. Crossbow out: V-cycle bolts — same.
5. Hammer V ~30 times across weapons: zero crash, no dot "ghosts" (exactly one dot ever visible).
6. F1–F4 loadout apply/save still work.
7. Set `config.ShowColorDot = false`, hot-reload: no dot, swap still works.

Expected: all pass; `UE4SS.log` tail clean of errors.

- [ ] **Step 6: Commit**

```bash
git add Scripts/hud.lua Scripts/config.lua Scripts/swap.lua
git commit -m "feat(hud): loaded-ammo color dot — own-widget, destroy+recreate on swap"
```

---

### Task 4: README + wrap-up (follows Task 3 OR Task C2)

**Files:**
- Modify: `README.md` (feature list + config docs)

**Interfaces:**
- Consumes: whichever feature actually shipped (dot or toast).

- [ ] **Step 1: Document the shipped feature in `README.md`**

Add to the feature list (dot version shown; adapt if C shipped):

```markdown
- **Loaded-ammo color dot** — a small colored square near the reticle shows
  which ammo is loaded (fire rune = red, water = blue, poison arrows = green, …).
  Colors, size, and position are configurable via `config.ColorMap`,
  `config.DotSize`, `config.DotOffsetY`; disable with `config.ShowColorDot = false`.
  The dot updates on swap and may linger briefly after holstering (by design —
  no background polling, see the V-crash history).
```

- [ ] **Step 2: Commit, then finish the branch**

```bash
git add README.md
git commit -m "docs: README for loaded-ammo color dot"
```

Then use the superpowers:finishing-a-development-branch skill (expected outcome: merge `feat/ammo-color-dot` into `main` after the user confirms a real play session was stable — the ~70-press bar from the V-crash saga).

---

### Task C1: Toast discovery (ONLY if Task 2 = FAIL)

**Files:**
- Create: `Scripts/toastgate.lua`
- Modify: `Scripts/config.lua` (reuse the HudGate keys section: rename comment, F7 = scan)
- Modify: `Scripts/main.lua` (swap the gate require to `toastgate` behind the same flag)

**Interfaces:**
- Consumes: `discovery.lua` patterns (class property/function walking, flushed file logs).
- Produces: a `discovery`-style report `sqs-toastgate.txt` listing candidate game notification functions and their parameter types; a go/no-go for Task C2.

- [ ] **Step 1: Write `Scripts/toastgate.lua`** — an F7-triggered scan that walks the HUD/PlayerController/GameInstance object graphs (same `findComponent`/`ForEachProperty` idiom as `swap.lua`/`discovery.lua`) hunting functions whose names match any of: `Notify`, `Notification`, `Toast`, `Message`, `Announce`, `Popup`, `ShowText`. For each hit, log the full function signature via `ForEachFunction` + `ForEachFunctionParameter` (names + types, flushed). **Read-only scan — calls nothing.**

```lua
--[[
    Sylore Quick Swap - toastgate.lua
    Approach C discovery: find a game-native toast/notification callable.
    READ-ONLY: walks classes and logs signatures; never calls anything.
    Killer constraint: any candidate whose params include FText is DEAD
    (FText construction hard-crashes this build — Runepot, June 2026).

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")

local toastgate = {}

local LOGFILE = "Mods/SyloreQuickSwap/sqs-toastgate.txt"
local function flog(msg)
    print("[SQS toastgate] " .. msg)
    local f = io.open(LOGFILE, "a")
    if f then f:write(msg .. "\n") f:close() end
end

local NAME_HINTS = { "notify", "notification", "toast", "message", "announce", "popup", "showtext" }

local function scanObject(label, obj)
    if obj == nil then return end
    local ok, cls = pcall(function() return obj:GetClass() end)
    if not ok or cls == nil then return end
    flog("== scanning " .. label .. " : " .. obj:GetFullName())
    pcall(function()
        cls:ForEachFunction(function(fn)
            local fname = string.lower(fn:GetFName():ToString())
            for _, hint in ipairs(NAME_HINTS) do
                if string.find(fname, hint, 1, true) then
                    local sig = { fn:GetFName():ToString() .. "(" }
                    pcall(function()
                        fn:ForEachFunctionParameter(function(param)
                            sig[#sig + 1] = param:GetClass():GetFName():ToString()
                                .. " " .. param:GetFName():ToString() .. ", "
                        end)
                    end)
                    flog("  CANDIDATE " .. label .. " :: " .. table.concat(sig) .. ")")
                    break
                end
            end
        end)
    end)
end

function toastgate.scan()
    flog("=== toast scan begin ===")
    local pc = UEHelpers:GetPlayerController()
    scanObject("PlayerController", pc)
    pcall(function() scanObject("HUD", pc.MyHUD) end)
    pcall(function() scanObject("Pawn", pc.Pawn) end)
    pcall(function() scanObject("GameInstance", UEHelpers:GetGameInstance()) end)
    flog("=== toast scan end — FText params disqualify a candidate ===")
end

return toastgate
```

Config comment edit + main.lua: replace the hudgate block's require/binds with `toastgate.scan()` on F7 only (G2/G3 binds removed). Commit: `git commit -m "feat(toast): Approach C read-only toast/notification scan"`.

- [ ] **Step 2: In-game scan + verdict** — F7 in-world, then read `sqs-toastgate.txt`. A candidate is viable only if its params are FString/plain types (NO FText). Record findings at the bottom of this plan, commit. If no viable candidate: the feature ends at console-print status quo — report that honestly to the user and skip to Task 4 (README documents nothing new; close the branch without merge or merge only the gate tooling per user preference).

---

### Task C2: Toast implementation (ONLY if C1 found a viable candidate)

**Files:**
- Create: `Scripts/hud.lua` (toast variant)
- Modify: `Scripts/swap.lua` (same hook as Task 3 Step 3)
- Modify: `Scripts/config.lua` (`config.ShowColorDot` replaced by `config.ShowToast`)

Shape: `hud.setDot(assetName)` keeps the SAME public name/signature (so the swap.lua hook is identical), but internally calls the discovered function with a plain string like `"Fire runes loaded"` inside `ExecuteInGameThread` + `pcall`. Exact call code depends on C1's discovered signature — fill it in from the C1 verdict before executing this task, then follow Task 3's smoke-test and commit steps (message: `feat(toast): swap-time ammo toast via <FunctionName>`).

---

## Gate verdicts (appended during execution)

*(empty — filled by Task 2 / Task C1)*
