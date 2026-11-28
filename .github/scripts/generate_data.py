"""Generate Data.lua from Blizzard's Forever client tables exported by Wago."""

import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from decimal import Decimal
from pathlib import Path


BUILD = "1.60.1.71139"
SOURCE_HASHES = {
    "SkillLineAbility": "ecdc96fca011a72281802b0a10e6e36dbcc9c072c2dfae93b5ceaa9f31aa74e7",
    "Spell": "cc8e495092e5030ccfc2719dd052948cb7e6debca79584260abd560582b855fc",
    "SpellEffect": "970158fb0ea34695b1d59837a8a612d72b76592f941324372095e1566ea461f2",
    "SpellLevels": "f7a4ee0244a9363e15a2aec0cc69525d7b1e75e11518df920608b285eedd4fc8",
    "SpellName": "02128e7f52b8741d2bd144f273cad5e29da384636096087f567db8734a939934",
    "SpellReagents": "be6e987755f7097348eb072073ae3175b3d56016f43f90615a081d33d6affff6",
}
CREATE_ITEM_EFFECT = 24
MAX_LEVEL = 60


def read_table(directory, table, key):
    path = directory / (table + ".csv")
    if hashlib.sha256(path.read_bytes()).hexdigest() != SOURCE_HASHES[table]:
        raise ValueError(f"{path} does not match the verified {BUILD} export")
    result = defaultdict(list)
    with path.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            result[int(row[key])].append(row)
    return result


def only(values, source):
    if len(values) != 1:
        raise ValueError(f"Expected one value for {source}, found {values}")
    return next(iter(values))


class ClientSpells:
    def __init__(self, directory):
        self.names = read_table(directory, "SpellName", "ID")
        self.spells = read_table(directory, "Spell", "ID")
        self.levels = read_table(directory, "SpellLevels", "SpellID")
        self.abilities = read_table(directory, "SkillLineAbility", "Spell")
        self.reagents = read_table(directory, "SpellReagents", "SpellID")
        self.effects = read_table(directory, "SpellEffect", "SpellID")

    def select(self, class_mask, name_pattern):
        pattern = re.compile(name_pattern)
        spell_ids = [
            spell_id
            for spell_id, names in self.names.items()
            if pattern.fullmatch(only(names, spell_id)["Name_lang"])
            and any(
                int(ability["ClassMask"]) & class_mask and int(ability["AcquireMethod"]) in (0, 1)
                for ability in self.abilities.get(spell_id, ())
            )
            and any(
                int(level["DifficultyID"]) == 0 and 1 <= int(level["SpellLevel"]) <= MAX_LEVEL
                for level in self.levels.get(spell_id, ())
            )
        ]
        if not spell_ids:
            raise ValueError(f"No class spells matched {name_pattern}")
        return sorted(spell_ids)

    def rank(self, spell_id):
        subtext = only(self.spells[spell_id], spell_id)["NameSubtext_lang"]
        if subtext == "":
            return 1
        match = re.fullmatch(r"Rank (\d+)", subtext)
        if not match:
            raise ValueError(f"Unexpected rank text for spell {spell_id}: {subtext}")
        return int(match[1])

    def materials(self, spell_id):
        row = only(self.reagents[spell_id], f"SpellReagents {spell_id}")
        materials = []
        for index in range(8):
            item = int(row[f"Reagent_{index}"])
            count = int(row[f"ReagentCount_{index}"])
            if item > 0 and count > 0:
                materials.append(dict(itemID=item, count=count))
        if not materials:
            raise ValueError(f"Spell {spell_id} has no item reagents")
        return materials

    def reagent(self, spell_id):
        return only(self.materials(spell_id), f"reagent for spell {spell_id}")["itemID"]

    def recipe(self, spell_id):
        products = [
            effect for effect in self.effects[spell_id]
            if int(effect["DifficultyID"]) == 0 and int(effect["Effect"]) == CREATE_ITEM_EFFECT
        ]
        product = only(products, f"item creation for spell {spell_id}")
        count = Decimal(product["EffectBasePointsF"])
        item = int(product["EffectItemType"])
        if item <= 0 or count <= 0 or count != count.to_integral_value():
            raise ValueError(f"Invalid item output for spell {spell_id}")
        return dict(spellID=spell_id, itemID=item, outputCount=int(count), reagents=self.materials(spell_id))


