--[[
    Sylore Quick Swap - names.lua
    THE ONE FILE THAT DEPENDS ON PHASE-1 DISCOVERY.

    Every Dragonwilds-specific class / property / function name lives here. The rest
    of the mod is engine-generic and references only these constants. When a game
    update renames something, fix it here (and in NAMES.md) and nothing else changes.

    All values below were confirmed from the UE4SS CXX header dump (Dominion.hpp) and
    live discovery (see NAMES.md). Architecture (decoded 2026-06-02):

      Runes are inventory items, NOT a property on the staff. The "active" rune is the
      item in the player's Loadout component, slot ELoadoutSlot::MagicAmmo1 (= 6).
      Loading a rune is the right-click "use" action:
          InventoryController:UseItemFromInventory(Inventory, SlotIndex)
      where Inventory is the inventory component holding the rune and SlotIndex is the
      rune's slot in it. All components hang off the PlayerController.

    Author: Syloreon Khan <sylore@hotmail.com>
]]

local names = {}

-- ── Components (all properties on the BP_PlayerController) ────────────────────
-- Property names on the PlayerController that hold each component. Matched by
-- substring at runtime (see swap.lua), so these are the canonical names we expect.
names.LoadoutComponentProp        = "BP_Components_Loadout"
names.InventoryControllerProp     = "BP_Components_InventoryController"
names.MainInventoryProp           = "BP_Components_Inventory"          -- paged; holds the rune panel
names.PersonalInventoryProp       = "BP_Components_PersonalInventory"

-- Native classes (for IsA / class-name checks).
names.LoadoutComponentClass       = "/Script/Dominion.LoadoutComponent"
names.InventoryControllerClass    = "/Script/Dominion.InventoryController"
names.InventoryComponentClass     = "/Script/Dominion.InventoryComponent"
names.ItemClass                   = "/Script/Dominion.Item"
names.ItemDataClass               = "/Script/Dominion.ItemData"

-- Runes are items whose ItemData is a MagicAmmoData (Category tag is empty/None, so
-- this CLASS is the reliable discriminator). Confirmed live: ITEM_Rune_Air /
-- ITEM_Rune_Fire are MagicAmmoData under /Game/Gameplay/Items/Resources/Magic/.
names.MagicAmmoDataClass          = "/Script/Dominion.MagicAmmoData"
-- Arrows AND bolts are both RangedAmmoData — distinguished only by their Category tag
-- (Item.Equipment.Ammo.Arrow.* vs ...Bolt.*) and by which loadout slot they occupy.
names.RangedAmmoDataClass         = "/Script/Dominion.RangedAmmoData"
-- Leading token stripped from asset names for friendly log output ("ITEM_Rune_Fire"
-- -> "Rune_Fire"). Functional matching never relies on asset names.
names.AssetPrefix                 = "ITEM_"

-- ── Loadout slot enum (ELoadoutSlot) ─────────────────────────────────────────
-- The staff's active rune lives in the MagicAmmo1 slot. (Defined here, before the
-- strategy table below references it.)
names.ELoadoutSlot = {
    Head = 0, Body = 1, Legs = 2, Cape = 3, Trinket = 4, Ammo = 5,
    MagicAmmo1 = 6, HeldRight = 7, HeldLeft = 8, CrossbowBolts = 9, FishingBait = 10,
}
names.MagicAmmoSlot = names.ELoadoutSlot.MagicAmmo1   -- 6

-- ── Held weapon ──────────────────────────────────────────────────────────────
-- The equipped weapon sits in the HeldRight slot (HeldLeft as fallback for the rare
-- left-hand case). Its ItemData.Category tells us which ammo to cycle.
names.HeldWeaponSlots             = { names.ELoadoutSlot.HeldRight, names.ELoadoutSlot.HeldLeft } -- {7,8}

