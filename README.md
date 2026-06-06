# Sylore Quick Swap

A quality-of-life mod for **RuneScape: Dragonwilds** (Unreal Engine 5) that adds two
combat conveniences, so you never have to dig through the inventory mid-fight:

- **Quick-swap ammo** — one key cycles the loaded ammo for whatever weapon you're holding:
  staff **runes**, bow **arrows**, or crossbow **bolts**. Each weapon remembers its own
  selection.
- **Armor loadouts** — save up to four armor sets and re-equip a whole set with a single
  function key.

Built on **UE4SS** (Lua). Single-player tested.

- **Author:** Syloreon Khan <sylore@hotmail.com>

## Controls (defaults — edit in `scripts/config.lua`)

| Action | Key |
|---|---|
| Cycle held weapon's ammo → next | `V` |
| Cycle held weapon's ammo → previous | `Shift + V` |
| Apply armor loadout 1–4 | `F1` / `F2` / `F3` / `F4` |
| Save current armor into loadout 1–4 | `Shift + F1` … `Shift + F4` |

Ammo cycling picks the right ammo automatically from the equipped weapon (staff→runes,
bow→arrows, crossbow→bolts) and only touches that weapon's slot — your other weapons keep
their selection. Armor loadouts cover Head/Body/Legs/Cape/Trinket and leave weapon & ammo
alone. Saving over a loadout slot overwrites it. Saved sets persist to `loadouts.txt` in the
mod folder and reload on startup.

## Requirements

- RuneScape: Dragonwilds (Steam) installed.
- [UE4SS for RSDragonwilds](https://www.nexusmods.com/runescapedragonwilds/mods/4) installed
  into `...\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\`
  (`dwmapi.dll` proxy + `ue4ss\` folder beside `RSDragonwilds-Win64-Shipping.exe`).

## Install

1. Copy the **`SyloreQuickSwap`** folder (this folder) into:
   `...\Binaries\Win64\ue4ss\Mods\SyloreQuickSwap\`
   (so the path is `...\ue4ss\Mods\SyloreQuickSwap\scripts\main.lua`).
2. Add a line to `ue4ss\Mods\mods.txt` (or keep the bundled `enabled.txt`):
   ```
   SyloreQuickSwap : 1
   ```
3. Launch the game. The UE4SS log should print `[Sylore Quick Swap] loaded.`

## Configuration (`scripts/config.lua`)

- **Keybinds** for every action above (`Key.*` / `ModifierKey.*` from the UE4SS Lua API).
- **`WrapAround`** — cycle past the last ammo back to the first.
- **`AmmoOrder`** — optional explicit cycle order (by item asset name); alphabetical otherwise.
- **`LoadoutSlotCount`** / **`LoadoutApplyKeys`** — number of loadout slots and their keys.
- **`LoadoutsFile`** — leave empty to auto-save next to the mod (portable); set a full path to override.
- **`ShowOnScreenFeedback`** / **`Verbose`** — console feedback and debug logging.

## How it works

Runes, arrows and bolts are inventory items; the "loaded" ammo is the item in a specific
loadout slot. Armor pieces work the same way. Both features use the game's own right-click
"use/equip" action (`InventoryController:UseItemFromInventory`), so the mod just presses the
same in-game action you already can — faster. It does **not** bypass cooldowns/timers or grant
items, staying within Jagex's
[Community Modding Guidelines](https://legal.jagex.com/docs/policies/runescape-dragonwilds-community-modding-guidelines).

Everything is resolved live on each press, so rearranging items in your bags never breaks the
cycle (ammo is ordered by stable item identity, not slot position).

## Files

```
SyloreQuickSwap/
  scripts/
    main.lua        entry point: registers keybinds
    config.lua      user settings (keys, order, options)
    names.lua       Dragonwilds-specific symbols (the only file to touch on a game update)
    swap.lua        ammo cycle (runes / arrows / bolts)
    loadouts.lua    armor loadouts (save / apply sets)
    discovery.lua   optional dev toolbox for re-mapping names (not loaded in normal play)
  enabled.txt
  NAMES.md          reverse-engineering / discovery record
  README.md
```

## Compatibility & maintenance

- Single-player tested. Dedicated-server use is out of scope.
- Early Access updates may rename internal classes/functions. If something stops working, all
  Dragonwilds-specific names live in `scripts/names.lua` — fix them there (set
  `config.DiscoveryMode = true` and use `scripts/discovery.lua` to re-probe; see `NAMES.md`).
- `F1`–`F4` are used for loadouts; if a future game patch binds them, remap `LoadoutApplyKeys`
  in `config.lua`.

## License

[MIT](LICENSE) © Syloreon Khan