def class_supplies(client):
    def direct(mask, pattern, purpose):
        spells = client.select(mask, pattern)
        item = only({client.reagent(spell_id) for spell_id in spells}, pattern)
        return dict(itemID=item, spells=spells, kind="direct", purpose=purpose)

    def ranked(mask, name, key):
        variants = [
            dict(itemID=client.reagent(spell_id), spells=[spell_id], rank=client.rank(spell_id))
            for spell_id in client.select(mask, name)
        ]
        variants.sort(key=lambda variant: variant["rank"], reverse=True)
        return dict(key=key, kind="direct", purpose=name, variants=variants)

    prayers = direct(16, r"Prayer of (?:Spirit|Shadow Protection)", "Group prayers")
    prayers["purposes"] = [
        dict(spells=client.select(16, f"Prayer of {name}"), label=name)
        for name in ("Spirit", "Shadow Protection")
    ]
    return {
        "MAGE": [
            direct(128, r"Portal: .+", "Group portals"),
            direct(128, r"Teleport: .+", "Teleport"),
            direct(128, "Arcane Brilliance", "Arcane Brilliance"),
        ],
        "PALADIN": [
            direct(2, r"Greater Blessing of .+", "Greater Blessings"),
            direct(2, "Divine Intervention", "Divine Intervention"),
        ],
        "SHAMAN": [direct(64, "Reincarnation", "Reincarnation")],
        "PRIEST": [ranked(16, "Prayer of Fortitude", "fortitude"), prayers],
        "DRUID": [
            ranked(1024, "Rebirth", "rebirth"),
            ranked(1024, "Gift of the Wild", "gift-of-the-wild"),
        ],
        "ROGUE": [direct(8, "Vanish", "Vanish")],
        "WARLOCK": [
            direct(256, "Inferno", "Inferno"),
            direct(256, "Ritual of Doom", "Ritual of Doom"),
        ],
    }


def poison_recipes(client):
    families = []
    for key, name, purpose in (
        ("instant", "Instant Poison", "Direct damage"),
        ("deadly", "Deadly Poison", "Damage over time"),
        ("crippling", "Crippling Poison", "Slows movement"),
        ("mind-numbing", "Mind-numbing Poison", "Slows spellcasting"),
        ("wound", "Wound Poison", "Reduces healing"),
        ("blinding-powder", "Blinding Powder", "Blind"),
    ):
        spells = client.select(8, name + r"(?: [IVX]+)?")
        spells.sort(key=client.rank)
        family = dict(key=key, purpose=purpose)
        if key == "blinding-powder":
            family["gatheredOnly"] = True
        family["ranks"] = [client.recipe(spell_id) for spell_id in spells]
        families.append(family)
    return families


def lua(value, depth=0):
    if isinstance(value, dict):
        entries = [f"{key} = {lua(item, depth + 1)}" for key, item in value.items()]
    elif isinstance(value, list):
        entries = [lua(item, depth + 1) for item in value]
    else:
        return json.dumps(value)
    joined = ", ".join(entries)
    if "\n" not in joined and len(joined) <= 116 - depth * 4:
        return "{ " + joined + " }"
    indent = "    " * depth
    return "{\n" + "".join(indent + "    " + entry + ",\n" for entry in entries) + indent + "}"


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=(
            "Download the tables in SOURCE_HASHES from "
            f"https://wago.tools/db2/<table>/csv?build={BUILD}. "
            "The generator verifies their SHA-256 hashes before reading them."
        ),
    )
    parser.add_argument("exports", type=Path, help=f"Directory with the {BUILD} CSV exports")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[2] / "Data.lua")
    parser.add_argument("--check", action="store_true", help="Compare against the checked-in catalog")
    args = parser.parse_args()
    client = ClientSpells(args.exports)
    data = (
        f"-- Generated from Blizzard's WoW Forever {BUILD} client tables.\n"
        "-- Source exports and checksums: .github/scripts/generate_data.py\n"
        "-- https://wago.tools/db2/SpellReagents/csv?build=" + BUILD + "\n\n"
        "local _, addon = ...\n\n"
        "addon.ClassSupplies = " + lua(class_supplies(client)) + "\n\n"
        "addon.Poisons = " + lua(poison_recipes(client)) + "\n"
    )
    if args.check:
        if args.output.read_text(encoding="utf-8") != data:
            parser.error(f"{args.output} differs from the generated catalog")
    else:
        args.output.write_text(data, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
