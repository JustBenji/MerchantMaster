"""Offline unit tests for tools/audit_catalog_blizzard.py (zero live network calls)."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile
import unittest

TOOLS_DIR = Path(__file__).resolve().parent
MM_ROOT = TOOLS_DIR.parent
if str(MM_ROOT) not in sys.path:
    sys.path.insert(0, str(MM_ROOT))

from tools import audit_catalog_blizzard as mod  # noqa: E402


SYNTHETIC_LUA = (
    "-- Header comment preserved\r\n"
    "local function I(id, name, sell, buy, vbuy, bop, mpFlag) end\r\n"
    "do (function()\r\n"
    '\tI(3371, "Empty Vial", 1, 4, 4, nil, true)\r\n'
    '\tI(8925, "Crystal Vial", 125, 450, 450, nil, true)\r\n'
    '\tI(13468, "Black Lotus", 1000, 4000, nil, nil, true)\r\n'
    '\tI(4390, "Iron Grenade", 250, 2000, nil, nil, true)\r\n'
    '\tI(2454, "Elixir of Lion\'s Strength", 20, 80, nil, nil, {n="Elixir of Minor Strength",s=20})\r\n'
    '\tI(13517, "Recipe: Alchemist\'s Stone", 0, 40000, nil, nil, true)\r\n'
    '\tI(5974, "Pattern: Guardian Cloak")\r\n'
    '\tI(6265, "Soul Shard")\r\n'
    '\tI(14046, "Runecloth Bag", 1000, 4000, nil, nil, true)\r\n'
    '\tI(14047, "Runecloth", 400, 1600, nil, nil, true)\r\n'
    '\tI(14341, "Rune Thread", 125, 500, 500, nil, true)\r\n'
    '\tI(7080, "Essence of Water", 400, 1600, nil, nil, true)\r\n'
    '\tI(7076, "Essence of Earth", 400, 1600, nil, nil, true)\r\n'
    '\tI(12808, "Essence of Undeath", 400, 1600, nil, nil, true)\r\n'
    '\tI(7931, "Mithril Coif", 800, 3200, nil, nil, true)\r\n'
    '\tI(13444, "Major Mana Potion", 500, 2000, nil, nil, true)\r\n'
    '\tI(3859, "Steel Bar", 100, 400, nil, nil, true)\r\n'
    '\tI(3575, "Iron Bar", 200, 800, nil, nil, true)\r\n'
    '\tI(3857, "Coal", nil, nil, 500)\r\n'
    "\tI(2665)\r\n"
    '\tI(2678, "Mild Spices", 2, 2, 10, nil, true)\r\n'
    "end)() end\r\n"
    "-- Recipes section\r\n"
    "do (function()\r\n"
    '\tR({idx=1,pk="blacksmithing",mpIdx=1,bySp=true,s=9961,i=7931,n="Mithril Coif",skill=230,source="trainer",acq="trainer",r={{3575,10}},tc=5000,y=240,g=250,gr=260,eff="Keep me"})\r\n'
    '\tR({idx=2,pk="alchemy",mpIdx=1,bySp=true,s=17580,i=13444,n="Major Mana Potion",skill=295,fav=120,rep=5,source="camp",acq="camp",r={{13468,1},{8925,1}},vA="Nina",vH="Durelle",vAll="Nina [A], Durelle [H]",y=300,g=310,gr=320,bis=true,bisC="Potion: Mana",eff="Restores mana"})\r\n'
    '\tR({idx=3,pk="alchemy",mpIdx=2,bySp=true,s=2329,i=2454,n="Elixir of Lion\'s Strength",skill=1,source="trainer",acq="trainer",r={{3371,1}},y=15,g=25,gr=35})\r\n'
    '\tR({idx=4,pk="engineering",mpIdx=1,bySp=true,s=3962,i=4390,n="Iron Grenade",skill=175,c=3,source="trainer",acq="trainer",r={{3575,1}},y=175,g=195,gr=215,bis=false})\r\n'
    '\tR({idx=5,pk="tailoring",mpIdx=1,bySp=true,s=18445,i=14046,n="Runecloth Bag",skill=260,source="vendor",acq="vendor",r={{14047,5},{14341,1}},vA="Qia",vH="Qia",vAll="Qia",y=275,g=290,gr=305})\r\n'
    '\tR({idx=6,pk="alchemy",mpIdx=3,bySp=true,s=17561,i=7080,n="Transmute: Earth to Water",skill=275,source="vendor",acq="vendor",r={{7076,1}},cd=86400,y=275,g=290,gr=305})\r\n'
    '\tR({idx=7,pk="alchemy",mpIdx=4,bySp=true,s=17560,i=7080,n="Transmute: Undeath to Water",skill=275,source="world",acq="ah",r={{12808,1}},cd=86400,y=275,g=290,gr=305})\r\n'
    '\tR({idx=8,pk="enchanting",mpIdx=1,bySp=true,s=13898,mpI=0,n="Enchant Weapon - Fiery Weapon",skill=265,ench=true,bop=true,source="world",acq="ah",r={{7076,4}},rod=376,y=265,g=285,gr=305})\r\n'
    '\tR({idx=9,pk="mining",mpIdx=1,bySp=true,s=3569,i=3859,n="Smelt Steel",skill=165,source="trainer",acq="trainer",r={{3575,1},{3857,1}},y=165,g=175,gr=185})\r\n'
    '\tR({idx=10,pk="poisons",mpIdx=1,bySp=true,s=8681,i=6947,n="Instant Poison",skill=100,source="trainer",acq="trainer",r={{3371,1}},y=100,g=120,gr=140})\r\n'
    '\tR({mpOnly=true,pk="mining",mpIdx=8,bop=true,c=0,ench=true,g=162,gr=175,i=0,n="Mine Iron Deposits (World Veins)",r={},req=125,s=9000186,src="gather",y=150,bySp=true})\r\n'
    "end)() end\r\n"
)


def _build_synthetic_cache() -> dict:
    return {
        "schema_version": 1,
        "region": "eu",
        "namespace": "static-forever-eu",
        "updated_at": "2026-11-22T00:00:00+00:00",
        "professions": [
            {"id": 171, "key": "alchemy", "name": "Alchemy", "skill_tiers": []},
            {"id": 164, "key": "blacksmithing", "name": "Blacksmithing", "skill_tiers": []},
            {"id": 202, "key": "engineering", "name": "Engineering", "skill_tiers": []},
            {"id": 197, "key": "tailoring", "name": "Tailoring", "skill_tiers": []},
            {"id": 333, "key": "enchanting", "name": "Enchanting", "skill_tiers": []},
            {"id": 186, "key": "mining", "name": "Mining", "skill_tiers": []},
        ],
        "skill_tiers": {},
        "recipes": {
            # CRITICAL: API recipe id 9961 is Major Mana Potion (Alchemy), which numerically
            # collides with Blacksmithing spellID 9961 (Mithril Coif)! Must join by
            # (alchemy, crafted_item 13444), NEVER to Blacksmithing spell 9961!
            "9961": {
                "id": 9961,
                "name": "Major Mana Potion",
                "prof": "alchemy",
                "prof_id": 171,
                "prof_name": "Alchemy",
                "tier_id": 2937,
                "category": "Potions",
                "crafted_item": {"id": 13444, "name": "Major Mana Potion"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [
                    {"id": 13468, "name": "Black Lotus", "quantity": 1},
                    {"id": 8925, "name": "Crystal Vial", "quantity": 1},
                ],
                "description": "",
            },
            # Same-profession spellID collision guard: API id=3962 (matches Iron Grenade spellID 3962!)
            # is a brand-new unrelated Engineering recipe with different crafted_item and name.
            "3962": {
                "id": 3962,
                "name": "Forever Camping Turret",
                "prof": "engineering",
                "prof_id": 202,
                "prof_name": "Engineering",
                "tier_id": 2941,
                "category": "Camping",
                "crafted_item": {"id": 299999, "name": "Forever Camping Turret"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [{"id": 3575, "name": "Iron Bar", "quantity": 4}],
                "description": "",
            },
            # Real Iron Grenade recipe with range yield 1..5 (midpoint 3 == local c=3 -> NO yield drift!)
            "2456": {
                "id": 2456,
                "name": "Iron Grenade",
                "prof": "engineering",
                "prof_id": 202,
                "prof_name": "Engineering",
                "tier_id": 2941,
                "category": "Explosives",
                "crafted_item": {"id": 4390, "name": "Iron Grenade"},
                "yield": {"value": 3, "min": 1, "max": 5, "is_range": True},
                "reagents": [{"id": 3575, "name": "Iron Bar", "quantity": 1}],
                "description": "",
            },
            # Confirmed Forever rename matched by (alchemy, crafted_item=2454)
            "1111": {
                "id": 1111,
                "name": "Elixir of Minor Strength",
                "prof": "alchemy",
                "prof_id": 171,
                "prof_name": "Alchemy",
                "tier_id": 2937,
                "category": "Elixirs",
                "crafted_item": {"id": 2454, "name": "Elixir of Minor Strength"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [{"id": 3371, "name": "Empty Vial", "quantity": 1}],
                "description": "",
            },
            # Runecloth Bag with updated reagent qty (safe) + known items
            "10401": {
                "id": 10401,
                "name": "Runecloth Bag",
                "prof": "tailoring",
                "prof_id": 197,
                "prof_name": "Tailoring",
                "tier_id": 2948,
                "category": "Bags",
                "crafted_item": {"id": 14046, "name": "Runecloth Bag"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [
                    {"id": 14047, "name": "Runecloth", "quantity": 6},
                    {"id": 14341, "name": "Rune Thread", "quantity": 2},
                ],
                "description": "",
            },
            # Multi-recipe same crafted_item (7080 Essence of Water): must disambiguate cleanly!
            "5001": {
                "id": 5001,
                "name": "Transmute: Earth to Water",
                "prof": "alchemy",
                "prof_id": 171,
                "prof_name": "Alchemy",
                "tier_id": 2937,
                "category": "Transmutation",
                "crafted_item": {"id": 7080, "name": "Essence of Water"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [{"id": 7076, "name": "Essence of Earth", "quantity": 1}],
                "description": "",
            },
            "5002": {
                "id": 5002,
                "name": "Transmute: Undeath to Water",
                "prof": "alchemy",
                "prof_id": 171,
                "prof_name": "Alchemy",
                "tier_id": 2937,
                "category": "Transmutation",
                "crafted_item": {"id": 7080, "name": "Essence of Water"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [{"id": 12808, "name": "Essence of Undeath", "quantity": 1}],
                "description": "",
            },
            # Enchanting fallback join by (prof, normalized_name) with no crafted_item.
            # Blizzard API maps spell EffectBasePoints (e.g. 65) into crafted_quantity
            # on enchants; must NEVER be flagged as a numMade yield drift!
            "11394": {
                "id": 11394,
                "name": "Enchant Weapon: Fiery Weapon",
                "prof": "enchanting",
                "prof_id": 333,
                "prof_name": "Enchanting",
                "tier_id": 2940,
                "category": "Weapon",
                "crafted_item": None,
                "yield": {"value": 65, "min": 65, "max": 65, "is_range": False},
                "reagents": [{"id": 7076, "name": "Essence of Earth", "quantity": 4}],
                "description": "Permanently enchants a melee weapon.",
            },
            # Exact yield drift (Smelt Steel: local implicit c=1 vs API value=2)
            "2001": {
                "id": 2001,
                "name": "Smelt Steel",
                "prof": "mining",
                "prof_id": 186,
                "prof_name": "Mining",
                "tier_id": 2946,
                "category": "Smelting",
                "crafted_item": {"id": 3859, "name": "Steel Bar"},
                "yield": {"value": 2, "min": 2, "max": 2, "is_range": False},
                "reagents": [
                    {"id": 3575, "name": "Iron Bar", "quantity": 1},
                    {"id": 3857, "name": "Coal", "quantity": 1},
                ],
                "description": "",
            },
            # New Forever recipe in Alchemy
            "54999": {
                "id": 54999,
                "name": "Draught of Predatory Senses",
                "prof": "alchemy",
                "prof_id": 171,
                "prof_name": "Alchemy",
                "tier_id": 2937,
                "category": "Camping",
                "crafted_item": {"id": 250327, "name": "Draught of Predatory Senses"},
                "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                "reagents": [{"id": 8925, "name": "Crystal Vial", "quantity": 1}],
                "description": "",
            },
        },
        "items": {
            # Empty Vial: 20c / 5 = 4c -> exact match with local vendorPrice=4 (no drift!)
            "3371": {
                "id": 3371,
                "name": "Empty Vial",
                "sell_price": 1,
                "purchase_price": 20,
                "purchase_quantity": 5,
                "unit_purchase_price": 4,
                "bop": False,
                "binding": None,
            },
            # Crystal Vial: 2500c / 5 = 500c vs local vendorPrice=450 -> vendor_reagent drift!
            "8925": {
                "id": 8925,
                "name": "Crystal Vial",
                "sell_price": 125,
                "purchase_price": 2500,
                "purchase_quantity": 5,
                "unit_purchase_price": 500,
                "bop": False,
                "binding": None,
            },
            # Black Lotus: NOT a vendor reagent (local vendorPrice=None) -> purchase_price=4000 must NOT trigger vendor drift!
            "13468": {
                "id": 13468,
                "name": "Black Lotus",
                "sell_price": 1000,
                "purchase_price": 4000,
                "purchase_quantity": 1,
                "unit_purchase_price": 4000,
                "bop": False,
                "binding": None,
            },
            # Iron Grenade: Forever nerfed sell_price 125c vs local 250c -> sell_price drift!
            "4390": {
                "id": 4390,
                "name": "Iron Grenade",
                "sell_price": 125,
                "purchase_price": 2000,
                "purchase_quantity": 1,
                "unit_purchase_price": 2000,
                "bop": False,
                "binding": None,
            },
            # Elixir of Minor Strength: sell_price changed 20 -> 35 (must also update mpFlag.s=35!)
            "2454": {
                "id": 2454,
                "name": "Elixir of Minor Strength",
                "sell_price": 35,
                "purchase_price": 140,
                "purchase_quantity": 1,
                "unit_purchase_price": 140,
                "bop": False,
                "binding": None,
            },
            # Recipe: Alchemist's Stone: BoP drift (local bop=False, API ON_ACQUIRE=True)
            "13517": {
                "id": 13517,
                "name": "Recipe: Alchemist's Stone",
                "sell_price": 0,
                "purchase_price": 40000,
                "purchase_quantity": 1,
                "unit_purchase_price": 40000,
                "bop": True,
                "binding": "ON_ACQUIRE",
            },
            # Pattern: Guardian Cloak: 2-arg I() backfill sell_price nil -> 150c
            "5974": {
                "id": 5974,
                "name": "Pattern: Guardian Cloak",
                "sell_price": 150,
                "purchase_price": 600,
                "purchase_quantity": 1,
                "unit_purchase_price": 600,
                "bop": False,
                "binding": None,
            },
            # Soul Shard: 2-arg I() with sell_price=0 (NOT sell drift!) and ON_ACQUIRE -> bop drift!
            "6265": {
                "id": 6265,
                "name": "Soul Shard",
                "sell_price": 0,
                "purchase_price": 0,
                "purchase_quantity": 1,
                "unit_purchase_price": 0,
                "bop": True,
                "binding": "ON_ACQUIRE",
            },
            # Coal: sell=nil vs API sell_price=125 -> sell backfill; purchase_price=500 -> exact match
            "3857": {
                "id": 3857,
                "name": "Coal",
                "sell_price": 125,
                "purchase_price": 500,
                "purchase_quantity": 1,
                "unit_purchase_price": 500,
                "bop": False,
                "binding": None,
            },
            # 1-arg I(2665) item with sell_price=0 and bop=False -> no drift
            "2665": {
                "id": 2665,
                "name": "Stormshroud Armor",
                "sell_price": 0,
                "purchase_price": 0,
                "purchase_quantity": 1,
                "unit_purchase_price": 0,
                "bop": False,
                "binding": None,
            },
            # Mild Spices: 10c / 5 = 2c/ea vs local vbuy=10 -> vendor_reagent drift to 2c
            "2678": {
                "id": 2678,
                "name": "Mild Spices",
                "sell_price": 2,
                "purchase_price": 10,
                "purchase_quantity": 5,
                "unit_purchase_price": 2,
                "bop": False,
                "binding": None,
            },
        },
    }


class TestAuditCatalogBlizzard(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self._tmp.name)
        self.catalog_path = self.tmp_dir / "Data_Recipes.lua"
        self.catalog_path.write_bytes(SYNTHETIC_LUA.encode("utf-8"))

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_parse_items_and_recipes(self) -> None:
        cat = mod.parse_data_recipes(self.catalog_path)
        self.assertEqual(cat.line_ending, "\r\n")
        self.assertEqual(len(cat.items), 21)
        self.assertEqual(len(cat.recipes), 11)
        self.assertEqual(cat.items[2665].arg_count, 1)
        self.assertEqual(cat.items[2665].name, "")
        self.assertEqual(cat.items[2678].vendor_price, 10)

        self.assertEqual(cat.items[3371].vendor_price, 4)
        self.assertIsNone(cat.items[13468].vendor_price)
        self.assertEqual(cat.items[2454].mp_name, "Elixir of Minor Strength")
        self.assertEqual(cat.items[2454].mp_sell, 20)
        self.assertIsNone(cat.items[5974].sell)
        self.assertEqual(cat.items[5974].arg_count, 2)
        self.assertEqual(cat.items[3857].vendor_price, 500)

        iron_grenade = next(r for r in cat.recipes if r.name == "Iron Grenade")
        self.assertEqual(iron_grenade.num_made, 3)
        self.assertEqual(iron_grenade.reagents, [(3575, 1)])
        self.assertIn("r", iron_grenade.value_spans)
        self.assertIn("c", iron_grenade.value_spans)

    def test_recipe_join_and_spell_id_collision_rejection(self) -> None:
        cat = mod.parse_data_recipes(self.catalog_path)
        cache = _build_synthetic_cache()
        api_recipes = {int(k): v for k, v in cache["recipes"].items()}

        matches, unmatched_local, unmatched_api = mod.match_recipes(cat.recipes, api_recipes)
        match_by_local_name = {cat.recipes[m["local_idx"]].name: m for m in matches}

        # Major Mana Potion MUST match API 9961 via (alchemy, 13444)
        self.assertIn("Major Mana Potion", match_by_local_name)
        self.assertEqual(match_by_local_name["Major Mana Potion"]["api_recipe_id"], 9961)
        self.assertEqual(match_by_local_name["Major Mana Potion"]["match_method"], "prof_output_item_id")

        # Blacksmithing Mithril Coif (spellID=9961) MUST NOT match API 9961!
        self.assertNotIn("Mithril Coif", match_by_local_name)

        # Engineering Iron Grenade (spellID=3962) MUST match API 2456, NEVER API 3962!
        self.assertEqual(match_by_local_name["Iron Grenade"]["api_recipe_id"], 2456)
        self.assertIn(3962, unmatched_api)

        # Confirmed Forever rename matched via outputItemID=2454
        self.assertEqual(match_by_local_name["Elixir of Lion's Strength"]["api_recipe_id"], 1111)
        self.assertTrue(match_by_local_name["Elixir of Lion's Strength"]["name_changed"])

        # Same-output Transmutes disambiguated by name
        self.assertEqual(match_by_local_name["Transmute: Earth to Water"]["api_recipe_id"], 5001)
        self.assertEqual(match_by_local_name["Transmute: Undeath to Water"]["api_recipe_id"], 5002)

        # Enchanting joined via normalized name (" - " vs ": ")
        self.assertEqual(match_by_local_name["Enchant Weapon - Fiery Weapon"]["api_recipe_id"], 11394)
        self.assertEqual(
            match_by_local_name["Enchant Weapon - Fiery Weapon"]["match_method"],
            "prof_normalized_name",
        )

        # Unmatched local includes Mithril Coif, Instant Poison, and World Veins
        unmatched_names = {cat.recipes[i].name for i in unmatched_local}
        self.assertEqual(
            unmatched_names,
            {"Mithril Coif", "Instant Poison", "Mine Iron Deposits (World Veins)"},
        )

    def test_drift_detection_all_seven_categories(self) -> None:
        cat = mod.parse_data_recipes(self.catalog_path)
        report = mod.compute_drift_report(cat, _build_synthetic_cache())
        drifts = report["summary"]["drifts"]

        # 1. Item sell_price drifts: 4390 (250->125), 2454 (20->35), 5974 (nil->150), 3857 (nil->125)
        #    Note: 6265 (nil vs API 0) must NOT be flagged!
        sell_ids = {row["item_id"]: row for row in report["item_sell_price_drifts"]}
        self.assertEqual(set(sell_ids.keys()), {4390, 2454, 5974, 3857})
        self.assertEqual(sell_ids[4390]["api_sell"], 125)
        self.assertEqual(sell_ids[4390]["kind"], "changed")
        self.assertEqual(sell_ids[5974]["kind"], "backfill")

        # 2. Vendor reagent unit buy drift: Crystal Vial (2500/5=500 vs 450) & Mild Spices (10/5=2 vs 10).
        #    Empty Vial (20/5=4 == 4) has NO drift; Black Lotus (non-vendor) ignored!
        self.assertEqual(drifts["vendor_reagent_buy_total"], 2)
        vrows = {row["item_id"]: row for row in report["vendor_reagent_buy_drifts"]}
        self.assertEqual(set(vrows.keys()), {8925, 2678})
        self.assertEqual(vrows[8925]["api_unit_buy"], 500)
        self.assertTrue(vrows[8925]["safe_to_apply"])
        self.assertEqual(vrows[2678]["api_unit_buy"], 2)
        self.assertTrue(vrows[2678]["safe_to_apply"])

        # 3. Item BoP drifts: 13517 & 6265
        bop_ids = {row["item_id"] for row in report["item_bop_drifts"]}
        self.assertEqual(bop_ids, {13517, 6265})

        # 4. Matched recipe reagents drift: Runecloth Bag (14047x5->6, 14341x1->2)
        self.assertEqual(drifts["recipe_reagent_total"], 1)
        rrow = report["recipe_reagent_drifts"][0]
        self.assertEqual(rrow["local_name"], "Runecloth Bag")
        self.assertTrue(rrow["safe_to_apply"])
        self.assertEqual(rrow["api_reagents"], [[14047, 6], [14341, 2]])

        # 5. Matched recipe numMade drift: Smelt Steel (1 -> 2); Iron Grenade (3 in 1..5 mid=3) OK!
        self.assertEqual(drifts["recipe_yield_total"], 1)
        yrow = report["recipe_yield_drifts"][0]
        self.assertEqual(yrow["local_name"], "Smelt Steel")
        self.assertEqual(yrow["api_yield"], 2)
        self.assertTrue(yrow["safe_to_apply"])

        # 6. Renamed / local-only separation
        ren = report["renamed_and_local_only"]
        self.assertEqual(len(ren["matched_renamed"]), 1)
        self.assertEqual(ren["matched_renamed"][0]["api_name"], "Elixir of Minor Strength")
        self.assertEqual(len(ren["non_api_local_only"]), 2)  # Poisons + World Veins
        self.assertEqual(len(ren["unmatched_api_prof_local_only"]), 1)  # Mithril Coif

        # 7. New Forever recipes staged by prof with Lua skeletons
        self.assertEqual(drifts["new_forever_recipes_total"], 2)
        self.assertEqual(
            drifts["new_forever_recipes_by_prof"],
            {"alchemy": 1, "engineering": 1},
        )
        new_alch = report["new_forever_recipes"]["alchemy"][0]
        self.assertEqual(new_alch["api_recipe_id"], 54999)
        self.assertIn("Draught of Predatory Senses", new_alch["lua_skeleton"])
        self.assertIn("s=TODO_SPELL_ID", new_alch["lua_skeleton"])

        # Markdown report renders cleanly without errors
        md = mod.render_markdown_report(report)
        self.assertIn("Blizzard WoW: Forever Static Catalog Drift Report", md)
        self.assertIn("Runecloth Bag", md)
        self.assertIn("Draught of Predatory Senses", md)

    def test_apply_safe_dry_run_and_apply_round_trip(self) -> None:
        cat = mod.parse_data_recipes(self.catalog_path)
        report = mod.compute_drift_report(cat, _build_synthetic_cache())
        orig_bytes = self.catalog_path.read_bytes()

        # Dry run must NOT modify Data_Recipes.lua
        dry = mod.apply_safe_patches(
            self.catalog_path, report, include_recipes=True, apply_write=False
        )
        self.assertFalse(dry["wrote_file"])
        self.assertEqual(dry["bad_glyphs"], 0)
        self.assertEqual(self.catalog_path.read_bytes(), orig_bytes)
        self.assertEqual(dry["counts"]["item_lines_changed"], 8)
        self.assertEqual(dry["counts"]["recipe_lines_changed"], 2)
        self.assertTrue(len(dry["diff_lines"]) > 0)

        # Apply mode writes verified changes while preserving ALL hand-curated fields
        applied = mod.apply_safe_patches(
            self.catalog_path, report, include_recipes=True, apply_write=True
        )
        self.assertTrue(applied["wrote_file"])
        self.assertEqual(applied["bad_glyphs"], 0)

        new_bytes = self.catalog_path.read_bytes()
        self.assertFalse(new_bytes.startswith(b"\xef\xbb\xbf"))
        new_text = new_bytes.decode("utf-8")
        self.assertIn("\r\n", new_text)
        self.assertIn("-- Header comment preserved", new_text)

        # Re-parse patched catalog and verify exact updated semantics + preserved curation
        reparsed = mod.parse_data_recipes(self.catalog_path)
        self.assertEqual(len(reparsed.items), len(cat.items))
        self.assertEqual(len(reparsed.recipes), len(cat.recipes))

        self.assertEqual(reparsed.items[4390].sell, 125)
        self.assertEqual(reparsed.items[8925].vendor_price, 500)
        self.assertEqual(reparsed.items[8925].buy, 500)
        self.assertEqual(reparsed.items[2454].sell, 35)
        self.assertEqual(reparsed.items[2454].mp_sell, 35)
        self.assertEqual(reparsed.items[2454].mp_name, "Elixir of Minor Strength")
        self.assertTrue(reparsed.items[13517].bop)
        self.assertTrue(reparsed.items[6265].bop)
        self.assertIsNone(reparsed.items[6265].sell)
        self.assertEqual(reparsed.items[5974].sell, 150)
        self.assertEqual(reparsed.items[3857].sell, 125)
        self.assertEqual(reparsed.items[3857].vendor_price, 500)
        self.assertEqual(reparsed.items[2678].vendor_price, 2)
        self.assertEqual(reparsed.items[2678].buy, 2)
        self.assertEqual(reparsed.items[2665].raw_line, "\tI(2665)")

        bag = next(r for r in reparsed.recipes if r.name == "Runecloth Bag")
        self.assertEqual(bag.reagents, [(14047, 6), (14341, 2)])
        self.assertEqual(bag.spell_id, 18445)
        self.assertEqual(bag.fields["vA"], "Qia")
        self.assertEqual(bag.fields["y"], 275)

        steel = next(r for r in reparsed.recipes if r.name == "Smelt Steel")
        self.assertEqual(steel.num_made, 2)
        self.assertEqual(steel.spell_id, 3569)
        self.assertEqual(steel.fields["gr"], 185)

        # Hand-curated Major Mana Potion completely untouched
        mmp = next(r for r in reparsed.recipes if r.name == "Major Mana Potion")
        self.assertEqual(mmp.fields["fav"], 120)
        self.assertEqual(mmp.fields["vAll"], "Nina [A], Durelle [H]")
        self.assertEqual(mmp.fields["bisC"], "Potion: Mana")

        # Re-auditing patched catalog yields ZERO item/reagent/yield drifts!
        report2 = mod.compute_drift_report(reparsed, _build_synthetic_cache())
        d2 = report2["summary"]["drifts"]
        self.assertEqual(d2["item_sell_price_total"], 0)
        self.assertEqual(d2["vendor_reagent_buy_total"], 0)
        self.assertEqual(d2["item_bop_total"], 0)
        self.assertEqual(d2["recipe_reagent_total"], 0)
        self.assertEqual(d2["recipe_yield_total"], 0)

    def test_static_fetcher_ignores_dnt_caches_and_never_leaks_secrets(self) -> None:
        secret_id = "FAKE_CLIENT_ID_NEVER_LEAK"
        secret_pw = "FAKE_CLIENT_SECRET_NEVER_LEAK"
        secret_tok = "FAKE_BEARER_TOKEN_NEVER_LEAK"
        calls = []

        def fake_transport(method, url, headers, body, timeout):
            calls.append((method, url))
            if url == "https://oauth.battle.net/token":
                payload = {"access_token": secret_tok, "expires_in": 3600}
                return 200, {}, json.dumps(payload).encode("utf-8")
            if "/data/wow/profession/index" in url:
                payload = {
                    "professions": [
                        {"id": 2933, "name": "Test Profession [DNT]"},
                        {"id": 186, "name": "Mining"},
                    ]
                }
                return 200, {}, json.dumps(payload).encode("utf-8")
            if "/data/wow/profession/186/skill-tier/2946" in url:
                payload = {
                    "id": 2946,
                    "name": "Classic Mining",
                    "categories": [
                        {"name": "Smelting", "recipes": [{"id": 2001, "name": "Smelt Steel"}]}
                    ],
                }
                return 200, {}, json.dumps(payload).encode("utf-8")
            if "/data/wow/profession/186?" in url:
                payload = {"id": 186, "name": "Mining", "skill_tiers": [{"id": 2946, "name": "Classic Mining"}]}
                return 200, {}, json.dumps(payload).encode("utf-8")
            if "/data/wow/recipe/2001" in url:
                payload = {
                    "id": 2001,
                    "name": "Smelt Steel",
                    "crafted_item": {"id": 3859, "name": "Steel Bar"},
                    "crafted_quantity": {"value": 1},
                    "reagents": [
                        {"reagent": {"id": 3575, "name": "Iron Bar"}, "quantity": 1},
                        {"reagent": {"id": 3857, "name": "Coal"}, "quantity": 1},
                    ],
                }
                return 200, {}, json.dumps(payload).encode("utf-8")
            if "/data/wow/item/3859" in url:
                payload = {
                    "id": 3859,
                    "name": "Steel Bar",
                    "sell_price": 100,
                    "purchase_price": 400,
                    "purchase_quantity": 1,
                }
                return 200, {}, json.dumps(payload).encode("utf-8")
            return 404, {}, b""

        # Minimal catalog with 1 item + 1 recipe
        mini_cat_path = self.tmp_dir / "Mini.lua"
        mini_cat_path.write_text(
            '\tI(3859, "Steel Bar", 100, 400, nil, nil, true)\n'
            '\tR({idx=1,pk="mining",s=3569,i=3859,n="Smelt Steel",skill=165,r={{3575,1},{3857,1}}})\n',
            encoding="utf-8",
        )
        mini_cat = mod.parse_data_recipes(mini_cat_path)
        cache_path = self.tmp_dir / "static_catalog_cache.json"

        client = mod.BlizzardForeverStaticClient(
            client_id=secret_id,
            client_secret=secret_pw,
            region="eu",
            transport=fake_transport,
            rate_per_sec=25.0,
        )
        cache, stats = mod.fetch_static_catalog(
            client=client,
            local_catalog=mini_cat,
            cache_path=cache_path,
            region="eu",
            refresh=False,
            workers=2,
        )

        # Ignored 2933 Test Profession [DNT]
        self.assertEqual([p["id"] for p in cache["professions"]], [186])
        self.assertEqual(stats["recipes_fetched_live"], 1)
        self.assertIn("2001", cache["recipes"])
        # Fetched 3859 + matched-recipe reagents 3575 & 3857 (404 cached cleanly)
        self.assertIn("3859", cache["items"])
        self.assertTrue(cache["items"]["3575"].get("_not_found"))

        # Cache file MUST NEVER contain secrets or tokens!
        cache_text = cache_path.read_text(encoding="utf-8")
        self.assertNotIn(secret_id, cache_text)
        self.assertNotIn(secret_pw, cache_text)
        self.assertNotIn(secret_tok, cache_text)

        # Second run with cache hits makes ZERO new HTTP requests!
        prev_reqs = client.http_requests
        _, stats2 = mod.fetch_static_catalog(
            client=client,
            local_catalog=mini_cat,
            cache_path=cache_path,
            region="eu",
            refresh=False,
            workers=2,
        )
        self.assertEqual(client.http_requests, prev_reqs)
        self.assertEqual(stats2["recipes_from_cache"], 1)
        self.assertEqual(stats2["items_from_cache"], 3)

    def test_tier1_fractional_vendor_reagent_half_up_and_held_unsafe(self) -> None:
        # Helper direct check: 300/200 = 1.5c -> half-up 2c, is_exact_div=False
        unit, exact = mod.compute_vendor_unit_buy(300, 200)
        self.assertEqual(unit, 2)
        self.assertFalse(exact)
        unit_exact, exact2 = mod.compute_vendor_unit_buy(10, 5)
        self.assertEqual(unit_exact, 2)
        self.assertTrue(exact2)

        # Case A: local 3030 Razor Arrow already at 2c -> half-up 2c matches, 0 drift (never floors to 1c!)
        lua_ok = (
            '\tI(3030, "Razor Arrow", 0, 2, 2, nil, true)\n'
            '\tI(3031, "Stub Arrow", 0, 5, 5, nil, true)\n'
        )
        cat_path = self.tmp_dir / "Ammo.lua"
        cat_path.write_text(lua_ok, encoding="utf-8")
        cat = mod.parse_data_recipes(cat_path)
        cache = {
            "schema_version": 1,
            "region": "eu",
            "namespace": "static-forever-eu",
            "professions": [],
            "recipes": {},
            "items": {
                "3030": mod.compact_api_item(
                    {"id": 3030, "name": "Razor Arrow", "sell_price": 0, "purchase_price": 300, "purchase_quantity": 200}
                ),
                "3031": mod.compact_api_item(
                    {"id": 3031, "name": "Stub Arrow", "sell_price": 0, "purchase_price": 300, "purchase_quantity": 200}
                ),
            },
        }
        self.assertEqual(cache["items"]["3030"]["unit_purchase_price"], 2)
        self.assertFalse(cache["items"]["3030"]["unit_purchase_exact"])

        report = mod.compute_drift_report(cat, cache)
        vrows = {r["item_id"]: r for r in report["vendor_reagent_buy_drifts"]}
        # 3030 already at 2c has NO drift (not floored to 1c!)
        self.assertNotIn(3030, vrows)
        # 3031 at 5c vs 300/200 -> half-up 2c, held safe_to_apply=False
        self.assertIn(3031, vrows)
        self.assertEqual(vrows[3031]["api_unit_buy"], 2)
        self.assertEqual(vrows[3031]["api_unit_buy_exact"], 1.5)
        self.assertFalse(vrows[3031]["is_exact_div"])
        self.assertFalse(vrows[3031]["safe_to_apply"])
        self.assertEqual(vrows[3031]["reason"], "fractional_purchase_price_per_unit")

        # apply-safe MUST skip 3031 and leave file untouched
        res = mod.apply_safe_patches(cat_path, report, include_recipes=True, apply_write=True)
        self.assertFalse(res["wrote_file"])
        self.assertEqual(res["counts"]["vendor_reagent_patched"], 0)
        self.assertEqual(res["counts"]["vendor_reagent_skipped_unsafe"], 1)

    def test_tier2_reagent_removal_blocked_and_range_yield_enchant_blocked(self) -> None:
        lua_src = (
            '\tI(4339, "Bolt of Mageweave", 200, 800, nil, nil, true)\n'
            '\tI(8343, "Heavy Silken Thread", 500, 2000, 2000, nil, true)\n'
            '\tI(2324, "Bleach", 6, 25, 25, nil, true)\n'
            '\tI(10040, "White Wedding Dress", 800, 3200, nil, nil, true)\n'
            '\tI(4360, "Rough Copper Bomb", 10, 40, nil, nil, true)\n'
            '\tI(2840, "Copper Bar", 10, 40, nil, nil, true)\n'
            '\tR({idx=1,pk="tailoring",mpIdx=1,bySp=true,s=12091,i=10040,n="White Wedding Dress",skill=250,source="world",acq="ah",r={{4339,5},{8343,3},{2324,1}},y=250,g=270,gr=290})\n'
            '\tR({idx=2,pk="engineering",mpIdx=1,bySp=true,s=3931,i=4360,n="Coarse Dynamite",skill=75,c=2,source="trainer",acq="trainer",r={{2840,1}},y=75,g=95,gr=115})\n'
            '\tR({idx=3,pk="enchanting",mpIdx=1,bySp=true,s=20025,mpI=0,n="Enchant Weapon - Spellblasting",skill=300,ench=true,bop=true,source="world",acq="ah",r={{2840,2}},y=300,g=310,gr=320})\n'
        )
        cat_path = self.tmp_dir / "Tier2.lua"
        cat_path.write_text(lua_src, encoding="utf-8")
        cat = mod.parse_data_recipes(cat_path)
        cache = {
            "schema_version": 1,
            "region": "eu",
            "namespace": "static-forever-eu",
            "professions": [
                {"id": 197, "key": "tailoring", "name": "Tailoring", "skill_tiers": []},
                {"id": 202, "key": "engineering", "name": "Engineering", "skill_tiers": []},
                {"id": 333, "key": "enchanting", "name": "Enchanting", "skill_tiers": []},
            ],
            "recipes": {
                # API omission bug: drops 2324 Bleach from White Wedding Dress
                "6622": {
                    "id": 6622,
                    "name": "White Wedding Dress",
                    "prof": "tailoring",
                    "category": "Dresses",
                    "crafted_item": {"id": 10040, "name": "White Wedding Dress"},
                    "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                    "reagents": [
                        {"id": 4339, "name": "Bolt of Mageweave", "quantity": 5},
                        {"id": 8343, "name": "Heavy Silken Thread", "quantity": 3},
                    ],
                },
                # API range bug: 1..4 (mid 2.5) on fixed-yield 2 engineering bomb
                "2427": {
                    "id": 2427,
                    "name": "Coarse Dynamite",
                    "prof": "engineering",
                    "category": "Explosives",
                    "crafted_item": {"id": 4360, "name": "Rough Copper Bomb"},
                    "yield": {"value": 2.5, "min": 1, "max": 4, "is_range": True},
                    "reagents": [{"id": 2840, "name": "Copper Bar", "quantity": 1}],
                },
                # API EffectBasePoints leak: crafted_item=None, yield=65
                "51804": {
                    "id": 51804,
                    "name": "Enchant Weapon: Spellblasting",
                    "prof": "enchanting",
                    "category": "Weapon",
                    "crafted_item": None,
                    "yield": {"value": 65, "min": 65, "max": 65, "is_range": False},
                    "reagents": [{"id": 2840, "name": "Copper Bar", "quantity": 2}],
                },
            },
            "items": {},
        }

        report = mod.compute_drift_report(cat, cache)
        # 1. White Wedding Dress reagent removal MUST be blocked safe_to_apply=False
        self.assertEqual(len(report["recipe_reagent_drifts"]), 1)
        dress = report["recipe_reagent_drifts"][0]
        self.assertEqual(dress["api_recipe_id"], 6622)
        self.assertFalse(dress["safe_to_apply"])
        self.assertEqual(dress["reason"], "reagent_removal_requires_second_source")
        self.assertEqual([r["id"] for r in dress["removed"]], [2324])

        # 2. Coarse Dynamite is_range yield MUST be blocked safe_to_apply=False;
        #    Enchanting EffectBasePoints=65 MUST be excluded entirely!
        self.assertEqual(len(report["recipe_yield_drifts"]), 1)
        bomb = report["recipe_yield_drifts"][0]
        self.assertEqual(bomb["api_recipe_id"], 2427)
        self.assertTrue(bomb["is_range"])
        self.assertFalse(bomb["safe_to_apply"])
        self.assertEqual(bomb["reason"], "range_yield_requires_second_source")

        # 3. apply-safe --apply --include-recipes MUST NOT alter White Wedding Dress or Coarse Dynamite
        res = mod.apply_safe_patches(cat_path, report, include_recipes=True, apply_write=True)
        self.assertFalse(res["wrote_file"])
        self.assertEqual(res["counts"]["recipe_reagents_skipped_unsafe"], 1)
        self.assertEqual(res["counts"]["recipe_yield_skipped_unsafe"], 1)
        self.assertIn("{2324,1}", cat_path.read_text(encoding="utf-8"))

    def test_tier2_new_recipe_classification_excludes_sod_deprecated_and_unseen(self) -> None:
        cat_path = self.tmp_dir / "Empty.lua"
        cat_path.write_text('\tI(2840, "Copper Bar", 10, 40, nil, nil, true)\n', encoding="utf-8")
        cat = mod.parse_data_recipes(cat_path)
        cache = {
            "schema_version": 1,
            "region": "eu",
            "namespace": "static-forever-eu",
            "professions": [
                {"id": 197, "key": "tailoring", "name": "Tailoring", "skill_tiers": []},
                {"id": 129, "key": "firstaid", "name": "First Aid", "skill_tiers": []},
                {"id": 185, "key": "cooking", "name": "Cooking", "skill_tiers": []},
            ],
            "recipes": {
                # 1. SoD category -> excluded
                "50001": {
                    "id": 50001,
                    "name": "SoD Leftover Cloak",
                    "prof": "tailoring",
                    "category": "SEASON OF DISCOVERY",
                    "crafted_item": {"id": 233966, "name": "SoD Leftover Cloak"},
                    "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                    "reagents": [{"id": 2840, "name": "Copper Bar", "quantity": 1}],
                },
                # 2. DEPRECATED reagent -> excluded
                "50002": {
                    "id": 50002,
                    "name": "Crystal Infused Bandage",
                    "prof": "firstaid",
                    "category": "Bandages",
                    "crafted_item": {"id": 23684, "name": "Crystal Infused Bandage"},
                    "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                    "reagents": [{"id": 23567, "name": "DEPRECATED ITEM", "quantity": 1}],
                },
                # 3. Unseen / dead stub (no AH, no PP seen, no Forever scroll) -> excluded
                "50003": {
                    "id": 50003,
                    "name": "Cleansing Stew",
                    "prof": "cooking",
                    "category": "Everyday Meals",
                    "crafted_item": {"id": 252683, "name": "Cleansing Stew"},
                    "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                    "reagents": [{"id": 2840, "name": "Copper Bar", "quantity": 1}],
                },
                # 4. Live Forever craft (in AH + PP seen) -> live_forever
                "57042": {
                    "id": 57042,
                    "name": "Loom",
                    "prof": "tailoring",
                    "category": "Camping",
                    "crafted_item": {"id": 279959, "name": "Loom"},
                    "yield": {"value": 1, "min": 1, "max": 1, "is_range": False},
                    "reagents": [{"id": 2840, "name": "Copper Bar", "quantity": 1}],
                },
            },
            "items": {},
        }
        evidence = {
            "has_external_evidence": True,
            "sources_loaded": ["profplanner", "oneforall", "snapshots_db"],
            "pp_by_ability": {
                50003: {"spell_id": 1255241, "seen": False},
                57042: {"spell_id": 1263080, "seen": True},
            },
            "ofa_by_spell": {
                1255241: {"spell_id": 1255241, "recipe_item_id": None, "output_item_id": 252683},
                1263080: {"spell_id": 1263080, "recipe_item_id": 273124, "output_item_id": 279959},
            },
            "ah_item_ids": {279959},
        }
        report = mod.compute_drift_report(cat, cache, liveness_evidence=evidence)
        d = report["summary"]["drifts"]
        self.assertEqual(d["new_forever_recipes_total"], 4)
        self.assertEqual(d["new_forever_live_candidates_total"], 1)
        self.assertEqual(d["new_forever_excluded_total"], 3)
        self.assertEqual(
            d["new_forever_excluded_by_reason"],
            {"deprecated_reagent": 1, "sod_category": 1, "unseen_dead": 1},
        )
        by_id = {
            e["api_recipe_id"]: e
            for entries in report["new_forever_recipes"].values()
            for e in entries
        }
        self.assertEqual(by_id[50001]["classification"], "excluded")
        self.assertEqual(by_id[50001]["classification_reason"], "sod_category")
        self.assertEqual(by_id[50002]["classification"], "excluded")
        self.assertEqual(by_id[50002]["classification_reason"], "deprecated_reagent")
        self.assertEqual(by_id[50003]["classification"], "excluded")
        self.assertEqual(by_id[50003]["classification_reason"], "unseen_dead")
        self.assertEqual(by_id[57042]["classification"], "live_forever")
        self.assertEqual(by_id[57042]["classification_reason"], "verified_live_forever")


if __name__ == "__main__":
    unittest.main()
