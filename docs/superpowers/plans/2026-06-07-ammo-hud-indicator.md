# Loaded-Ammo HUD Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tint the game's existing on-screen ammo icon by element (Fire/Poison/plain) so the player always knows which arrow/bolt is loaded, without cycling or opening the inventory.

**Architecture:** A probe-first, two-phase build. Phase A is a gated in-game discovery harness (`hud_probe.lua`) that locates the ammo HUD widget, confirms its tint can be safely mutated, and dumps the real arrow/bolt asset names. Phase B is a self-contained always-on module (`hud_ammo.lua`) that polls the loaded ammo on a `LoopAsync` tick and sets the widget's tint per element, restoring the original tint for plain ammo / no ranged weapon. Image/tint only — never `FText` (hard-crashes on this build).

**Tech Stack:** UE4SS 3.0.1 (Lua 5.4) for RuneScape: Dragonwilds (UE5). No automated test runner exists; verification = `python F:\claude\runescape\luacheck.py <file>` for parse-checking + scripted in-game observation. Deploy via `deploy-mod.ps1`; keybinds require a FULL game restart to (re)register.

---

## How "tests" work in this plan (read first)

There is **no local Lua interpreter and no unit-test framework**. A Lua load error silently kills the entire mod (no popup). So every code task uses this two-part verification in place of TDD:

1. **Parse-check (automated, fast):** `python F:\claude\runescape\luacheck.py <file>` must report no errors. This is the closest thing to a failing/passing unit test and MUST be run after every edit.
2. **In-game observation (the real test):** deploy, FULL restart (keybinds only register on a fresh launch — Ctrl+R hot-reload does NOT re-register binds), perform the documented action, and confirm the documented expected result (on-screen and/or in the flushed `discovery-hud.txt`).

**Crash-safety rule (applies to all code here):** wrap every game-object access in `pcall`; run every mutation/UI dispatch inside `ExecuteInGameThread`; never call `IsA("string")`; never touch `FText`. Discovery output is written open-append-close per line so a native crash can't lose the tail.

**Phase gate:** Do NOT start Phase B until the Phase A probe has confirmed (a) the ammo widget is findable, (b) its tint is safely settable and visibly changes on screen, and (c) the arrow/bolt asset names are captured. If the tint cannot be set safely, STOP and report — the fallback (child marker / standalone widget) is a separate re-scoped plan.

---

## File structure

- **Create** `scripts/hud_probe.lua` — Phase-A discovery harness (gated by `config.DiscoveryMode`). Throwaway-ish; kept for future re-mapping like the existing `discovery.lua`.
- **Create** `scripts/hud_ammo.lua` — Phase-B always-on indicator module. Self-contained, references only `names.lua` + `config.lua`.
- **Modify** `scripts/config.lua` — add indicator config + Phase-A discovery keys/match strings.
- **Modify** `scripts/names.lua` — add `names.AmmoElements` table + the widget/tint constants discovered in Phase A.
- **Modify** `scripts/main.lua` — load `hud_probe` under DiscoveryMode (Phase A); always-start `hud_ammo` (Phase B).
- **Output (generated in-game)** `discovery-hud.txt` — flushed probe dump (already gitignored alongside other `discovery-*.txt`).

---

## Phase A — Discovery probe

### Task A1: Add Phase-A config (keys + match strings)

**Files:**
- Modify: `scripts/config.lua`

- [ ] **Step 1: Add the HUD discovery config block.** Insert immediately after the existing `config.HookKey = Key.F7` line (the Phase-1 discovery block), before `return config`:

```lua
-- ── Phase A: HUD indicator discovery (TEMPORARY — only when DiscoveryMode) ──
-- Shift+F7 dumps loaded UserWidgets + ammo asset names to discovery-hud.txt.
-- Ctrl+F7 toggles a bright TEST tint on the widget whose class-leaf contains
-- HudWidgetMatch, via the property/ setter named HudTintProp — used to confirm,
-- AFTER reading the dump, that we found the right widget and can mutate its tint.
config.HudDumpMods          = { ModifierKey.SHIFT }  -- Shift+F7 -> probe.dumpHud()
config.HudTintTestMods      = { ModifierKey.CONTROL } -- Ctrl+F7  -> probe.testHudTint()
-- Set these two AFTER reading the first dump, then full-restart and press Ctrl+F7:
config.HudWidgetMatch       = ""   -- e.g. "Ammo" — class-leaf substring of the ammo widget
config.HudTintProp          = "ColorAndOpacity"  -- tint property/setter to drive
```