-- ── Ammo cycle strategies ────────────────────────────────────────────────────
-- One per weapon type. When V is pressed we read the held weapon's Category, pick the
-- first strategy whose `weaponTag` is a substring of it, then cycle that ammo:
--   slot      = ELoadoutSlot index whose item is the ACTIVE ammo for this weapon
--   dataClass = ItemData class leaf name a candidate item must have
--   ammoTag   = (optional) substring the item's Category must contain (separates
--               arrows from bolts, which share the RangedAmmoData class)
-- To support a new weapon/ammo later, add a row here — swap.lua needs no changes.
names.AmmoStrategies = {
    { label = "Rune",  weaponTag = "Weapon.Staff",    slot = names.ELoadoutSlot.MagicAmmo1,    dataClass = "MagicAmmoData" },
    { label = "Arrow", weaponTag = "Weapon.Bow",      slot = names.ELoadoutSlot.Ammo,          dataClass = "RangedAmmoData", ammoTag = "Ammo.Arrow" },
    { label = "Bolt",  weaponTag = "Weapon.Crossbow", slot = names.ELoadoutSlot.CrossbowBolts, dataClass = "RangedAmmoData", ammoTag = "Ammo.Bolt" },
}

-- ── Armor loadouts (equipment sets) ──────────────────────────────────────────
-- A "loadout" is a saved set of worn ARMOR pieces (weapon & ammo are left alone;
-- the V-cycle already handles ammo). Worn armor lives in these Loadout slots:
--   Head=0, Body=1, Legs=2, Cape=3 hold WearableEquipmentData items;
--   Trinket=4 holds a TrinketItemData item.
-- Equipping a piece is the SAME right-click "use" action as loading ammo:
--   InventoryController:UseItemFromInventory(BagInventory, SlotIndexOfPiece)
-- the game routes the worn piece into the correct loadout slot by item type.
names.WearableEquipmentDataClass  = "/Script/Dominion.WearableEquipmentData"
names.TrinketItemDataClass        = "/Script/Dominion.TrinketItemData"

-- Leaf class names accepted as "armor" when matching a saved asset back to a bag
-- item (a loose sanity filter; the asset name is already a unique identity).
names.ArmorDataClasses = {
    WearableEquipmentData = true,
    TrinketItemData       = true,
}

-- Ordered list of the slots a loadout saves/restores. Order = the sequence pieces
-- are re-equipped in when a set is applied. Each row: the ELoadoutSlot value and a
-- friendly label for logs. Add/remove rows to change what a loadout covers.
names.ArmorSlots = {
    { slot = names.ELoadoutSlot.Head,    label = "Head"    },
    { slot = names.ELoadoutSlot.Body,    label = "Body"    },
    { slot = names.ELoadoutSlot.Legs,    label = "Legs"    },
    { slot = names.ELoadoutSlot.Cape,    label = "Cape"    },
    { slot = names.ELoadoutSlot.Trinket, label = "Trinket" },
}

-- ── Functions we CALL ────────────────────────────────────────────────────────
-- On the LoadoutComponent (extends InventoryComponent):
--   GetSlotIndexForSlot(ELoadoutSlot Slot) -> int32
--   GetItemFromSlot(int32 SlotIndex)        -> UItem*
names.Fn_GetSlotIndexForSlot      = "GetSlotIndexForSlot"
names.Fn_GetItemFromSlot          = "GetItemFromSlot"

-- On the InventoryController — the right-click "load rune" action:
--   UseItemFromInventory(UInventoryComponent* Inventory, int32 SlotIndex)
names.Fn_UseItemFromInventory     = "UseItemFromInventory"
-- Fallback (move the rune item straight into the MagicAmmo1 slot):
--   MoveItemBetweenInventories(Source, SourceSlotIndex, Target, TargetSlotIndex) -> bool
names.Fn_MoveItemBetweenInventories = "MoveItemBetweenInventories"

-- On UInventoryComponent — enumerate contents:
names.Prop_ItemSlots              = "ItemSlots"        -- TArray<UItem*>
names.Fn_GetNumItems              = "GetNumItems"

-- ── Item identity (UItem / UItemData) ────────────────────────────────────────
--   UItem.ItemData                  -> UItemData*
--   UItem:GetPlayerFacingName()     -> FText  ("Air Rune", "Fire Rune", ...)
--   UItem:HasTag(FGameplayTag)      -> bool
--   UItemData.Category              -> FGameplayTag   (shared by all runes)
names.Prop_ItemData               = "ItemData"
names.Fn_GetPlayerFacingName      = "GetPlayerFacingName"
names.Prop_ItemCategory           = "Category"

return names
