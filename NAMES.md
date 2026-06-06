# Discovered Dragonwilds symbols (Phase 1)

Fill this in from the UE4SS console using `scripts/discovery.lua`, then copy the
confirmed values into `scripts/names.lua`. Keep this file as the human-readable
record of *how* each name was found, so re-discovery after a game update is fast.

| names.lua key | Confirmed value | How it was found / notes |
|---|---|---|
| `EquipmentComponentClass` | _TODO_ | `RQS.find("...Component")`, pick the one referencing the staff |
| `StaffWeaponClass` | _TODO_ | `RQS.find("Staff")` while a staff is equipped |
| `EquippedWeaponProperty` | _TODO_ | `RQS.props(equipmentComponent)` — property pointing at the staff |
| `CurrentRuneProperty` | _TODO_ | `RQS.props(staff)` — property holding the active rune |
| `AvailableRunesProperty` | _TODO_ | `RQS.props(...)` — the TArray of runes (on staff or inventory/equip comp) |
| `RuneIdProperty` | _TODO_ | a stable id on a rune item (ItemId / row name / DisplayName) |
| `SetActiveRuneFunction` | _TODO_ | `RQS.hookWatch({...})`, then click a rune in the UI; the hook that fires |
| `SetActiveRuneTarget` | `staff` / `equipment` / `pawn` | which object owns `SetActiveRuneFunction` |

## Session log

### 2026-06-02 — first live dumps (UE4SS 4.3.0.1, F8 discovery harness)
Confirmed so far (everything is Blueprint-driven `BlueprintGeneratedClass`, names end in `_C`):

- **Pawn:** `BP_PlayerCharacter_C`
  (`/Game/Gameplay/Character/Player/BP_PlayerCharacter.BP_PlayerCharacter_C`)
- **Equipment component:** pawn property `.BP_Components_PlayerEquipment` →
  `BP_Components_PlayerEquipment_C`
  (`/Game/Gameplay/Character/Components/BP_Components_PlayerEquipment...`)
  - `.HeldEquipmentActorRight` [ObjectProperty] → **the equipped staff** =
    `BP_Staff_Battlestaff_C` ✅ (this is the staff in the right hand)
  - `.HeldEquipmentActorLeft` [ObjectProperty] → off-hand actor
  - `.HeldRightSocketName` = `prop_r`, `.HeldLeftSocketName` = `prop_L`
  - `.BP_OnHeldEquipmentChanged` / `.BP_OnWornEquipmentChanged` (multicast delegates)
  - wearables: `.CurrentHeadWearable/.CurrentBodyWearable/...` → `WearableEquipmentData`
- **Other candidate components on the pawn:** `BP_Components_PlayerCombatMagic_C`,
  `BP_Components_PlayerCombatMode_C`, `BP_Components_PlayerRangedAttack_C`,
  `BP_Components_PlayerUtilityMagic_C`.

**Still TODO:** dump `BP_Staff_Battlestaff_C` (and/or the CombatMagic component) for the
current-rune property, the available-runes list, and the set-rune UFunction. Next F8 run
(crash-safe metadata-only dumper) targets exactly these.

### 2026-06-02 — second run (clean reinstall), equipment props confirmed + flush fix
Full property list of `BP_Components_PlayerEquipment_C` captured (props only; the run
crashed when it moved on to the function enumeration, before reaching the staff):
`BP_OnHeldEquipmentChanged`, `BP_OnWornEquipmentChanged`, `HeldRightSocketName`,
`HeldLeftSocketName`, `bHideEquipmentOnBreak`, `MeleeWeaponCategoryTagContainer`,
`HeldEquipmentActorLeft`, `HeldEquipmentActorRight` (→ staff), then wearable/mesh props
(`CurrentHeadWearable`/`CurrentBodyWearable`/`CurrentLegsWearable`/`CurrentCapeWearable`,
various `*Mesh`), `OwningController`, and the usual `ActorComponent` base members
(`bIsActive`, `OnComponentActivated/Deactivated`, …). No rune/spell list lives here — it's
on the staff or CombatMagic component.

**New gotcha — log buffering hides crash point:** UE4SS's `UE4SS.log` is buffered, so a hard
C++ crash drops everything since the last flush (all output landed on ONE unterminated line).
Fix: `discovery.lua` now writes every line to a flushed file via open-append-close. Props are
dumped BEFORE functions so a function-walk crash still leaves properties saved.