- [ ] **Step 2: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\config.lua`
Expected: no errors reported.

- [ ] **Step 3: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/config.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): add Phase-A HUD discovery config keys"
```

---

### Task A2: Write the HUD discovery harness

**Files:**
- Create: `scripts/hud_probe.lua`

- [ ] **Step 1: Write `hud_probe.lua` in full.**

```lua
--[[
    Sylore Quick Swap - hud_probe.lua  (Phase A discovery harness)

    Goal: find the game's on-screen AMMO icon widget, confirm we can safely set
    its tint, and capture the real arrow/bolt asset names — so hud_ammo.lua can
    recolor the loaded-ammo icon by element.

    Output is flushed per line to discovery-hud.txt (open-append-close) so a native
    C++ crash (uncatchable by pcall) can't lose the tail. Everything is pcall-guarded;
    the tint write runs inside ExecuteInGameThread. No FText anywhere.

    Keys (only when config.DiscoveryMode; see main.lua):
      Shift+F7 -> probe.dumpHud()     : list UserWidgets + interesting props + ammo assets
      Ctrl+F7  -> probe.testHudTint() : toggle a bright TEST tint on the matched widget

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
local config    = require("config")
local names     = require("names")

local probe = {}

-- ── flushed output into the mod folder (portable; no machine path) ──────────
local function modRoot()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        local p = src:gsub("^@", "")
        local dir = p:match("^(.*[/\\])")
        if dir and dir ~= "" then return (dir:gsub("[Ss]cripts[/\\]$", "")) end
    end
    return "./"
end
local FILE = modRoot() .. "discovery-hud.txt"
local function w(line)
    line = tostring(line)
    print("[HUD] " .. line)
    local ok, f = pcall(io.open, FILE, "a")
    if ok and f then f:write(line .. "\n"); f:close() end
end
local function reset(title)
    local ok, f = pcall(io.open, FILE, "w")
    if ok and f then f:write("=== " .. tostring(title) .. " ===\n"); f:close() end
end

-- ── safe primitives (re-declared; never share across modules) ───────────────
local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o.IsValid ~= nil and o:IsValid() end)
    return ok and v or false
end
local function fullName(o)
    if o == nil then return "nil" end
    local ok, n = pcall(function() return o:GetFullName() end)
    return ok and n or tostring(o)
end
local function leaf(s) return (s and s:match("[%.%s]([^%.%s]+)$")) or s end
local function classLeaf(o)
    if not valid(o) then return "nil" end
    local ok, c = pcall(function() return o:GetClass() end)
    if not ok or c == nil then return "nil" end
    return leaf(fullName(c))
end

-- Property names worth logging when scanning a widget.
local KW = { "color", "tint", "brush", "image", "icon", "ammo", "opacity", "quiver" }
local function interesting(name)
    local n = string.lower(name)
    for _, k in ipairs(KW) do if string.find(n, k, 1, true) then return true end end
    return false
end

-- Dump the keyword-matching properties of one widget (name + type leaf).
local function dumpProps(obj)
    local ok, cls = pcall(function() return obj:GetClass() end)
    if not ok or cls == nil then w("    (no class)"); return end
    pcall(function()
        cls:ForEachProperty(function(prop)
            local pname = prop:GetFName():ToString()
            if not interesting(pname) then return end
            local ptype = "?"
            pcall(function() ptype = leaf(prop:GetClass():GetFullName()) end)
            w(("    . %-28s : %s"):format(pname, ptype))
        end)
    end)
end

-- ── Shift+F7 : enumerate widgets + ammo assets ──────────────────────────────
function probe.dumpHud()
    reset("HUD widget dump")

    local widgets = {}
    pcall(function() widgets = FindAllOf("UserWidget") or {} end)
    w("FindAllOf('UserWidget') -> " .. tostring(#widgets) .. " instances")

    -- 1) distinct class-leaf tally (spot the ammo widget's class here)
    local tally, order = {}, {}
    for _, wd in ipairs(widgets) do
        if valid(wd) then
            local cl = classLeaf(wd)
            if tally[cl] == nil then tally[cl] = 0; order[#order + 1] = cl end
            tally[cl] = tally[cl] + 1
        end
    end
    w("---- distinct UserWidget classes ----")
    table.sort(order)
    for _, cl in ipairs(order) do w(("  %4d x %s"):format(tally[cl], cl)) end

    -- 2) detail dump for widgets whose CLASS matches a keyword (likely candidates)
    w("---- candidate widgets (class matches keyword) ----")
    for i, wd in ipairs(widgets) do
        if valid(wd) and interesting(classLeaf(wd)) then
            w(("[%d] %s"):format(i, fullName(wd)))
            dumpProps(wd)
        end
    end

    -- 3) loaded arrow/bolt asset names (so we can map them to elements)
    w("---- ranged ammo assets in inventory ----")
    pcall(function()
        local pc = UEHelpers:GetPlayerController()
        if not valid(pc) then w("  (no player controller)"); return end
        -- main bag + personal inventory, by property-name substring
        local function scanInv(want, excl)
            local cls = pc:GetClass()
            cls:ForEachProperty(function(prop)
                local pn = prop:GetFName():ToString()
                local nm = string.lower(pn)
                if string.find(nm, want, 1, true) == nil then return end
                if excl and string.find(nm, excl, 1, true) then return end
                local okv, inv = pcall(function() return pc[pn] end)
                if not (okv and valid(inv)) then return end
                local n = 0
                pcall(function() n = inv.ItemSlots:GetArrayNum() end)
                for s = 0, n - 1 do
                    local oki, item = pcall(function() return inv:GetItemFromSlot(s) end)
                    if oki and valid(item) then
                        local data = nil
                        pcall(function() data = item.ItemData end)
                        if valid(data) and classLeaf(data) == "RangedAmmoData" then
                            local cat = ""
                            pcall(function() cat = data.Category.TagName:ToString() end)
                            w(("  slot %2d  %-26s  cat=%s"):format(s, leaf(fullName(data)), cat))
                            -- also log any icon-bearing property on the ItemData
                            pcall(function()
                                data:GetClass():ForEachProperty(function(p2)
                                    local p2n = p2:GetFName():ToString()
                                    if interesting(p2n) then
                                        w(("        data.%s"):format(p2n))
                                    end
                                end)
                            end)
                        end
                    end
                end
            end)
        end
        scanInv("inventory", "controller")  -- BP_Components_Inventory (skip InventoryController)
        scanInv("personal", nil)            -- BP_Components_PersonalInventory
    end)

    w("=== dump complete ===")
end

-- ── Ctrl+F7 : toggle a bright TEST tint on the matched widget ────────────────
-- Tries a setter (Set<Prop>) first, then direct property assignment. Logs which
-- worked. Press again to restore. FLinearColor is passed as a {R,G,B,A} table.
local _origStore = nil   -- captured original value (for restore)
local _tinted    = false

local function findWidget(match)
    if match == nil or match == "" then return nil end
    local widgets = {}
    pcall(function() widgets = FindAllOf("UserWidget") or {} end)
    for _, wd in ipairs(widgets) do
        if valid(wd) and string.find(string.lower(classLeaf(wd)), string.lower(match), 1, true) then
            return wd
        end
    end
    return nil
end

function probe.testHudTint()
    local match = config.HudWidgetMatch
    local prop  = config.HudTintProp or "ColorAndOpacity"
    if match == nil or match == "" then
        w("testHudTint: set config.HudWidgetMatch (read the dump first) then full-restart.")
        return
    end
    local wd = findWidget(match)
    if not valid(wd) then w("testHudTint: no widget whose class contains '" .. match .. "'."); return end
    w("testHudTint: target " .. fullName(wd) .. "  prop=" .. prop)

    local TEST = { R = 1.0, G = 0.0, B = 1.0, A = 1.0 }  -- bright magenta
    ExecuteInGameThread(function()
        if not _tinted then
            -- capture original (best-effort) before first change
            pcall(function() _origStore = wd[prop] end)
            local setter = "Set" .. prop
            local okS = pcall(function() wd[setter](wd, TEST) end)
            if okS then
                w("  set via " .. setter .. "(table) OK")
            else
                local okP = pcall(function() wd[prop] = TEST end)
                w("  set via property assign: " .. tostring(okP))
            end
            _tinted = true
        else
            -- restore
            if _origStore ~= nil then
                local setter = "Set" .. prop
                local okS = pcall(function() wd[setter](wd, _origStore) end)
                if not okS then pcall(function() wd[prop] = _origStore end) end
                w("  restored original")
            else
                w("  no original captured to restore")
            end
            _tinted = false
        end
    end)
end

return probe
```

