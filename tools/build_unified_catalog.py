"""Verify or rebuild MerchantMaster's single unified catalog (Data_Recipes.lua + Data_CratesAndWrits.lua)
from the legacy 3-file catalog, and prove 100% runtime table parity in Lua 5.1.

Run from repo root or tools/:
  python tools/build_unified_catalog.py          # read-only parity check against baseline a8a5f47
  python tools/build_unified_catalog.py --write  # overwrite Data_CratesAndWrits.lua & Data_Recipes.lua from baseline
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
MM = TOOLS.parent
LUA = __import__("os").environ.get("LUA_BIN") or __import__("shutil").which("lua5.1") or __import__("shutil").which("lua51") or __import__("shutil").which("lua") or next((str(p) for p in sorted(Path.home().glob(".vscode/extensions/actboy168.lua-debug-*/runtime/**/lua51/lua.exe"))), "lua5.1")
BASELINE_COMMIT = "a8a5f47"

DUMP_LUA = r"""
local json_escape_map = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}
local function jstr(s)
  local out = {}
  for i = 1, #s do
    local ch = s:sub(i, i)
    local esc = json_escape_map[ch]
    if esc then
      out[#out + 1] = esc
    else
      local b = ch:byte()
      if b < 32 then
        out[#out + 1] = string.format('\\u%04x', b)
      else
        out[#out + 1] = ch
      end
    end
  end
  return '"' .. table.concat(out) .. '"'
end

local function is_seq_array(t)
  local n = #t
  local count = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k > n or math.floor(k) ~= k then
      return false
    end
    count = count + 1
  end
  return count == n
end

local function jenc(v)
  local tv = type(v)
  if v == nil then return 'null'
  elseif tv == 'boolean' then return v and 'true' or 'false'
  elseif tv == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then error('non-finite number') end
    return tostring(v)
  elseif tv == 'string' then return jstr(v)
  elseif tv == 'table' then
    if is_seq_array(v) then
      local out = {}
      for i = 1, #v do out[i] = jenc(v[i]) end
      return '[' .. table.concat(out, ',') .. ']'
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local out = {}
      for _, k in ipairs(keys) do
        out[#out + 1] = jstr(tostring(k)) .. ':' .. jenc(v[k])
      end
      return '{' .. table.concat(out, ',') .. '}'
    end
  else
    error('unsupported type: ' .. tv)
  end
end

local dir = ...
local ns = {}
for _, fname in ipairs({'Data_CratesAndWrits.lua', 'Data_Recipes.lua', 'Data_RecipeMeta.lua'}) do
  assert(loadfile(dir .. '/' .. fname))('MerchantMaster', ns)
end

-- Identify CAMP_RECIPES_BY_REP indices
local camp_rep_idx = {}
for rep, arr in pairs(ns.CAMP_RECIPES_BY_REP) do
  local list = {}
  for i, rec in ipairs(arr) do
    assert(ns.RECIPES[rec.idx] == rec, 'camp bucket identity mismatch')
    list[i] = rec.idx
  end
  camp_rep_idx[tostring(rep)] = list
end

-- Identify MP.RECIPES_BY_SPELL winners
local mp_ref_pos = {}
for pk, arr in pairs(ns.MP.RECIPES) do
  for k, rec in ipairs(arr) do
    mp_ref_pos[rec] = { pk = pk, idx = k }
  end
end
local by_spell_pos = {}
for sp, rec in pairs(ns.MP.RECIPES_BY_SPELL) do
  local pos = assert(mp_ref_pos[rec], 'by_spell missing from MP.RECIPES')
  by_spell_pos[tostring(sp)] = pos
end

local payload = {
  ALL_CATALOG_IDS = ns.ALL_CATALOG_IDS,
  ITEM_NAMES_BY_ID = ns.ITEM_NAMES_BY_ID,
  ITEM_IDS_BY_NAME = ns.ITEM_IDS_BY_NAME,
  VENDOR_REAGENTS = ns.VENDOR_REAGENTS,
  ITEM_VENDOR_SELL = ns.ITEM_VENDOR_SELL,
  ITEM_BOP = ns.ITEM_BOP,
  MP_ITEM_INFO = ns.MP.ITEM_INFO,
  RECIPES = ns.RECIPES,
  CAMP_RECIPES_BY_REP = camp_rep_idx,
  WRITS = ns.WRITS,
  WRIT_ACQ_BY_WRIT_ID = ns.WRIT_ACQ_BY_WRIT_ID,
  MP_PROF_ORDER = ns.MP.PROF_ORDER,
  MP_RECIPES = ns.MP.RECIPES,
  MP_RECIPES_BY_SPELL = by_spell_pos,
}
io.write(jenc(payload))
"""

PARITY_LUA = r"""
local oldDir, newDir = ...
local function loadCatalog(dir, files)
  _G.MerchantProfessorNS = nil
  local ns = {}
  for _, fname in ipairs(files) do
    assert(loadfile(dir .. '/' .. fname))('MerchantMaster', ns)
  end
  local globalMP = _G.MerchantProfessorNS
  _G.MerchantProfessorNS = nil
  return ns, globalMP
end

local oldNS, oldGlobalMP = loadCatalog(oldDir, {'Data_CratesAndWrits.lua', 'Data_Recipes.lua', 'Data_RecipeMeta.lua'})
local newNS, newGlobalMP = loadCatalog(newDir, {'Data_CratesAndWrits.lua', 'Data_Recipes.lua'})

assert(oldGlobalMP == oldNS.MP, 'old MerchantProfessorNS == oldNS.MP')
assert(newGlobalMP == newNS.MP, 'new MerchantProfessorNS == newNS.MP')

local diffs = 0
local function report(path, msg)
  diffs = diffs + 1
  if diffs <= 40 then
    io.stderr:write(string.format('DIFF %s: %s\n', path, msg))
  end
end

local function deepEq(path, a, b, skip)
  if type(a) ~= type(b) then
    report(path, string.format('type %s ~= %s (%s vs %s)', type(a), type(b), tostring(a), tostring(b)))
    return
  end
  if type(a) ~= 'table' then
    if a ~= b then
      report(path, string.format('%s ~= %s', tostring(a), tostring(b)))
    end
    return
  end
  for k, va in pairs(a) do
    if not (skip and skip[k]) then
      deepEq(path .. '[' .. tostring(k) .. ']', va, b[k], nil)
    end
  end
  for k, vb in pairs(b) do
    if not (skip and skip[k]) and a[k] == nil then
      report(path .. '[' .. tostring(k) .. ']', 'extra key in new: ' .. tostring(vb))
    end
  end
end

for _, key in ipairs({
  'ALL_CATALOG_IDS',
  'ITEM_NAMES_BY_ID',
  'ITEM_IDS_BY_NAME',
  'VENDOR_REAGENTS',
  'ITEM_VENDOR_SELL',
  'ITEM_BOP',
  'WRIT_ACQ_BY_WRIT_ID',
  'WRITS',
  'RECIPES',
  'CRATES',
  'GATHER_ITEMS',
  'WRIT_ZONE_HINTS',
  'SPECIAL_REP_UNLOCKS',
  'PROFESSIONS',
}) do
  deepEq('ns.' .. key, oldNS[key], newNS[key])
end

-- Check CAMP_RECIPES_BY_REP counts and reference identity
for rep, arr in pairs(oldNS.CAMP_RECIPES_BY_REP) do
  local narr = newNS.CAMP_RECIPES_BY_REP[rep]
  if type(narr) ~= 'table' or #arr ~= #narr then
    report('CAMP_RECIPES_BY_REP[' .. tostring(rep) .. ']', string.format('len %s ~= %s', #arr, type(narr) == 'table' and #narr or -1))
  else
    for i = 1, #arr do
      if arr[i].idx ~= narr[i].idx or newNS.RECIPES[narr[i].idx] ~= narr[i] then
        report('CAMP_RECIPES_BY_REP[' .. tostring(rep) .. '][' .. i .. ']', 'idx/ref mismatch')
      end
    end
  end
end
for rep in pairs(newNS.CAMP_RECIPES_BY_REP) do
  if oldNS.CAMP_RECIPES_BY_REP[rep] == nil then
    report('CAMP_RECIPES_BY_REP[' .. tostring(rep) .. ']', 'extra rep bucket')
  end
end

-- Check MP subtables
for _, key in ipairs({'LEGACY_TRAITS', 'PROF_ORDER', 'PROFESSIONS', 'PROF_SPECS', 'ENCHANTING_RODS', 'ITEM_INFO', 'RECIPES'}) do
  deepEq('MP.' .. key, oldNS.MP[key], newNS.MP[key])
end

-- Check MP.RECIPES_BY_SPELL exact identity
local oldRefPos, newRefPos = {}, {}
for pk, arr in pairs(oldNS.MP.RECIPES) do
  for k, rec in ipairs(arr) do oldRefPos[rec] = pk .. ':' .. k end
end
for pk, arr in pairs(newNS.MP.RECIPES) do
  for k, rec in ipairs(arr) do newRefPos[rec] = pk .. ':' .. k end
end
for sp, rec in pairs(oldNS.MP.RECIPES_BY_SPELL) do
  local nrec = newNS.MP.RECIPES_BY_SPELL[sp]
  if not nrec then
    report('MP.RECIPES_BY_SPELL[' .. tostring(sp) .. ']', 'missing in new')
  elseif oldRefPos[rec] ~= newRefPos[nrec] then
    report('MP.RECIPES_BY_SPELL[' .. tostring(sp) .. ']', tostring(oldRefPos[rec]) .. ' ~= ' .. tostring(newRefPos[nrec]))
  end
end
for sp in pairs(newNS.MP.RECIPES_BY_SPELL) do
  if not oldNS.MP.RECIPES_BY_SPELL[sp] then
    report('MP.RECIPES_BY_SPELL[' .. tostring(sp) .. ']', 'extra spell in new')
  end
end

-- Check unified ns.ITEMS presence
assert(type(newNS.ITEMS) == 'table', 'ns.ITEMS must exist')
for id in pairs(newNS.ALL_CATALOG_IDS) do
  assert(type(newNS.ITEMS[id]) == 'table' and newNS.ITEMS[id].id == id, 'missing ns.ITEMS row for ' .. tostring(id))
end

if diffs > 0 then
  io.stderr:write('TOTAL_DIFFS=' .. diffs .. '\n')
  os.exit(1)
end
print('PARITY_OK')
"""


def lua_val(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v.is_integer():
            return str(int(v))
        return repr(v)
    if isinstance(v, str):
        escaped = (
            v.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
        )
        return f'"{escaped}"'
    if isinstance(v, list):
        return "{" + ",".join(lua_val(x) for x in v) + "}"
    if isinstance(v, dict):
        items = []
        for k, val in v.items():
            items.append(f"{k}={lua_val(val)}")
        return "{" + ",".join(items) + "}"
    raise TypeError(type(v))


def reagents_lua(rg_list) -> str:
    return "{" + ",".join(f"{{{int(r[0])},{int(r[1])}}}" for r in rg_list) + "}"


def split_vendor_by_faction(vn: str):
    if not isinstance(vn, str) or vn == "":
        return None, None, None
    a_parts, h_parts = [], []
    for part in vn.split(","):
        p = part.strip()
        if p != "":
            if "[A]" in p:
                a_parts.append(p.replace("[A]", "").strip())
            elif "[H]" in p:
                h_parts.append(p.replace("[H]", "").strip())
            else:
                a_parts.append(p)
                h_parts.append(p)
    v_a = ", ".join(a_parts) if a_parts else ""
    v_h = ", ".join(h_parts) if h_parts else ""
    return v_a, v_h, vn


def export_baseline_files(tmp_dir: Path, ref: str) -> Path:
    for fn in ("Data_CratesAndWrits.lua", "Data_Recipes.lua", "Data_RecipeMeta.lua"):
        res = subprocess.run(
            ["git", "show", f"{ref}:{fn}"],
            cwd=str(MM),
            capture_output=True,
            check=True,
        )
        (tmp_dir / fn).write_bytes(res.stdout)
    return tmp_dir


def dump_ground_truth(src_dir: Path) -> dict:
    res = subprocess.run(
        [LUA, "-", src_dir.as_posix()],
        input=DUMP_LUA,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    )
    return json.loads(res.stdout)


def rebuild_crates_and_writs(old_dir: Path, truth: dict, write: bool = False) -> tuple[int, int]:
    orig_lines = (old_dir / "Data_CratesAndWrits.lua").read_text(encoding="utf-8").splitlines(keepends=True)
    idx_writs = next(i for i, l in enumerate(orig_lines) if l.startswith("ns.WRITS = {}"))
    idx_hints = next(i for i, l in enumerate(orig_lines) if l.startswith("-- Inferred turn-in zones"))

    # Map recipes by spellID (only unambiguous unique spell match or exact first match)
    rec_by_spell = {}
    for rec in truth["RECIPES"]:
        sp = rec.get("spellID")
        if sp:
            rec_by_spell.setdefault(sp, []).append(rec)

    writ_acq = truth["WRIT_ACQ_BY_WRIT_ID"]
    out = list(orig_lines[:idx_writs])
    out.append("ns.WRITS = {}\n")
    out.append("ns.WRIT_ACQ_BY_WRIT_ID = {}\n")
    out.append(
        "local function addWrit(itemID, questID, shortName, reqID, reqName, qty, rep, prof, skill, spellID, numMade, reagents, npc, zone, x, y, acqType, recID, recName, vA, vH, vAll, recVendorPrice)\n"
        '\tlocal fullName = "Craftsman\'s Writ: " .. shortName\n'
        "\tlocal pouchMeta = ns.WRIT_POUCH_BY_REP[rep]\n"
        "\tns.RegisterItem(itemID, fullName)\n"
        "\tns.RegisterItem(reqID, reqName)\n"
        "\tif reagents then\n"
        "\t\tfor _, r in ipairs(reagents) do\n"
        "\t\t\tns.ALL_CATALOG_IDS[r[1]] = true\n"
        "\t\tend\n"
        "\tend\n"
        "\tlocal entry = {\n"
        "\t\titemID = itemID,\n"
        "\t\tquestID = questID,\n"
        "\t\tname = fullName,\n"
        "\t\tshortName = shortName,\n"
        "\t\trequiredItemID = reqID,\n"
        "\t\trequiredItemName = reqName,\n"
        "\t\tqty = qty,\n"
        "\t\trep = rep,\n"
        "\t\ttier = pouchMeta and pouchMeta.tier or nil,\n"
        "\t\tpouchItemID = pouchMeta and pouchMeta.id or nil,\n"
        "\t\tpouchCopper = pouchMeta and pouchMeta.avgMoneyCopper or nil,\n"
        "\t\tprof = prof,\n"
        "\t\tskill = skill,\n"
        "\t\tspellID = spellID,\n"
        "\t\tnumMade = numMade,\n"
        "\t\treagents = reagents,\n"
        '\t\tnpc = npc ~= "" and npc or nil,\n'
        '\t\tzone = zone ~= "" and zone or nil,\n'
        "\t\tx = x > 0 and x or nil,\n"
        "\t\ty = y > 0 and y or nil,\n"
        "\t}\n"
        "\tif acqType ~= nil then\n"
        "\t\tentry.acqType = acqType\n"
        "\t\tif recID and recID > 0 then entry.recipeItemID = recID end\n"
        '\t\tif recName and recName ~= "" then entry.recipeName = recName end\n'
        "\t\tentry.vendorA = vA or \"\"\n"
        "\t\tentry.vendorH = vH or \"\"\n"
        "\t\tentry.vendorAll = vAll or \"\"\n"
        "\t\tif recVendorPrice and recVendorPrice > 0 then entry.recipeVendorPrice = recVendorPrice end\n"
        "\t\tns.WRIT_ACQ_BY_WRIT_ID[itemID] = { acqType, recID or 0, recName or \"\", vA or \"\", vH or \"\", vAll or \"\", recVendorPrice or 0 }\n"
        "\tend\n"
        "\tns.WRITS[#ns.WRITS + 1] = entry\n"
        "end\n\n"
    )

    deduped_reagents = 0
    kept_reagents = 0
    comment_prefix = "-- Alan Sneeks (257282) QDB spawn has corrupt Y=21424.0; verified Forever Hillsbrad/Alterac pin 30.4, 61.2.\n"
    for w in truth["WRITS"]:
        if w["itemID"] == 264047:
            out.append(comment_prefix)
        sp = w.get("spellID") or 0
        matches = rec_by_spell.get(sp, [])
        can_dedup = (
            len(matches) == 1
            and matches[0].get("numMade") == w.get("numMade")
            and matches[0].get("reagents") == w.get("reagents")
        )
        if can_dedup:
            deduped_reagents += 1
            nm_arg, rg_arg = "nil", "nil"
        else:
            kept_reagents += 1
            nm_arg = lua_val(w.get("numMade"))
            rg_arg = reagents_lua(w["reagents"])

        m = writ_acq.get(str(w["itemID"]))
        acq_args = ""
        if m is not None:
            acq_args = ", " + ", ".join([
                lua_val(m[0]),
                lua_val(m[1]),
                lua_val(m[2]),
                lua_val(m[3]),
                lua_val(m[4]),
                lua_val(m[5]),
                lua_val(m[6]),
            ])
        args = [
            lua_val(w["itemID"]),
            lua_val(w["questID"]),
            lua_val(w["shortName"]),
            lua_val(w["requiredItemID"]),
            lua_val(w["requiredItemName"]),
            lua_val(w["qty"]),
            lua_val(w["rep"]),
            lua_val(w["prof"]),
            lua_val(w["skill"]),
            lua_val(w["spellID"]),
            nm_arg,
            rg_arg,
            lua_val(w.get("npc") or ""),
            lua_val(w.get("zone") or ""),
            lua_val(w.get("x") or 0),
            lua_val(w.get("y") or 0),
        ]
        out.append(f"addWrit({', '.join(args)}{acq_args})\n")

    out.append("\n\n")
    out.extend(orig_lines[idx_hints:])
    if write:
        (MM / "Data_CratesAndWrits.lua").write_text("".join(out), encoding="utf-8", newline="\n")
    return deduped_reagents, kept_reagents


def extract_mp_header(old_dir: Path) -> str:
    meta_lines = (old_dir / "Data_RecipeMeta.lua").read_text(encoding="utf-8").splitlines(keepends=True)
    start = next(i for i, l in enumerate(meta_lines) if l.startswith("local MP = ns.MP or {}"))
    end = next(i for i, l in enumerate(meta_lines) if l.startswith("MP.EXTRA_VENDOR_REAGENTS"))
    return "".join(meta_lines[start:end])


def build_unified_recipes(old_dir: Path, truth: dict, write: bool = False) -> dict:
    mp_header = extract_mp_header(old_dir)

    all_ids = sorted(int(k) for k in truth["ALL_CATALOG_IDS"])
    names_by_id = {int(k): v for k, v in truth["ITEM_NAMES_BY_ID"].items()}
    ids_by_name = truth["ITEM_IDS_BY_NAME"]
    v_reag = {int(k): v for k, v in truth["VENDOR_REAGENTS"].items()}
    v_sell = {int(k): v for k, v in truth["ITEM_VENDOR_SELL"].items()}
    bop_map = {int(k): v for k, v in truth["ITEM_BOP"].items()}
    mp_info = {int(k): v for k, v in truth["MP_ITEM_INFO"].items()}

    # Verify any MP_ITEM_INFO differences against canonical item columns
    item_lines = []
    for item_id in all_ids:
        name = names_by_id.get(item_id)
        sell = v_sell.get(item_id)
        vr = v_reag.get(item_id)
        bop = True if bop_map.get(item_id) else False
        mp = mp_info.get(item_id)
        if mp is not None:
            # Verify whether mp agrees with name/sell/bop
            mp_name = mp.get("name")
            mp_sell = mp.get("sell")
            mp_buy = mp.get("buy")
            mp_bop = mp.get("bop")
            buy_arg = mp_buy if mp_buy is not None else -1
            assert mp_bop is bop, f"bop mismatch {item_id}: {bop} vs {mp_bop}"
            assert mp_sell is None or sell == mp_sell, f"sell mismatch {item_id}: {sell} vs {mp_sell}"
            mp_flag = None
            if mp_name != name or mp_sell != sell:
                mp_flag = {"n": mp_name if mp_name != name else None, "s": mp_sell}
            args = [lua_val(item_id), lua_val(name), lua_val(sell), lua_val(buy_arg), lua_val(vr), "true" if bop else "nil"]
            if mp_flag:
                args.append(lua_val(mp_flag))
            else:
                args.append("true")  # explicitly marks inclusion in MP.ITEM_INFO even if buy == nil
        else:
            args = [lua_val(item_id), lua_val(name), lua_val(sell), "nil", lua_val(vr), "true" if bop else "nil"]
        # Trim trailing nils
        while args and args[-1] == "nil":
            args.pop()
        item_lines.append(f"\tI({', '.join(args)})\n")

    # Compute exact ITEM_IDS_BY_NAME overrides needed after Data_CratesAndWrits + Data_Recipes item registration
    # Read Data_CratesAndWrits runtime ITEM_IDS_BY_NAME via Lua!
    cw_probe = """
local dir = ...
local ns = {}
assert(loadfile(dir .. '/Data_CratesAndWrits.lua'))('MerchantMaster', ns)
for k, v in pairs(ns.ITEM_IDS_BY_NAME) do print(tostring(k) .. '\\t' .. tostring(v)) end
"""
    cw_out = subprocess.run([LUA, "-", MM.as_posix()], input=cw_probe, capture_output=True, text=True, encoding="utf-8", check=True)
    sim_by_name = {}
    for line in cw_out.stdout.splitlines():
        n, _, i_str = line.partition("\t")
        sim_by_name[n] = int(i_str)
    for item_id in all_ids:
        name = names_by_id.get(item_id)
        if name and name != "" and name not in sim_by_name:
            sim_by_name[name] = item_id
    id_by_name_overrides = [
        (name, want_id)
        for name, want_id in sorted(ids_by_name.items())
        if sim_by_name.get(name) != want_id
    ]

    # Pair ns.RECIPES with MP.RECIPES
    mp_entries = []
    mp_by_key = {}
    for pk in truth["MP_PROF_ORDER"]:
        for idx1, m in enumerate(truth["MP_RECIPES"].get(pk, []), start=1):
            rec_obj = {"pk": pk, "mpIdx": idx1, "m": m, "used": False}
            mp_entries.append(rec_obj)
            sp = m.get("s")
            ri = m.get("ri")
            if sp:
                mp_by_key.setdefault(("s", pk, sp), []).append(rec_obj)
            if ri:
                mp_by_key.setdefault(("ri", pk, ri), []).append(rec_obj)

    by_spell_win = truth["MP_RECIPES_BY_SPELL"]
    camp_order = {}
    for rep_str, idx_list in truth["CAMP_RECIPES_BY_REP"].items():
        for pos, ridx in enumerate(idx_list):
            camp_order[ridx] = (int(rep_str), pos)

    unified_rows = []
    matched_count = 0
    mm_only_count = 0
    mp_only_count = 0

    for rec in truth["RECIPES"]:
        pk = rec["prof"]
        sp = rec.get("spellID")
        ri = rec.get("recipeItemID")
        cand = None
        for key in (("s", pk, sp), ("ri", pk, ri)):
            if key[2]:
                for obj in mp_by_key.get(key, []):
                    if not obj["used"]:
                        cand = obj
                        break
            if cand is not None:
                break
        if cand is not None:
            cand["used"] = True
            matched_count += 1
        else:
            mm_only_count += 1
        unified_rows.append((rec, cand))

    for obj in mp_entries:
        if not obj["used"]:
            mp_only_count += 1
            unified_rows.append((None, obj))

    # Serialize each unified row cleanly
    recipe_lines = []
    for rec, mp_obj in unified_rows:
        t = {}
        if rec is not None and mp_obj is None:
            t["mmOnly"] = True
            t["idx"] = rec["idx"]
            if rec.get("spellID"): t["s"] = rec["spellID"]
            if rec.get("recipeItemID"): t["ri"] = rec["recipeItemID"]
            if rec.get("outputItemID"): t["i"] = rec["outputItemID"]
            t["n"] = rec["name"]
            if rec.get("recipeName") and rec["recipeName"] != rec["name"]: t["rn"] = rec["recipeName"]
            t["prof"] = rec["prof"]
            t["skill"] = rec["skill"]
            if rec.get("rep", 0) != 0: t["rep"] = rec["rep"]
            if rec.get("favorCost", 0) != 0: t["fav"] = rec["favorCost"]
            t["source"] = rec["source"]
            if rec.get("acqType") is not None: t["acq"] = rec["acqType"]
            if rec.get("numMade", 1) != 1: t["c"] = rec["numMade"]
            default_sell = (not rec.get("isEnchant", False)) and (not (rec.get("outputItemID") and bop_map.get(rec["outputItemID"]))) and (rec.get("outputItemID") is not None)
            if rec.get("sellable") != default_sell: t["sell"] = rec["sellable"]
            if rec.get("isEnchant"): t["ench"] = True
            if rec.get("reagents"): t["r"] = rec["reagents"]
            if rec.get("trainerCost") is not None: t["tc"] = rec["trainerCost"]
            if rec.get("recipeVendorPrice") is not None: t["rbuy"] = rec["recipeVendorPrice"]
            if rec.get("vendorA") is not None: t["vA"] = rec["vendorA"]
            if rec.get("vendorH") is not None: t["vH"] = rec["vendorH"]
            if rec.get("vendorAll") is not None: t["vAll"] = rec["vendorAll"]
            if rec.get("reqCharLevel") is not None: t["rlv"] = rec["reqCharLevel"]
            if rec.get("effectText") is not None: t["eff"] = rec["effectText"]
            if rec.get("isBiS") is not None: t["bis"] = rec["isBiS"]
            if rec.get("bisClass") is not None: t["bisC"] = rec["bisClass"]
            if rec.get("bisVal") is not None: t["bisV"] = rec["bisVal"]
            if rec.get("bisRank") is not None: t["bisR"] = rec["bisRank"]
            if rec.get("bisTotal") is not None: t["bisT"] = rec["bisTotal"]
            if rec.get("bisBestName") is not None: t["bisBN"] = rec["bisBestName"]
            if rec.get("bisBestVal") is not None: t["bisBV"] = rec["bisBestVal"]
        elif rec is None and mp_obj is not None:
            m = mp_obj["m"]
            t["mpOnly"] = True
            t["pk"] = mp_obj["pk"]
            t["mpIdx"] = mp_obj["mpIdx"]
            for k, val in m.items():
                if k == "prof" and val == mp_obj["pk"]:
                    continue
                t[k] = val
            win = by_spell_win.get(str(m.get("s")))
            if win and win["pk"] == mp_obj["pk"] and win["idx"] == mp_obj["mpIdx"]:
                t["bySp"] = True
        else:
            m = mp_obj["m"]
            pk = mp_obj["pk"]
            mp_idx = mp_obj["mpIdx"]
            # Paired row!
            t["idx"] = rec["idx"]
            t["pk"] = pk
            t["mpIdx"] = mp_idx
            win = by_spell_win.get(str(m.get("s")))
            if win and win["pk"] == pk and win["idx"] == mp_idx:
                t["bySp"] = True
            # Core identity
            if rec.get("spellID") == m.get("s"):
                if rec.get("spellID") is not None: t["s"] = rec["spellID"]
            else:
                if rec.get("spellID") is not None: t["s"] = rec["spellID"]
                t["mpS"] = m.get("s")
            if rec.get("outputItemID") == m.get("i"):
                if rec.get("outputItemID") is not None: t["i"] = rec["outputItemID"]
            else:
                if rec.get("outputItemID") is not None: t["i"] = rec["outputItemID"]
                if "i" in m: t["mpI"] = m.get("i")
            if rec.get("recipeItemID") == m.get("ri"):
                if rec.get("recipeItemID") is not None: t["ri"] = rec["recipeItemID"]
            else:
                if rec.get("recipeItemID") is not None: t["ri"] = rec["recipeItemID"]
                t["mpRi"] = m.get("ri") if "ri" in m else False
            t["n"] = rec["name"]
            if m.get("n") != rec["name"]: t["mpN"] = m.get("n")
            if rec.get("recipeName") != rec["name"]: t["rn"] = rec["recipeName"]
            if m.get("rn") is not None and m.get("rn") != (t.get("rn") or rec["name"]):
                t["mpRn"] = m.get("rn")
            elif "rn" in t and "rn" not in m:
                t["mpRn"] = False
            if rec["prof"] != pk:
                t["prof"] = rec["prof"]
            if rec["skill"] == m.get("req"):
                t["skill"] = rec["skill"]
            else:
                t["skill"] = rec["skill"]
                t["mpReq"] = m.get("req")
            if rec.get("numMade", 1) == m.get("c", 1):
                if rec.get("numMade", 1) != 1: t["c"] = rec["numMade"]
            else:
                t["c"] = rec.get("numMade", 1)
                t["mpC"] = m.get("c") if "c" in m else False
            if rec.get("rep", 0) != 0: t["rep"] = rec["rep"]
            if "rep" in m and m.get("rep") != t.get("rep", 0):
                t["mpRep"] = m.get("rep")
            elif "rep" in t and "rep" not in m:
                t["mpRep"] = False
            if rec.get("favorCost", 0) != 0: t["fav"] = rec["favorCost"]
            if "fav" in m and m.get("fav") != t.get("fav", 0):
                t["mpFav"] = m.get("fav")
            elif "fav" in t and "fav" not in m:
                t["mpFav"] = False
            t["source"] = rec["source"]
            if rec.get("acqType") is not None: t["acq"] = rec["acqType"]
            if m.get("src") != rec.get("acqType"):
                t["mpSrc"] = m.get("src")
            default_sell = (not rec.get("isEnchant", False)) and (not (rec.get("outputItemID") and bop_map.get(rec["outputItemID"]))) and (rec.get("outputItemID") is not None)
            if rec.get("sellable") != default_sell: t["sell"] = rec["sellable"]
            if rec.get("isEnchant"): t["ench"] = True
            if "ench" in m and m.get("ench") != rec.get("isEnchant"):
                t["mpEnch"] = m.get("ench")
            elif not "ench" in m and rec.get("isEnchant"):
                t["mpEnch"] = False
            if "bop" in m: t["bop"] = m.get("bop")
            if rec.get("reagents"): t["r"] = rec["reagents"]
            if m.get("r") != rec.get("reagents"):
                t["mpR"] = m.get("r") if "r" in m else False
            if rec.get("trainerCost") is not None: t["tc"] = rec["trainerCost"]
            if m.get("tc") != rec.get("trainerCost"):
                t["mpTc"] = m.get("tc") if "tc" in m else False
            if rec.get("recipeVendorPrice") is not None: t["rbuy"] = rec["recipeVendorPrice"]
            if m.get("rbuy") != rec.get("recipeVendorPrice"):
                t["mpRbuy"] = m.get("rbuy") if "rbuy" in m else False
            # Vendors
            sv_a, sv_h, sv_all = split_vendor_by_faction(m.get("vn"))
            if rec.get("vendorA") is not None: t["vA"] = rec["vendorA"]
            if rec.get("vendorH") is not None: t["vH"] = rec["vendorH"]
            if rec.get("vendorAll") is not None: t["vAll"] = rec["vendorAll"]
            if m.get("vn") is not None and m.get("vn") != rec.get("vendorAll"):
                t["vn"] = m.get("vn")
            elif m.get("vn") is None and rec.get("vendorAll") is not None:
                t["vn"] = False
            # Char level & progression columns
            if rec.get("reqCharLevel") == m.get("rlv"):
                if rec.get("reqCharLevel") is not None: t["rlv"] = rec["reqCharLevel"]
            else:
                if rec.get("reqCharLevel") is not None: t["rlv"] = rec["reqCharLevel"]
                t["mpRlv"] = m.get("rlv") if "rlv" in m else False
            for mk in ("y", "g", "gr", "elv", "fac", "pre", "spec", "rod", "cd"):
                if mk in m: t[mk] = m[mk]
            handled_m = {"s", "i", "ri", "n", "rn", "prof", "req", "c", "rep", "fav", "src", "ench", "bop", "r", "tc", "rbuy", "vn", "rlv", "y", "g", "gr", "elv", "fac", "pre", "spec", "rod", "cd"}
            extra_m = sorted(set(m.keys()) - handled_m)
            assert not extra_m, f"Unhandled MP keys: {extra_m}"
            if m.get("prof") != pk:
                t["mpProf"] = m.get("prof")
            # Forever effect & BiS
            if rec.get("effectText") is not None: t["eff"] = rec["effectText"]
            if rec.get("isBiS") is not None: t["bis"] = rec["isBiS"]
            if rec.get("bisClass") is not None: t["bisC"] = rec["bisClass"]
            if rec.get("bisVal") is not None: t["bisV"] = rec["bisVal"]
            if rec.get("bisRank") is not None: t["bisR"] = rec["bisRank"]
            if rec.get("bisTotal") is not None: t["bisT"] = rec["bisTotal"]
            if rec.get("bisBestName") is not None: t["bisBN"] = rec["bisBestName"]
            if rec.get("bisBestVal") is not None: t["bisBV"] = rec["bisBestVal"]

        # Preserve exact CAMP_RECIPES_BY_REP order if different from idx order
        if rec is not None and rec["source"] == "camp" and rec["idx"] in camp_order:
            t["campOrd"] = camp_order[rec["idx"]][1]
        recipe_lines.append(t)

    # Assemble Data_Recipes.lua
    parts = []
    parts.append("-- MerchantMaster: Unified Item & Recipe Catalog (single source of truth for items, recipes, vendor prices, BiS & Professor leveling)\n")
    parts.append("local _, ns = ...\n\n")
    parts.append(mp_header)
    parts.append("\n-- Section 1: Unified Item Catalog (replaces VENDOR_REAGENTS, EXTRA_NAMES, RItem, MP.EXTRA_VENDOR_REAGENTS & MP.ITEM_INFO)\n")
    parts.append("ns.ITEMS = {}\n")
    parts.append("ns.VENDOR_REAGENTS = {}\n")
    parts.append("ns.ITEM_VENDOR_SELL = {}\n")
    parts.append("ns.ITEM_BOP = {}\n")
    parts.append("MP.ITEM_INFO = {}\n")
    parts.append(
        "local function I(id, name, sell, buy, vbuy, bop, mpFlag)\n"
        "\tns.RegisterItem(id, name)\n"
        "\tlocal hasMP = mpFlag ~= nil or buy ~= nil\n"
        "\tlocal mpBuy = (buy ~= nil and buy ~= -1) and buy or nil\n"
        "\tlocal vendorPrice = (vbuy == true and mpBuy) or (type(vbuy) == 'number' and vbuy) or nil\n"
        "\tns.ITEMS[id] = { id = id, name = name, sell = sell, buy = mpBuy, vendorPrice = vendorPrice, bop = bop == true }\n"
        "\tif sell ~= nil then ns.ITEM_VENDOR_SELL[id] = sell end\n"
        "\tif bop == true then ns.ITEM_BOP[id] = true end\n"
        "\tif vendorPrice ~= nil then ns.VENDOR_REAGENTS[id] = vendorPrice end\n"
        "\tif hasMP then\n"
        "\t\tlocal mpName = (type(mpFlag) == 'table' and mpFlag.n) or name\n"
        "\t\tlocal mpSell = (type(mpFlag) == 'table' and mpFlag.s) or sell\n"
        "\t\tMP.ITEM_INFO[id] = { name = mpName, sell = mpSell, buy = mpBuy, bop = bop == true }\n"
        "\tend\n"
        "end\n\n"
    )

    chunk = 250
    for start in range(0, len(item_lines), chunk):
        parts.append("do (function()\n")
        parts.extend(item_lines[start : start + chunk])
        parts.append("end)() end\n")

    if id_by_name_overrides:
        parts.append("\n-- Preserve legacy first-registered itemID for shared item names\n")
        for name, want_id in id_by_name_overrides:
            parts.append(f"ns.ITEM_IDS_BY_NAME[{lua_val(name)}] = {want_id}\n")

    parts.append("\n-- Section 2: Unified Recipe Catalog (replaces Data_Recipes + M + MP.RECIPES; single row per recipe)\n")
    parts.append("ns.RECIPES = {}\n")
    parts.append("ns.CAMP_RECIPES_BY_REP = { [0] = {}, [5] = {}, [6] = {}, [7] = {}, [8] = {} }\n")
    parts.append("MP.RECIPES = {}\n")
    parts.append("for _, pk in ipairs(MP.PROF_ORDER) do MP.RECIPES[pk] = {} end\n")
    parts.append("MP.RECIPES_BY_SPELL = {}\n")
    parts.append("local campSlots = { [0] = {}, [5] = {}, [6] = {}, [7] = {}, [8] = {} }\n\n")
    parts.append(
        "local function cloneReagents(r)\n"
        "\tif not r then return nil end\n"
        "\tlocal out = {}\n"
        "\tfor i = 1, #r do out[i] = { r[i][1], r[i][2] } end\n"
        "\treturn out\n"
        "end\n\n"
        "local function mpVal(override, fallback)\n"
        "\tif override == false then return nil end\n"
        "\tif override ~= nil then return override end\n"
        "\treturn fallback\n"
        "end\n\n"
    )
    parts.append(
        "local function R(t)\n"
        "\tif not t.mpOnly then\n"
        "\t\tlocal outID = t.i\n"
        "\t\tlocal recID = t.ri\n"
        "\t\tlocal reagents = t.r or {}\n"
        "\t\tfor _, rg in ipairs(reagents) do ns.ALL_CATALOG_IDS[rg[1]] = true end\n"
        "\t\tlocal isEnch = t.ench == true\n"
        "\t\tlocal isBoP = outID ~= nil and ns.ITEM_BOP[outID] == true\n"
        "\t\tlocal sellable = t.sell\n"
        "\t\tif sellable == nil then sellable = (not isEnch) and (not isBoP) and (outID ~= nil) end\n"
        "\t\tlocal prof = t.prof or t.pk\n"
        "\t\tlocal entry = {\n"
        "\t\t\tidx = t.idx,\n"
        "\t\t\tspellID = t.s,\n"
        "\t\t\trecipeItemID = recID,\n"
        "\t\t\toutputItemID = outID,\n"
        "\t\t\tname = t.n,\n"
        "\t\t\trecipeName = t.rn or t.n,\n"
        "\t\t\tprof = prof,\n"
        "\t\t\tskill = t.skill,\n"
        "\t\t\trep = t.rep or 0,\n"
        "\t\t\tfavorCost = t.fav or 0,\n"
        "\t\t\tsource = t.source,\n"
        "\t\t\tacqType = t.acq,\n"
        "\t\t\tnumMade = t.c or 1,\n"
        "\t\t\tsellable = sellable,\n"
        "\t\t\tisEnchant = isEnch,\n"
        "\t\t\treagents = reagents,\n"
        "\t\t\ttrainerCost = t.tc,\n"
        "\t\t\trecipeVendorPrice = t.rbuy,\n"
        "\t\t\tvendorA = t.vA,\n"
        "\t\t\tvendorH = t.vH,\n"
        "\t\t\tvendorAll = t.vAll,\n"
        "\t\t\treqCharLevel = t.rlv,\n"
        "\t\t\teffectText = t.eff,\n"
        "\t\t\tisBiS = t.bis,\n"
        "\t\t\tbisClass = t.bisC,\n"
        "\t\t\tbisVal = t.bisV,\n"
        "\t\t\tbisRank = t.bisR,\n"
        "\t\t\tbisTotal = t.bisT,\n"
        "\t\t\tbisBestName = t.bisBN,\n"
        "\t\t\tbisBestVal = t.bisBV,\n"
        "\t\t}\n"
        "\t\tns.RECIPES[t.idx] = entry\n"
        "\t\tif entry.source == 'camp' and campSlots[entry.rep] then\n"
        "\t\t\tlocal pos = t.campOrd ~= nil and (t.campOrd + 1) or (#campSlots[entry.rep] + 1)\n"
        "\t\t\tcampSlots[entry.rep][pos] = entry\n"
        "\t\tend\n"
        "\tend\n"
        "\tif not t.mmOnly then\n"
        "\t\tlocal pk = t.pk\n"
        "\t\tMP.RECIPES[pk] = MP.RECIPES[pk] or {}\n"
        "\t\tlocal m\n"
        "\t\tif t.mpOnly then\n"
        "\t\t\tm = {}\n"
        "\t\t\tfor k, v in pairs(t) do\n"
        "\t\t\t\tif k ~= 'mpOnly' and k ~= 'pk' and k ~= 'mpIdx' and k ~= 'bySp' then m[k] = v end\n"
        "\t\t\tend\n"
        "\t\t\tm.prof = t.mpProf or pk\n"
        "\t\telse\n"
        "\t\t\tlocal mpR\n"
        "\t\t\tif t.mpR == false then mpR = nil\n"
        "\t\t\telseif t.mpR ~= nil then mpR = t.mpR\n"
        "\t\t\telse mpR = cloneReagents(t.r) end\n"
        "\t\t\tm = {\n"
        "\t\t\t\ts = (t.mpS ~= nil) and t.mpS or t.s,\n"
        "\t\t\t\ti = (t.mpI ~= nil) and t.mpI or t.i,\n"
        "\t\t\t\tn = (t.mpN ~= nil) and t.mpN or t.n,\n"
        "\t\t\t\tc = mpVal(t.mpC, t.c or 1),\n"
        "\t\t\t\treq = (t.mpReq ~= nil) and t.mpReq or t.skill,\n"
        "\t\t\t\ty = t.y, g = t.g, gr = t.gr,\n"
        "\t\t\t\tsrc = t.mpSrc or t.acq,\n"
        "\t\t\t\trlv = mpVal(t.mpRlv, t.rlv),\n"
        "\t\t\t\telv = t.elv,\n"
        "\t\t\t\ttc = mpVal(t.mpTc, t.tc),\n"
        "\t\t\t\tri = mpVal(t.mpRi, t.ri),\n"
        "\t\t\t\trn = mpVal(t.mpRn, t.rn),\n"
        "\t\t\t\trbuy = mpVal(t.mpRbuy, t.rbuy),\n"
        "\t\t\t\tfav = mpVal(t.mpFav, t.fav),\n"
        "\t\t\t\trep = mpVal(t.mpRep, t.rep),\n"
        "\t\t\t\tvn = mpVal(t.vn, t.vAll),\n"
        "\t\t\t\tfac = t.fac, pre = t.pre, spec = t.spec, rod = t.rod, cd = t.cd,\n"
        "\t\t\t\tench = mpVal(t.mpEnch, t.ench),\n"
        "\t\t\t\tbop = t.bop,\n"
        "\t\t\t\tr = mpR,\n"
        "\t\t\t\tprof = t.mpProf or pk,\n"
        "\t\t\t}\n"
        "\t\tend\n"
        "\t\tMP.RECIPES[pk][t.mpIdx] = m\n"
        "\t\tif t.bySp and m.s then MP.RECIPES_BY_SPELL[m.s] = m end\n"
        "\tend\n"
        "end\n\n"
    )

    rchunk = 180
    for start in range(0, len(recipe_lines), rchunk):
        parts.append("do (function()\n")
        for row in recipe_lines[start : start + rchunk]:
            parts.append(f"\tR({lua_val(row)})\n")
        parts.append("end)() end\n")

    parts.append(
        "\nfor rep, list in pairs(campSlots) do\n"
        "\tlocal target = ns.CAMP_RECIPES_BY_REP[rep]\n"
        "\tfor _, e in ipairs(list) do target[#target + 1] = e end\n"
        "end\n\n"
        "-- Backfill Craftman's Writ numMade and reagents from ns.RECIPES when shared by spellID\n"
        "do\n"
        "\tlocal bySpell = {}\n"
        "\tfor _, rec in ipairs(ns.RECIPES) do\n"
        "\t\tif rec.spellID and not bySpell[rec.spellID] then bySpell[rec.spellID] = rec end\n"
        "\tend\n"
        "\tfor _, w in ipairs(ns.WRITS or {}) do\n"
        "\t\tif w.reagents == nil and w.spellID and bySpell[w.spellID] then\n"
        "\t\t\tlocal rec = bySpell[w.spellID]\n"
        "\t\t\tw.numMade = w.numMade or rec.numMade\n"
        "\t\t\tw.reagents = cloneReagents(rec.reagents)\n"
        "\t\t\tfor _, rg in ipairs(w.reagents or {}) do ns.ALL_CATALOG_IDS[rg[1]] = true end\n"
        "\t\tend\n"
        "\tend\n"
        "end\n"
    )

    if write:
        (MM / "Data_Recipes.lua").write_text("".join(parts), encoding="utf-8", newline="\n")
    return {
        "items": len(all_ids),
        "id_by_name_overrides": len(id_by_name_overrides),
        "unified_recipes": len(recipe_lines),
        "matched": matched_count,
        "mm_only": mm_only_count,
        "mp_only": mp_only_count,
    }


def verify_parity(old_dir: Path) -> None:
    res = subprocess.run(
        [LUA, "-", old_dir.as_posix(), MM.as_posix()],
        input=PARITY_LUA,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if res.returncode != 0 or "PARITY_OK" not in res.stdout:
        print("PARITY STDOUT:\n" + res.stdout, file=sys.stderr)
        print("PARITY STDERR:\n" + res.stderr, file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-ref", default=BASELINE_COMMIT, help="Git ref holding pre-unification 3-file catalog")
    parser.add_argument("--old-dir", type=Path, default=None, help="Optional directory containing legacy Data_* files")
    parser.add_argument("--write", action="store_true", help="Overwrite Data_CratesAndWrits.lua and Data_Recipes.lua from baseline")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        old_dir = args.old_dir or export_baseline_files(Path(tmp), args.baseline_ref)
        truth = dump_ground_truth(old_dir)
        deduped, kept = rebuild_crates_and_writs(old_dir, truth, write=args.write)
        stats = build_unified_recipes(old_dir, truth, write=args.write)
        verify_parity(old_dir)
        mode = "WROTE+PARITY_OK" if args.write else "PARITY_OK (read-only)"
        print(
            f"{mode} items={stats['items']} name_overrides={stats['id_by_name_overrides']} "
            f"unified_recipes={stats['unified_recipes']} matched={stats['matched']} mm_only={stats['mm_only']} mp_only={stats['mp_only']} "
            f"writ_reagents_deduped={deduped} writ_reagents_explicit={kept}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
