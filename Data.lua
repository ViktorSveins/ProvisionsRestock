-- Forever reagent mappings adapted from Jagerente's ReReagent.
-- https://github.com/Jagerente/ReReagent/blob/main/Data/Reagents.lua
--[[
MIT License

Copyright (c) 2026 Jagerente

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local _, addon = ...

-- Each spell list is a set of alternative learned spells giving a reason to stock the item.
addon.ClassSupplies = {
    MAGE = {
        { itemID = 17032, spells = { 10059, 11416, 11417, 11418, 11419, 11420 }, kind = "direct", purpose = "Group portals" }, -- Rune of Portals
        { itemID = 17031, spells = { 3561, 3562, 3563, 3565, 3566, 3567, 1297659 }, kind = "direct", purpose = "Teleport" }, -- Rune of Teleportation
        { itemID = 17020, spells = { 23028 }, kind = "direct", purpose = "Arcane Brilliance" }, -- Arcane Powder
    },
    PALADIN = {
        { itemID = 21177, spells = { 25782, 25894, 25898, 25916, 25918 }, kind = "direct", purpose = "Greater Blessings" }, -- Symbol of Kings
        { itemID = 17033, spells = { 19752 }, kind = "direct", purpose = "Divine Intervention" }, -- Symbol of Divinity
    },
    SHAMAN = {
        { itemID = 17030, spells = { 20608, 21169 }, kind = "direct", purpose = "Reincarnation" }, -- Ankh
    },
    PRIEST = {
        {
            key = "fortitude",
            kind = "direct",
            purpose = "Prayer of Fortitude",
            variants = {
                { itemID = 17029, spells = { 21564 }, rank = 2 }, -- Sacred Candle
                { itemID = 17028, spells = { 21562 }, rank = 1 }, -- Holy Candle
            },
        },
        {
            itemID = 17029, -- Sacred Candle
            spells = { 27681, 27683 },
            kind = "direct",
            purpose = "Group prayers",
            purposes = {
                { spells = { 27681 }, label = "Spirit" },
                { spells = { 27683 }, label = "Shadow Protection" },
            },
        },
    },
    DRUID = {
        {
            key = "rebirth",
            kind = "direct",
            purpose = "Rebirth",
            variants = {
                { itemID = 17038, spells = { 20748 }, rank = 5 }, -- Ironwood Seed
                { itemID = 17037, spells = { 20747 }, rank = 4 }, -- Hornbeam Seed
                { itemID = 17036, spells = { 20742 }, rank = 3 }, -- Ashwood Seed
                { itemID = 17035, spells = { 20739 }, rank = 2 }, -- Stranglethorn Seed
                { itemID = 17034, spells = { 20484 }, rank = 1 }, -- Maple Seed
            },
        },
        {
            key = "gift-of-the-wild",
            kind = "direct",
            purpose = "Gift of the Wild",
            variants = {
                { itemID = 17026, spells = { 21850 }, rank = 2 }, -- Wild Thornroot
                { itemID = 17021, spells = { 21849 }, rank = 1 }, -- Wild Berries
            },
        },
    },
    ROGUE = {
        { itemID = 5140, spells = { 1856, 1857 }, kind = "direct", purpose = "Vanish" }, -- Flash Powder
    },
    WARLOCK = {
        { itemID = 5565, spells = { 1122 }, kind = "direct", purpose = "Inferno" }, -- Infernal Stone
        { itemID = 16583, spells = { 18540 }, kind = "direct", purpose = "Ritual of Doom" }, -- Demonic Figurine
    },
}

-- Forever spell records, including Create Item effects:
-- https://db.icy-veins.com/wow-forever/spells/11343
-- https://db.icy-veins.com/wow-forever/spells/25347
-- https://db.icy-veins.com/wow-forever/spells/6510
local dustOfDecay = 2928
local essenceOfPain = 2930
local deathweed = 5173
local essenceOfAgony = 8923
local dustOfDeterioration = 8924
local emptyVial = 3371
local leadedVial = 3372
local crystalVial = 8925
local fadeleaf = 3818

local function Ingredient(itemID, count)
    return { itemID = itemID, count = count }
end

local function Recipe(spellID, itemID, outputCount, reagents)
    return { spellID = spellID, itemID = itemID, outputCount = outputCount, reagents = reagents }
end

addon.Poisons = {
    {
        key = "instant",
        purpose = "Direct damage",
        ranks = {
            Recipe(8681, 6947, 1, { Ingredient(dustOfDecay, 1), Ingredient(emptyVial, 1) }),
            Recipe(8687, 6949, 1, { Ingredient(dustOfDecay, 3), Ingredient(leadedVial, 1) }),
            Recipe(8691, 6950, 1, { Ingredient(dustOfDeterioration, 1), Ingredient(leadedVial, 1) }),
            Recipe(11341, 8926, 1, { Ingredient(dustOfDeterioration, 2), Ingredient(crystalVial, 1) }),
            Recipe(11342, 8927, 1, { Ingredient(dustOfDeterioration, 3), Ingredient(crystalVial, 1) }),
            Recipe(11343, 8928, 1, { Ingredient(dustOfDeterioration, 4), Ingredient(crystalVial, 1) }),
        },
    },
    {
        key = "deadly",
        purpose = "Damage over time",
        ranks = {
            Recipe(2835, 2892, 1, { Ingredient(deathweed, 1), Ingredient(leadedVial, 1) }),
            Recipe(2837, 2893, 1, { Ingredient(deathweed, 2), Ingredient(leadedVial, 1) }),
            Recipe(11357, 8984, 1, { Ingredient(deathweed, 3), Ingredient(crystalVial, 1) }),
            Recipe(11358, 8985, 1, { Ingredient(deathweed, 5), Ingredient(crystalVial, 1) }),
            Recipe(25347, 20844, 1, { Ingredient(deathweed, 7), Ingredient(crystalVial, 1) }),
        },
    },
    {
        key = "crippling",
        purpose = "Slows movement",
        ranks = {
            Recipe(3420, 3775, 1, { Ingredient(essenceOfPain, 1), Ingredient(emptyVial, 1) }),
            Recipe(3421, 3776, 1, { Ingredient(essenceOfAgony, 3), Ingredient(crystalVial, 1) }),
        },
    },
    {
        key = "mind-numbing",
        purpose = "Slows spellcasting",
        ranks = {
            Recipe(5763, 5237, 1, { Ingredient(dustOfDecay, 1), Ingredient(essenceOfPain, 1), Ingredient(emptyVial, 1) }),
            Recipe(8694, 6951, 1, { Ingredient(dustOfDecay, 4), Ingredient(essenceOfPain, 4), Ingredient(leadedVial, 1) }),
            Recipe(11400, 9186, 1, { Ingredient(dustOfDeterioration, 2), Ingredient(essenceOfAgony, 2), Ingredient(crystalVial, 1) }),
        },
    },
    {
        key = "wound",
        purpose = "Reduces healing",
        ranks = {
            Recipe(13220, 10918, 1, { Ingredient(essenceOfPain, 1), Ingredient(deathweed, 1), Ingredient(leadedVial, 1) }),
            Recipe(13228, 10920, 1, { Ingredient(essenceOfPain, 1), Ingredient(deathweed, 2), Ingredient(leadedVial, 1) }),
            Recipe(13229, 10921, 1, { Ingredient(essenceOfAgony, 1), Ingredient(deathweed, 2), Ingredient(crystalVial, 1) }),
            Recipe(13230, 10922, 1, { Ingredient(essenceOfAgony, 2), Ingredient(deathweed, 2), Ingredient(crystalVial, 1) }),
        },
    },
    {
        key = "blinding-powder",
        purpose = "Blind",
        gatheredOnly = true,
        ranks = {
            Recipe(6510, 5530, 3, { Ingredient(fadeleaf, 1) }),
        },
    },
}