- [ ] **Step 2: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\hud_probe.lua`
Expected: no errors reported.

- [ ] **Step 3: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/hud_probe.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): add Phase-A HUD discovery harness"
```

---

### Task A3: Wire the probe into main.lua under DiscoveryMode

**Files:**
- Modify: `scripts/main.lua:53-60`

- [ ] **Step 1: Extend the DiscoveryMode block.** Replace the existing block (lines 53–60):

```lua
-- ── Phase 1 discovery keybinds (only when config.DiscoveryMode) ─────────────
if config.DiscoveryMode then
    require("discovery")
    print("[Sylore Quick Swap] DISCOVERY MODE on — F8=probe live rune state, F9=dump player, F7=arm rune hooks.")
    RegisterKeyBind(config.DiscoverKey,   {}, safe(function() RQS.probeRunes() end))
    RegisterKeyBind(config.CombatMagicKey,{}, safe(function() RQS.dumpPlayer() end))
    RegisterKeyBind(config.HookKey,       {}, safe(function() RQS.armRuneHooks() end))
end
```

with:

```lua
-- ── Phase 1 discovery keybinds (only when config.DiscoveryMode) ─────────────
if config.DiscoveryMode then
    require("discovery")
    local hudProbe = require("hud_probe")
    print("[Sylore Quick Swap] DISCOVERY MODE on — F8=probe rune state, F9=dump player, F7=rune hooks; Shift+F7=dump HUD, Ctrl+F7=test HUD tint.")
    RegisterKeyBind(config.DiscoverKey,   {}, safe(function() RQS.probeRunes() end))
    RegisterKeyBind(config.CombatMagicKey,{}, safe(function() RQS.dumpPlayer() end))
    RegisterKeyBind(config.HookKey,       {}, safe(function() RQS.armRuneHooks() end))
    bind("hud dump",      config.HookKey, config.HudDumpMods,     function() hudProbe.dumpHud() end)
    bind("hud tint test", config.HookKey, config.HudTintTestMods, function() hudProbe.testHudTint() end)
end
```

