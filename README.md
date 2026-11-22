# Provisions Restock
[![CurseForge](https://cf.way2muchnoise.eu/1508583.svg?badge_style=for_the_badge)](https://www.curseforge.com/wow/addons/provisions-restock)

Restock class reagents, food, water, and ammunition at vendors in **World of Warcraft: Forever**. Provisions Restock docks beside the merchant and starts folded when the vendor has no matching supplies. Click **Restock** beside **Buyback** to open it, or click the selected **Restock** tab to fold it again.

## Restock

1. Open a vendor that sells your supplies.
2. **Keep** starts at one bag stack for a new supply. Enter a different amount and press Enter or click away to save. Clear the field or enter `0` to turn off that target.
3. Click **Buy** on a row. Hover over the button to see quantities and price.

Targets are saved per character. Rogues can add a learned poison's exact item link or ID in **Customize**. At reagent vendors, **Buy** gets the missing materials for that rank. Craft the poison in the Poisons window.

Hover over an item for its spell or purpose. Rebirth, Gift of the Wild, and Prayer of Fortitude let you choose among learned ranks.

**Auto stock starts off.** With a positive Keep target, check **Auto stock** on an eligible item to refill it on future visits. Checking the box during a visit saves the choice. You can click **Buy** for that visit. Clear the target or uncheck the box to stop refills. Automatic purchases are limited to individually opted-in direct items. A detected **Reagent Economy** perk pauses class reagent auto-stock, and **Buy** is available for a manual backup.

Each Keep target counts the exact item in your bags. Bank items do not count.

## Customize

**Restock** uses the class defaults with **Show** checked and the custom items you add. Uncheck **Show** to hide a default and pause its Auto stock. To add food, water, ammo, or any other custom item, click the Add field, Shift-click a bag item, then press Enter or click **Add**. Pasted links and numeric IDs work too. Custom items have a **Remove** button.

## Commands

| Command | Use |
| --- | --- |
| `/provisions` | Switch to Customize while the merchant is open. |
| `/provisions add <item link or ID> [Keep]` | Add a custom item and optionally set its Keep target. |
| `/provisions remove <item link or ID>` | Remove a custom item and its target. |
