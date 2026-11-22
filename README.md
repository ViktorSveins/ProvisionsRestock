# Provisions Restock

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
| `/provisions food <item link or ID>` | Add a specific food as a custom item. |
| `/provisions water <item link or ID>` | Add a specific drink as a custom item. |

## Installation and development

Run the build command from this repository.

| Build | Command | Install |
| --- | --- | --- |
| Release | `.\build.ps1` | Extract `build\ProvisionsRestock.zip` into `World of Warcraft\_forever_\Interface\AddOns\`. |
| Dev | `.\build.ps1 -Mode Dev` | Copy `build\Dev\ProvisionsRestock` into the same AddOns directory. |

The release uses `ProvisionsRestock.toc`. The dev build generates a TOC that loads `DevProfiles.lua`. Both target Forever interface `16001` and install as `ProvisionsRestock`. Restart WoW after switching build types.

If upgrading from the `Provisions` folder, exit WoW and move the old addon out of `AddOns`. To keep your settings, copy `Provisions.lua` to `ProvisionsRestock.lua` inside each character's `SavedVariables` directory before starting the game.

### CurseForge releases

`ProvisionsRestock.toc` identifies CurseForge project `1824496`. Save a CurseForge author upload token as `CF_API_TOKEN` in the repository's Actions secrets. [CurseForge token instructions](https://support.curseforge.com/support/solutions/articles/9000197321) · [GitHub Actions secrets](https://github.com/ViktorSveins/ProvisionsRestock/settings/secrets/actions)

Update `## Version` in `ProvisionsRestock.toc`, commit it, and push a matching tag such as `v1.0.1`. GitHub Actions builds the Forever ZIP and uploads it to CurseForge.

### Character profiler

Use `/provisionsdev list` to see the profiles, then open a vendor after selecting one.

| Command | Action |
| --- | --- |
| `/provisionsdev use rogue-max` | Use a level 60 Rogue with every catalog poison rank. |
| `/provisionsdev use hunter-bow` | Use a level 60 Hunter with arrows in the simulated bags. |
| `/provisionsdev use hunter-gun` | Use a level 60 Hunter with a gun. |
| `/provisionsdev status` | Show the active profile and simulated funds. |
| `/provisionsdev reset` | Restore the active profile's starting settings, supplies, and funds. |
| `/provisionsdev off` | Return to the logged-in character on the next visit. |

Close the vendor before changing or resetting profiles. The panel shows the active profile under **Simulation**. **Buy**, **Test ×5**, and the profile's opted-in auto-stock use the current vendor's offers while updating the profile's bags, wallet, and limited stock. WoW’s native merchant buttons still act on the logged-in character. Profile state lasts until `/reload` or client exit. Edit the profile table in `DevProfiles.lua` to add scenarios.

Run `lua tests/restock.lua` for mocked vendor, profile, and purchase checks. For a live check, log in on a low-level character of another class. Add a poison to the Rogue profile or ammo to a Hunter profile and visit an appropriate vendor. Confirm the NPC’s offers and prices match, and compare real bag counts and money before and after a simulated order.

Class reagent data incorporates material from ReReagent under MIT. See the attribution in [Data.lua](Data.lua).