- [ ] **Step 2: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\main.lua`
Expected: no errors reported.

- [ ] **Step 3: Enable discovery + deploy + FULL restart.** Set `config.DiscoveryMode = true` in `scripts/config.lua`, then:

Run: `pwsh -File F:\claude\runescape\deploy-mod.ps1 -ModName SyloreQuickSwap -Link`
Then FULLY quit and relaunch the game (keybinds register only on a fresh launch).
Expected: UE4SS console prints the "DISCOVERY MODE on … Shift+F7=dump HUD, Ctrl+F7=test HUD tint." line, and `UE4SS.log` shows no `Error executing script`.

- [ ] **Step 4: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/main.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): wire Phase-A HUD probe keys (Shift+F7 dump, Ctrl+F7 tint test)"
```

---

### Task A4: Run the dump and identify the ammo widget (in-game)

**Files:** none (in-game investigation; produces `discovery-hud.txt`)

- [ ] **Step 1: Dump the HUD.** In-game, equip a **bow or crossbow** with at least one arrow/bolt loaded, then press **Shift+F7**.
Expected: `discovery-hud.txt` is created in the mod folder and ends with `=== dump complete ===`.

- [ ] **Step 2: Read the dump.** Open `F:\claude\runescape\SyloreQuickSwap\discovery-hud.txt`. In the "distinct UserWidget classes" tally and the "candidate widgets" section, find the widget that represents the on-screen **ammo icon** (look for class leaves containing `Ammo`/`Quiver`/`Ranged`/`Hotbar`, and a property like `ColorAndOpacity`, `BrushColor`, or a named `Image`). Note the **class-leaf substring** and the **tint property name**.
In the "ranged ammo assets" section, record the asset names of each variant (e.g. `ITEM_Arrow_Fire`, `ITEM_Arrow_Poison`, `ITEM_Arrow`).