**Crash root cause (FIXED):** the class-chain walker stepped one level PAST the root
`/Script/CoreUObject.Object` into an unresolved engine metaclass (`fq` = `UClass: 0x…`) and
`ForEachProperty` on that garbage object hard-crashed. Walker now only recurses into structs
whose full name contains `/Script/` or `/Game/` and stops at `CoreUObject.Object`. Dumps now
complete cleanly. Per-command output files: `discovery-staff.txt`, `discovery-player.txt`,
`discovery-equip.txt`, `discovery-hooks.txt`. Keys: **F8 = equip+controller**,
**F9 = player+components**, **F7 = arm hooks**.

### 2026-06-02 — ARCHITECTURE BREAKTHROUGH: runes are "magic ammo"
The staff/mace (`Dominion.HeldEquipmentActor` base) has **no rune state** — only
`GetHeldEquipmentItem/Data`. Runes are handled as **MagicAmmo**, exactly parallel to how
**arrows** are ammo for the bow:
- `Dominion.PlayerCombatMagicComponent` (on pawn as `BP_Components_PlayerCombatMagic`) CONSUMES
  magic ammo to cast spells. Props: `EquippedMagicAmmoToPrimaryStarterSpell` /
  `…SecondaryStarterSpell` (Maps: equipped rune → spell), delegates `OnSpellActiveChange`,
  `OnSpellFailedNoAmmo`, `OnRefundRuneCost`. Parent chain → `Dominion.PlayerMagicComponent`.
  It has NO set/select-ammo function — it only reacts.
- `Dominion.PlayerRangedAttackComponent` (the bow sibling) confirms the pattern: `.EquipmentComponent`,
  `:OnAmmoItemChanged()` (reaction callback), `:HasRequiredAmmoEquipped()`,
  `:GetEquippedRangedAmmoDataForCurrentWeapon()` — but again NO "SetAmmo". Ammo is *equipped*.
- Pawn (`Dominion.DominionPlayerCharacter`) has per-slot change reactions:
  `OnAnyHeldItemChanged`, `OnHeldRightItemChanged`, `OnTrinketItemChanged`, etc. (no ammo one seen),
  plus component getters `GetPlayerCombatMagicComponent`, `GetPlayerEquipmentComponent`, …
- No `Inventory`/`Ammo` component directly on the pawn → inventory likely lives on the
  **PlayerController**.

**Conclusion:** swapping a rune = **equipping a different rune item into the magic-ammo slot**
(an inventory/equip operation), NOT writing an "active rune" property. So the function we need is
an **EquipItem / SetEquippedAmmo**-style call on `BP_Components_PlayerEquipment` (its FUNCTIONS
were never captured — lost to the first crash) or on the **PlayerController/inventory**. Next
step: **F8 = `dumpEquipAndController()`** captures exactly those. After that, F7 hooks the
chosen candidate and we swap a rune in-game to confirm.

Other confirmed pawn component names (full list saved in `discovery-player.txt`): combat set is
`BP_Components_PlayerMeleeAttack`, `…PlayerRangedAttack`, `…PlayerCombatMagic`,
`…PlayerUtilityMagic`, `…PlayerCombatMode`, `…PlayerEquipment`, `…PlayerBlocking`. The native
module prefix is `Dominion` and many components are also exposed as `*ComponentRef` structs +
`Get*Component()` accessors on `DominionPlayerCharacter`.

### 2026-06-02 — SOLVED the rune location: Loadout "MagicAmmo1" slot
`PlayerEquipment` only handles held weapons + armor/wearables (NOT ammo) — ruled out. The
magic/inventory system lives on the **PlayerController** (`BP_PlayerController_C`). Key components
(all reachable from the controller; saved in `discovery-equip.txt` + `discovery-magic.txt`):
- **`BP_Components_Loadout` → `Dominion.LoadoutComponent`** — THE rune home. It's an inventory
  whose slots are equipment slots, with per-slot change delegates:
  `OnHeldRightItemChanged`, `OnAmmoItemChanged` (arrows), **`OnMagicAmmo1Changed` (the RUNE)**,
  `OnCrossbowBoltsItemChanged`, `OnFishingBaitChanged`, … Slot identity comes from
  `.LoadoutSlotEnum`. Helpers: `GetSlotIndexForSlot`, `GetSlotForSlotIndex`, `GetItemFromSlot`,
  `GetEquipmentFromSlot`, `IsEquipped`, `FindSlotFromEquipment`, `GetSlotIndexForItem`.
  Parent chain: `LoadoutComponent → InventoryWithLogComponent → InventoryComponent`.
