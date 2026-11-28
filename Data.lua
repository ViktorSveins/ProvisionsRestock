-- Generated from Blizzard's WoW Forever 1.60.1.71139 client tables.
-- Source exports and checksums: .github/scripts/generate_data.py
-- https://wago.tools/db2/SpellReagents/csv?build=1.60.1.71139

local _, addon = ...

addon.ClassSupplies = {
    MAGE = {
        {
            itemID = 17032,
            spells = { 10059, 11416, 11417, 11418, 11419, 11420 },
            kind = "direct",
            purpose = "Group portals",
        },
        {
            itemID = 17031,
            spells = { 3561, 3562, 3563, 3565, 3566, 3567, 1297659 },
            kind = "direct",
            purpose = "Teleport",
        },
        { itemID = 17020, spells = { 23028 }, kind = "direct", purpose = "Arcane Brilliance" },
    },
    PALADIN = {
        {
            itemID = 21177,
            spells = { 25782, 25894, 25898, 25916, 25918 },
            kind = "direct",
            purpose = "Greater Blessings",
        },
        { itemID = 17033, spells = { 19752 }, kind = "direct", purpose = "Divine Intervention" },
    },
    SHAMAN = { { itemID = 17030, spells = { 20608, 21169 }, kind = "direct", purpose = "Reincarnation" } },
    PRIEST = {
        {
            key = "fortitude",
            kind = "direct",
            purpose = "Prayer of Fortitude",
            variants = { { itemID = 17029, spells = { 21564 }, rank = 2 }, { itemID = 17028, spells = { 21562 }, rank = 1 } },
        },
        {
            itemID = 17029,
            spells = { 27681, 27683 },
            kind = "direct",
            purpose = "Group prayers",
            purposes = { { spells = { 27681 }, label = "Spirit" }, { spells = { 27683 }, label = "Shadow Protection" } },
        },
    },
    DRUID = {
        {
            key = "rebirth",
            kind = "direct",
            purpose = "Rebirth",
            variants = {
                { itemID = 17038, spells = { 20748 }, rank = 5 },
                { itemID = 17037, spells = { 20747 }, rank = 4 },
                { itemID = 17036, spells = { 20742 }, rank = 3 },
                { itemID = 17035, spells = { 20739 }, rank = 2 },
                { itemID = 17034, spells = { 20484 }, rank = 1 },
            },
        },
        {
            key = "gift-of-the-wild",
            kind = "direct",
            purpose = "Gift of the Wild",
            variants = { { itemID = 17026, spells = { 21850 }, rank = 2 }, { itemID = 17021, spells = { 21849 }, rank = 1 } },
        },
    },
    ROGUE = { { itemID = 5140, spells = { 1856, 1857 }, kind = "direct", purpose = "Vanish" } },
    WARLOCK = {
        { itemID = 5565, spells = { 1122 }, kind = "direct", purpose = "Inferno" },
        { itemID = 16583, spells = { 18540 }, kind = "direct", purpose = "Ritual of Doom" },
    },
}

addon.Poisons = {
    {
        key = "instant",
        purpose = "Direct damage",
        ranks = {
            {
                spellID = 8681,
                itemID = 6947,
                outputCount = 1,
                reagents = { { itemID = 2928, count = 1 }, { itemID = 3371, count = 1 } },
            },
            {
                spellID = 8687,
                itemID = 6949,
                outputCount = 1,
                reagents = { { itemID = 2928, count = 3 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 8691,
                itemID = 6950,
                outputCount = 1,
                reagents = { { itemID = 8924, count = 1 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 11341,
                itemID = 8926,
                outputCount = 1,
                reagents = { { itemID = 8924, count = 2 }, { itemID = 8925, count = 1 } },
            },
            {
                spellID = 11342,
                itemID = 8927,
                outputCount = 1,
                reagents = { { itemID = 8924, count = 3 }, { itemID = 8925, count = 1 } },
            },
            {
                spellID = 11343,
                itemID = 8928,
                outputCount = 1,
                reagents = { { itemID = 8924, count = 4 }, { itemID = 8925, count = 1 } },
            },
        },
    },
    {
        key = "deadly",
        purpose = "Damage over time",
        ranks = {
            {
                spellID = 2835,
                itemID = 2892,
                outputCount = 1,
                reagents = { { itemID = 5173, count = 1 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 2837,
                itemID = 2893,
                outputCount = 1,
                reagents = { { itemID = 5173, count = 2 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 11357,
                itemID = 8984,
                outputCount = 1,
                reagents = { { itemID = 5173, count = 3 }, { itemID = 8925, count = 1 } },
            },
            {
                spellID = 11358,
                itemID = 8985,
                outputCount = 1,
                reagents = { { itemID = 5173, count = 5 }, { itemID = 8925, count = 1 } },
            },
            {
                spellID = 25347,
                itemID = 20844,
                outputCount = 1,
                reagents = { { itemID = 5173, count = 7 }, { itemID = 8925, count = 1 } },
            },
        },
    },
    {
        key = "crippling",
        purpose = "Slows movement",
        ranks = {
            {
                spellID = 3420,
                itemID = 3775,
                outputCount = 1,
                reagents = { { itemID = 2930, count = 1 }, { itemID = 3371, count = 1 } },
            },
            {
                spellID = 3421,
                itemID = 3776,
                outputCount = 1,
                reagents = { { itemID = 8923, count = 3 }, { itemID = 8925, count = 1 } },
            },
        },
    },
    {
        key = "mind-numbing",
        purpose = "Slows spellcasting",
        ranks = {
            {
                spellID = 5763,
                itemID = 5237,
                outputCount = 1,
                reagents = { { itemID = 2928, count = 1 }, { itemID = 2930, count = 1 }, { itemID = 3371, count = 1 } },
            },
            {
                spellID = 8694,
                itemID = 6951,
                outputCount = 1,
                reagents = { { itemID = 2928, count = 4 }, { itemID = 2930, count = 4 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 11400,
                itemID = 9186,
                outputCount = 1,
                reagents = { { itemID = 8924, count = 2 }, { itemID = 8923, count = 2 }, { itemID = 8925, count = 1 } },
            },
        },
    },
    {
        key = "wound",
        purpose = "Reduces healing",
        ranks = {
            {
                spellID = 13220,
                itemID = 10918,
                outputCount = 1,
                reagents = { { itemID = 2930, count = 1 }, { itemID = 5173, count = 1 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 13228,
                itemID = 10920,
                outputCount = 1,
                reagents = { { itemID = 2930, count = 1 }, { itemID = 5173, count = 2 }, { itemID = 3372, count = 1 } },
            },
            {
                spellID = 13229,
                itemID = 10921,
                outputCount = 1,
                reagents = { { itemID = 8923, count = 1 }, { itemID = 5173, count = 2 }, { itemID = 8925, count = 1 } },
            },
            {
                spellID = 13230,
                itemID = 10922,
                outputCount = 1,
                reagents = { { itemID = 8923, count = 2 }, { itemID = 5173, count = 2 }, { itemID = 8925, count = 1 } },
            },
        },
    },
    {
        key = "blinding-powder",
        purpose = "Blind",
        gatheredOnly = true,
        ranks = { { spellID = 6510, itemID = 5530, outputCount = 3, reagents = { { itemID = 3818, count = 1 } } } },
    },
}