- [ ] **Step 3: Record findings in the spec's NAMES.md.** Append the identified widget class, tint property, and the full list of arrow/bolt asset names to `F:\claude\runescape\SyloreQuickSwap\NAMES.md` under a new "HUD ammo indicator" heading (local notes; gitignored). This is the source data for Tasks A5, B1.

- [ ] **Step 4: Set the match strings.** Edit `scripts/config.lua`: set `config.HudWidgetMatch` to the class-leaf substring (e.g. `"Ammo"`) and `config.HudTintProp` to the tint property (e.g. `"ColorAndOpacity"`). Parse-check:
Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\config.lua`
Expected: no errors.

- [ ] **Step 5: Commit the config (findings are local in NAMES.md).**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/config.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "chore(hud): set discovered ammo-widget match + tint property"
```

---

### Task A5: Confirm the tint is safely mutable (in-game GATE)

**Files:** none (in-game investigation)

- [ ] **Step 1: Re-deploy + FULL restart** so the updated `config.HudWidgetMatch`/`HudTintProp` load:
Run: `pwsh -File F:\claude\runescape\deploy-mod.ps1 -ModName SyloreQuickSwap -Link`
Then fully relaunch the game.

- [ ] **Step 2: Toggle the test tint.** With a bow/crossbow equipped, press **Ctrl+F7**.
Expected: the on-screen ammo icon turns **bright magenta**; `discovery-hud.txt` logs `set via Set<Prop>(table) OK` (or `property assign: true`). No crash.

- [ ] **Step 3: Restore.** Press **Ctrl+F7** again.
Expected: the icon returns to its original color; log shows `restored original`. No crash.

- [ ] **Step 4: GATE DECISION.**
  - If the icon visibly tinted and restored with no crash → **proceed to Phase B.** Note in `NAMES.md` which mechanism worked (setter vs property assign) — Phase B uses the same.
  - If nothing tinted, or the magenta hit the wrong element, or it crashed → **STOP.** Record the failure in `NAMES.md` and report back: Phase B (tint approach) is not viable as-is; the child-marker/standalone fallback needs a re-scoped plan. Do not write `hud_ammo.lua` against an unconfirmed mechanism.

---

## Phase B — The always-on indicator (build ONLY after the A5 gate passes)

### Task B1: Add the element/colour data + widget constants to names.lua

**Files:**
- Modify: `scripts/names.lua` (append before `return names`)

- [ ] **Step 1: Add the data table.** Use the REAL asset names recorded in Task A4. The example below assumes `ITEM_Arrow_Fire`/`ITEM_Bolt_Fire` and `..._Poison`; replace the `match` substrings with whatever the dump showed. Plain ammo has no row (no match ⇒ no tint).

```lua
-- ── HUD ammo indicator (Phase B) ─────────────────────────────────────────────
-- The on-screen ammo icon widget, discovered in Phase A. Matched by class-leaf
-- substring; its tint is set via the property/setter named here.
names.HudWidgetMatch = "Ammo"            -- class-leaf substring (confirmed in A4/A5)
names.HudTintProp    = "ColorAndOpacity" -- tint property/setter (confirmed in A5)

-- Element table: first row whose `match` is a case-insensitive substring of the
-- loaded ammo's ASSET name wins; no match ⇒ plain (restore original tint).
-- tint is an FLinearColor as {R,G,B,A} in 0..1. Add a row to support a new type.
names.AmmoElements = {
    { match = "Fire",   element = "Fire",   tint = { R = 1.0, G = 0.25, B = 0.10, A = 1.0 } },
    { match = "Poison", element = "Poison", tint = { R = 0.30, G = 0.95, B = 0.20, A = 1.0 } },
}
```

- [ ] **Step 2: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\names.lua`
Expected: no errors.

- [ ] **Step 3: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/names.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): add ammo-element tint table + widget constants"
```

---

### Task B2: Add Phase-B runtime config

**Files:**
- Modify: `scripts/config.lua` (in the "Behavior"/"Feedback" area, before `return config`)

- [ ] **Step 1: Add the indicator config block.**

```lua
-- ── HUD ammo indicator (Phase B) ──────────────────────────────────────────
config.HudIndicatorEnabled  = true   -- master on/off for the loaded-ammo tint
config.HudTickMs            = 500    -- poll interval (ms) for re-applying the tint
-- Optional per-element overrides; nil/absent = use names.AmmoElements defaults.
-- Each value is an FLinearColor {R,G,B,A} in 0..1. Example:
--   config.HudTintColors = { Fire = { R=1, G=0, B=0, A=1 } }
config.HudTintColors        = nil
```