- **`Dominion.InventoryComponent`** (base of Loadout + all inventories) — item ops:
  `GetItemFromSlot`, `GetItemSlots`, `AddItemToSlot`, `AddItemByDataToSlot`, `RemoveFromSlot`,
  `MoveItem`, `MoveAllItems`, `GetAllItemsOfClass`, `ContainsItem`, `IsItemAllowed`,
  `GetSlotForItemByCategory`, `.ItemSlots [Array]`, `.JsonInventory [Str]`.
- **`BP_Components_InventoryController` → `Dominion.InventoryController`** — drives moves:
  `MoveItemBetweenInventories`, `MoveItemBetweenInventoriesAnySlot`,
  `Server_MoveItemBetweenInventories`, `UseItemFromInventory`/`Server_UseItemFromInventory`.
- `BP_Components_Inventory` (paged backpack) and `BP_Components_PersonalInventory` — same
  `InventoryComponent` base; the backpack holds the spare runes.
- `BP_Components_Spellcasting → Dominion.SpellcastingComponent` — `.SelectedSpells [Array]`,
  `Server_SwapSpells`, spell radials/placement. This is the UTILITY/placeable-spell selection,
  NOT the combat staff rune. Probably not what we want (keep as a fallback lead).

**Mechanism:** swapping a rune = moving a different rune item into the Loadout's **MagicAmmo1**
slot (server-authoritative inventory move), NOT a simple property set. Next step: **F7 hook
trace** — `armRuneHooks()` now watches the InventoryController/InventoryComponent move/use
functions (+ `LoadoutComponent:OnReceiveInventoryChanged`) and logs args. User drags a different
rune into the staff's magic-ammo slot once; whichever fires + its arg values = the exact call the
mod must replicate. Output → `discovery-hooks.txt`.

**Still needed for names.lua / swap.lua:** the MagicAmmo1 slot enum value + slot index; the item
category/filter that identifies a "rune"; and the confirmed move/equip call signature (from the
hook trace). The mod's cycle = read current MagicAmmo1 item → find next rune in backpack → move
it into MagicAmmo1 (swapping the old one back).

**User-confirmed UX (2026-06-02):** you **RIGHT-CLICK** a rune in the inventory to load it (same
for arrows). **Staffs load only 2 runes at once** (matches CombatMagic's primary+secondary
starter-spell maps) — so cycle logic must account for a primary/secondary pair, not a single
active rune.

**Hook trace #1 result (SURPRISE):** with F7 watching the 9 obvious inventory verbs
(`UseItemFromInventory`/`Server_UseItemFromInventory`, `MoveItemBetweenInventories`(+Server,
+AnySlot), `MoveItem`, `AddItemToSlot`, `AddItemByDataToSlot`, `RemoveFromSlot`) + 
`LoadoutComponent:OnReceiveInventoryChanged`, a real right-click rune load fired **ONLY**
`OnReceiveInventoryChanged` (~40× — it's a noisy replication callback). **NONE of the move/use
verbs fired.** So right-click-load does NOT go through those — the equip happens via some other
function. Prime unexplored suspect: **`Dominion.AutoEquipComponent`** (on the controller as
`.AutoEquipComponent`; never dumped — yielded nothing in the F8 magic dump). 

**Next action (queued):** `armRuneHooks` was rewritten to a BROAD auto-hook — it enumerates every
function across the controller's Inventory/Loadout/AutoEquip/Spellcasting components + the pawn's
PlayerEquipment/PlayerCombatMagic/PlayerRangedAttack, and hooks all *verb-like* names
(include: equip/ammo/magic/rune/swap/useitem/moveitem/additem/removefrom/slot/loadout/select/active;
exclude: onrep/onreceive/get/is/has/find/.../debug) with arg logging. So on resume: **restart game →
in-game with staff + 2 rune types → F7 → right-click-load a different rune → read
`discovery-hooks.txt`** to see exactly which function does the equip (+ its args). That's the call
the mod replicates.

**Gotcha learned:** UE4SS `ForEachProperty`/`ForEachFunction` only return members declared on
the EXACT class — must walk the superclass chain (`GetSuperStruct`) to see native members.
Reading arbitrary native property *values* can hard-crash the game (C++ access violation,
uncatchable by Lua pcall); the discovery dumper is now metadata-only (names/types/functions),
reading values only for a few known-safe object pointers used to navigate.