- [ ] **Step 2: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\config.lua`
Expected: no errors.

- [ ] **Step 3: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/config.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): add Phase-B indicator runtime config"
```

---

### Task B3: Write the indicator module

**Files:**
- Create: `scripts/hud_ammo.lua`

- [ ] **Step 1: Write `hud_ammo.lua` in full.** This re-declares its own helpers (no sharing with `swap.lua`), resolves the loaded ammo the same way `swap.lua` does, and uses the SAME set mechanism confirmed in A5 (setter first, property-assign fallback).

```lua
--[[
    Sylore Quick Swap - hud_ammo.lua  (Phase B)

    Always-on loaded-ammo indicator: tints the game's existing on-screen ammo icon
    by element (Fire/Poison/...). Resolves the loaded arrow/bolt the same way swap.lua
    does (held weapon -> strategy -> loadout slot item -> asset name), looks up its
    element in names.AmmoElements, and sets the widget's tint on a slow LoopAsync tick.

    Plain ammo / no ranged weapon / disabled  ->  restore the widget's ORIGINAL tint
    (captured on first touch). The tick self-heals if the widget reference goes stale
    (world reload). Image/tint only — no FText. All mutation in ExecuteInGameThread.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local UEHelpers = require("UEHelpers")
local names     = require("names")
local config    = require("config")

local hud = {}

-- ── safe primitives (re-declared per module) ───────────────────────────────
local function valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o.IsValid ~= nil and o:IsValid() end)
    return ok and v or false
end
local function fullName(o)
    if o == nil then return "nil" end
    local ok, n = pcall(function() return o:GetFullName() end)
    return ok and n or tostring(o)
end
local function leaf(s) return (s and s:match("[%.%s]([^%.%s]+)$")) or s end
local function classLeaf(o)
    if not valid(o) then return "nil" end
    local ok, c = pcall(function() return o:GetClass() end)
    if not ok or c == nil then return "nil" end
    return leaf(fullName(c))
end
local function log(m) if config.Verbose then print("[Sylore Quick Swap][hud] " .. tostring(m)) end end

-- ── resolve the loaded ammo asset (mirrors swap.lua, independently) ─────────
local function findComponent(owner, want, excludes)
    if not valid(owner) then return nil end
    local ok, cls = pcall(function() return owner:GetClass() end)
    if not ok or cls == nil then return nil end
    want = string.lower(want)
    local found = nil
    pcall(function()
        cls:ForEachProperty(function(prop)
            if found ~= nil then return end
            local nm = string.lower(prop:GetFName():ToString())
            if string.find(nm, want, 1, true) == nil then return end
            if excludes then
                for _, ex in ipairs(excludes) do
                    if string.find(nm, string.lower(ex), 1, true) then return end
                end
            end
            local okv, v = pcall(function() return owner[prop:GetFName():ToString()] end)
            if okv and valid(v) then found = v end
        end)
    end)
    return found
end

local function itemInSlot(loadout, slotEnum)
    if not valid(loadout) then return nil end
    local okIdx, idx = pcall(function() return loadout:GetSlotIndexForSlot(slotEnum) end)
    if not okIdx or idx == nil or idx < 0 then return nil end
    local okIt, item = pcall(function() return loadout:GetItemFromSlot(idx) end)
    if okIt and valid(item) then return item end
    return nil
end

local function categoryOf(item)
    local cat = ""
    pcall(function() cat = item.ItemData.Category.TagName:ToString() end)
    return cat or ""
end
local function assetOf(item)
    local ok, data = pcall(function() return item.ItemData end)
    if ok and valid(data) then return leaf(fullName(data)) end
    return nil
end

-- Returns the loaded ammo's asset name, or nil if no ranged weapon / no ammo.
local function loadedAmmoAsset(pc)
    local loadout = findComponent(pc, "Loadout")
    if not valid(loadout) then return nil end
    -- which ranged strategy does the held weapon use?
    local weapon = itemInSlot(loadout, names.ELoadoutSlot.HeldRight)
        or itemInSlot(loadout, names.ELoadoutSlot.HeldLeft)
    if not valid(weapon) then return nil end
    local wcat = categoryOf(weapon)
    for _, s in ipairs(names.AmmoStrategies) do
        if s.dataClass == "RangedAmmoData" and string.find(wcat, s.weaponTag, 1, true) then
            local ammo = itemInSlot(loadout, s.slot)
            if valid(ammo) then return assetOf(ammo) end
            return nil
        end
    end
    return nil   -- not a ranged weapon (e.g. staff) -> indicator stays neutral
end

-- element tint for an asset name, or nil (plain).
local function tintFor(asset)
    if asset == nil then return nil end
    local lower = string.lower(asset)
    for _, e in ipairs(names.AmmoElements) do
        if string.find(lower, string.lower(e.match), 1, true) then
            local override = config.HudTintColors and config.HudTintColors[e.element]
            return override or e.tint
        end
    end
    return nil
end

-- ── the widget + its original tint ──────────────────────────────────────────
local widget   = nil   -- cached ammo-icon widget
local original = nil   -- captured original tint value
local applied  = nil   -- string key of the last tint we applied ("" = original)

local function findWidget()
    local match = names.HudWidgetMatch
    if match == nil or match == "" then return nil end
    local widgets = {}
    pcall(function() widgets = FindAllOf("UserWidget") or {} end)
    for _, wd in ipairs(widgets) do
        if valid(wd) and string.find(string.lower(classLeaf(wd)), string.lower(match), 1, true) then
            return wd
        end
    end
    return nil
end

-- set the tint property to `value`; setter first, property-assign fallback.
local function setTint(wd, value)
    local prop   = names.HudTintProp or "ColorAndOpacity"
    local setter = "Set" .. prop
    local okS = pcall(function() wd[setter](wd, value) end)
    if okS then return true end
    return pcall(function() wd[prop] = value end)
end

-- ── the tick ────────────────────────────────────────────────────────────────
local function tick()
    if not config.HudIndicatorEnabled then return end

    -- (re)find the widget if stale
    if not valid(widget) then
        widget   = findWidget()
        original = nil
        applied  = nil
    end
    if not valid(widget) then return end

    local prop = names.HudTintProp or "ColorAndOpacity"
    -- capture original tint once (off-thread read is fine)
    if original == nil then
        pcall(function() original = widget[prop] end)
    end

    local asset = nil
    pcall(function() asset = loadedAmmoAsset(UEHelpers:GetPlayerController()) end)
    local tint  = tintFor(asset)
    -- key for change detection so we don't re-set every tick
    local key = tint and (asset or "?") or ""
    if key == applied then return end

    local target = tint or original
    if target == nil then return end   -- nothing to restore to yet
    ExecuteInGameThread(function()
        local ok = setTint(widget, target)
        if ok then applied = key else log("setTint failed for key=" .. key) end
    end)
    log("tint -> " .. (tint and ("element:" .. key) or "original"))
end

function hud.start()
    if not config.HudIndicatorEnabled then
        print("[Sylore Quick Swap] HUD ammo indicator disabled (config.HudIndicatorEnabled=false).")
        return
    end
    local ms = config.HudTickMs or 500
    LoopAsync(ms, function()
        pcall(tick)
        return false   -- keep looping
    end)
    print("[Sylore Quick Swap] HUD ammo indicator running (tint by element every " .. ms .. "ms).")
end

return hud
```

- [ ] **Step 2: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\hud_ammo.lua`
Expected: no errors.

- [ ] **Step 3: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/hud_ammo.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): add always-on loaded-ammo tint indicator module"
```

---

### Task B4: Start the indicator from main.lua

**Files:**
- Modify: `scripts/main.lua`

- [ ] **Step 1: Require the module at the top.** After line 11 (`local loadouts = require("loadouts")`), add:

```lua
local hudAmmo  = require("hud_ammo")
```

- [ ] **Step 2: Start it after the loadout binds.** Immediately after the `for slotNum = 1, config.LoadoutSlotCount do ... end` loop (currently ending at line 51), before the DiscoveryMode block, add:

```lua
-- ── HUD ammo indicator (always-on tint of the loaded arrow/bolt icon) ───────
hudAmmo.start()
```

- [ ] **Step 3: Parse-check.** Run: `python F:\claude\runescape\luacheck.py F:\claude\runescape\SyloreQuickSwap\scripts\main.lua`
Expected: no errors.

- [ ] **Step 4: Disable discovery + deploy + FULL restart.** Set `config.DiscoveryMode = false` in `scripts/config.lua`, then:
Run: `pwsh -File F:\claude\runescape\deploy-mod.ps1 -ModName SyloreQuickSwap -Link`
Then fully relaunch the game.
Expected: console prints "HUD ammo indicator running …"; `UE4SS.log` shows no `Error executing script`.

- [ ] **Step 5: Commit.**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add scripts/main.lua scripts/config.lua
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "feat(hud): start always-on ammo indicator on load"
```

---

### Task B5: End-to-end in-game verification

**Files:** none (in-game observation)

- [ ] **Step 1: Fire tint.** Equip a bow/crossbow and load a **Fire** arrow/bolt (cycle with V if needed).
Expected: within ~0.5s the on-screen ammo icon shows the Fire tint (warm red).

- [ ] **Step 2: Poison tint.** Cycle (V) to a **Poison** arrow/bolt.
Expected: within ~0.5s the icon switches to the Poison tint (green).

- [ ] **Step 3: Plain restores.** Cycle (V) to a **plain** arrow/bolt.
Expected: the icon returns to its original, untinted color.

- [ ] **Step 4: Unequip restores.** Switch to a melee weapon or staff (no ranged ammo).
Expected: the icon shows its original color (no leftover tint).

- [ ] **Step 5: Reload survival.** Reload the world / travel so the HUD rebuilds, then re-equip the bow with Fire loaded.
Expected: the tint re-applies within a tick (the module re-finds the widget). No crash across the reload.

- [ ] **Step 6: Disable switch.** Set `config.HudIndicatorEnabled = false`, Ctrl+R hot-reload is insufficient for keybinds but fine here since `start()` runs at load — so deploy + FULL restart, then check the icon stays the game's original color and the console prints the "disabled" line.

- [ ] **Step 7: Final commit (any tint-color tweaks from observation).**

```bash
cd F:/claude/runescape/SyloreQuickSwap
git add -A
git -c user.name="Syloreon Khan" -c user.email="sylore@hotmail.com" commit -m "chore(hud): finalize element tint colors after in-game tuning"
```

---

## Self-review against the spec

- **"Persistent, always-on, no cycling needed"** → Task B3 `LoopAsync` tick + B4 `hud.start()` at load. ✓
- **"Distinguish Fire/Poison/plain by color"** → `names.AmmoElements` (B1) + `tintFor` (B3); plain = no row = restore original. ✓
- **"No second element ('I don't want two items')"** → mutates the existing widget in place (B3 `setTint` on the discovered widget); never creates a widget. ✓
- **"No FText"** → only `FLinearColor` `{R,G,B,A}` tables + image tint; no text anywhere. ✓
- **"Probe-first; build only if tint safely mutable"** → Tasks A1–A5 with an explicit GATE in A5 Step 4. ✓
- **"Restore the original tint exactly"** → `original` captured on first touch (B3) and restored for plain/no-weapon/disabled. ✓
- **"Self-heal across world reload"** → B3 `tick` re-finds the widget when `widget` goes invalid; verified in B5 Step 5. ✓
- **"Mutations in ExecuteInGameThread, pcall-guarded, keybinds-only triggers, proven keys"** → all mutations wrapped (A2/B3); probe on Shift+F7 / Ctrl+F7 (proven F7 + modifiers). ✓
- **"Data-driven; new type = one row"** → `names.AmmoElements` row (B1). ✓
- **Type/name consistency:** `names.HudWidgetMatch` / `names.HudTintProp` defined in B1 and consumed in B3; `config.HudWidgetMatch`/`HudTintProp` are the Phase-A probe equivalents (A1) used only by `hud_probe.lua`; `tintFor`/`setTint`/`findWidget`/`tick`/`hud.start` all defined and used within B3/B4. ✓
- **Identity rule:** all commits use `Syloreon Khan <sylore@hotmail.com>`; scan staged content before any push. ✓

**Note for the executor:** Phase B's element `match` strings and the widget/tint constants in Task B1 use *example* names. Replace them with the REAL values recorded in Task A4/A5 before running B1's parse-check. This is a data-transcription step (the data comes from the live probe), not a code placeholder — the module code in B3 is complete and references these constants by name.
