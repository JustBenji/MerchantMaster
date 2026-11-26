"""Blizzard Official WoW: Forever Static Catalog Verifier & Safe Importer.

Audits MerchantMaster's Data_Recipes.lua against Blizzard's official
`static-forever-{region}` Game Data API (professions, skill-tiers, recipes,
and items) and generates exact patch-drift reports (JSON + Markdown) plus a
zero-data-loss `apply-safe` patcher (`--dry-run` by default).

Security & Rate-Limit Guardrails:
  - Pure Python 3.11 stdlib (zero third-party dependencies).
  - Reads `BLIZZARD_CLIENT_ID` / `BLIZZARD_CLIENT_SECRET` from environment or
    Windows HKCU user environment; NEVER prints, logs, or stores
    credentials, Authorization headers, or OAuth tokens.
  - Concurrency capped at <= 12 workers and polite token-bucket rate limiting
    capped at <= 25 req/sec (far below Blizzard's 100 req/sec limit).
  - Caches public static API responses in
    `%LOCALAPPDATA%\\MerchantMaster\\static_catalog_cache.json` (`--refresh`
    to bust cache).
"""

from __future__ import annotations

import argparse
import base64
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
import difflib
import gzip
import http.client
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
import threading
import time
from typing import Any, Callable, Dict, List, Optional, Sequence, Set, Tuple
import urllib.error
import urllib.parse
import urllib.request

TOOLS_DIR = Path(__file__).resolve().parent
MM_ROOT = TOOLS_DIR.parent
if str(MM_ROOT) not in sys.path:
    sys.path.insert(0, str(MM_ROOT))

DEFAULT_BLIZZARD_REGION = "eu"
DEFAULT_CATALOG_PATH = MM_ROOT / "Data_Recipes.lua"

HttpResponse = Tuple[int, Dict[str, str], bytes]
HttpTransport = Callable[[str, str, Dict[str, str], Optional[bytes], float], HttpResponse]

_ALLOWED_WINREG_ENV_KEYS = frozenset({"BLIZZARD_CLIENT_ID", "BLIZZARD_CLIENT_SECRET"})


def _read_windows_user_env(name: str) -> str:
    if sys.platform != "win32" or name not in _ALLOWED_WINREG_ENV_KEYS:
        return ""
    try:
        import winreg
    except ImportError:
        return ""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            val, _ = winreg.QueryValueEx(key, name)
            return str(val).strip()
    except OSError:
        return ""


def get_blizzard_credentials() -> Optional[Tuple[str, str]]:
    """Read Blizzard OAuth credentials from environment (or HKCU\\Environment on Windows)."""
    client_id = os.environ.get("BLIZZARD_CLIENT_ID", "").strip() or _read_windows_user_env("BLIZZARD_CLIENT_ID")
    client_secret = os.environ.get("BLIZZARD_CLIENT_SECRET", "").strip() or _read_windows_user_env("BLIZZARD_CLIENT_SECRET")
    if not client_id or not client_secret:
        return None
    return client_id, client_secret


def _default_transport(
    method: str,
    url: str,
    headers: Dict[str, str],
    body: Optional[bytes],
    timeout: float,
) -> HttpResponse:
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            resp_headers = {k.lower(): v for k, v in resp.headers.items()}
            return int(resp.status), resp_headers, resp.read()
    except urllib.error.HTTPError as exc:
        resp_headers = {k.lower(): v for k, v in exc.headers.items()} if exc.headers else {}
        raw = exc.read() if exc.fp is not None else b""
        return int(exc.code), resp_headers, raw
    except http.client.HTTPException as exc:
        raise RuntimeError(f"Blizzard HTTP transport error ({type(exc).__name__})") from exc


def _decode_json_body(headers: Dict[str, str], body: bytes) -> Any:
    if not body:
        return {}
    enc = headers.get("content-encoding", "").lower()
    try:
        data = gzip.decompress(body) if "gzip" in enc else body
        return json.loads(data.decode("utf-8"))
    except (OSError, EOFError, UnicodeDecodeError, ValueError) as exc:
        raise RuntimeError(f"Blizzard API returned invalid response body ({type(exc).__name__})") from exc


def _extract_id_from_entry(entry: Dict[str, Any]) -> Optional[int]:
    if "id" in entry and isinstance(entry["id"], int):
        return int(entry["id"])
    key_href = ""
    if isinstance(entry.get("key"), dict):
        key_href = str(entry["key"].get("href", ""))
    elif isinstance(entry.get("href"), str):
        key_href = entry["href"]
    if key_href:
        tail = urllib.parse.urlparse(key_href).path.rstrip("/").rsplit("/", 1)[-1]
        if tail.isdigit():
            return int(tail)
    return None


def _extract_localized_name(val: Any) -> str:
    if isinstance(val, str):
        return val.strip()
    if isinstance(val, dict):
        for loc in ("en_US", "en_GB"):
            v = val.get(loc)
            if isinstance(v, str) and v.strip():
                return v.strip()
        for v in val.values():
            if isinstance(v, str) and v.strip():
                return v.strip()
    return ""


class BlizzardForeverClient:
    """Minimal stdlib OAuth HTTP client base for WoW Forever Game Data APIs."""

    def __init__(
        self,
        client_id: str,
        client_secret: str,
        region: str = DEFAULT_BLIZZARD_REGION,
        db: Optional[Any] = None,
        transport: Optional[HttpTransport] = None,
        timeout: float = 30.0,
    ) -> None:
        self._client_id = client_id
        self._client_secret = client_secret
        self.region = region.lower().strip() or DEFAULT_BLIZZARD_REGION
        self.namespace = f"dynamic-forever-{self.region}"
        self.api_base = f"https://{self.region}.api.blizzard.com"
        self.oauth_url = "https://oauth.battle.net/token"
        self._db = db
        self._transport = transport or _default_transport
        self._timeout = timeout
        self._token: Optional[str] = None
        self._token_expires_at: float = 0.0

    def _get_token(self) -> str:
        now = time.time()
        if self._token and now < self._token_expires_at - 60:
            return self._token
        basic_raw = f"{self._client_id}:{self._client_secret}".encode("utf-8")
        basic_b64 = base64.b64encode(basic_raw).decode("ascii")
        headers = {
            "Authorization": f"Basic {basic_b64}",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept-Encoding": "gzip",
        }
        status, resp_headers, body = self._transport(
            "POST", self.oauth_url, headers, b"grant_type=client_credentials", self._timeout
        )
        if status != 200:
            raise RuntimeError(f"Blizzard OAuth token request failed (HTTP {status})")
        payload = _decode_json_body(resp_headers, body)
        if not isinstance(payload, dict) or not payload.get("access_token"):
            raise RuntimeError("Blizzard OAuth response missing access_token")
        expires_in = int(payload.get("expires_in", 3600) or 3600)
        self._token = str(payload["access_token"])
        self._token_expires_at = now + expires_in
        return self._token

# ---------------------------------------------------------------------------
# Constants & Profession Mapping
# ---------------------------------------------------------------------------

CACHE_SCHEMA_VERSION = 1
MAX_WORKERS = 12
DEFAULT_WORKERS = 10
MAX_RATE_PER_SEC = 25.0
DEFAULT_RATE_PER_SEC = 20.0
IGNORED_PROFESSION_IDS = frozenset({2933})  # 2933 = Test Profession [DNT]

# Matches tools/check_glyphs.py ALLOWED set exactly
ALLOWED_NON_ASCII_GLYPHS = frozenset(
    {"·", "—", "–", "…", "×", "é", "ê", "è", "É", "ô", "à"}
)

PROFESSION_ID_TO_KEY: Dict[int, str] = {
    171: "alchemy",
    164: "blacksmithing",
    185: "cooking",
    333: "enchanting",
    202: "engineering",
    129: "firstaid",
    165: "leatherworking",
    186: "mining",
    197: "tailoring",
    182: "herbalism",
    393: "skinning",
    356: "fishing",
}

NON_API_PROFESSIONS = frozenset({"poisons", "others"})


def default_cache_path() -> Path:
    """Resolve the default non-secret static catalog cache JSON path."""
    env_override = os.environ.get("MERCHANTMASTER_STATIC_CACHE", "").strip()
    if env_override:
        return Path(env_override)
    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    base = Path(local_app_data) if local_app_data else Path.home()
    return base / "MerchantMaster" / "static_catalog_cache.json"


def prof_key_from_api(prof_id: int, prof_name: str) -> str:
    if prof_id in PROFESSION_ID_TO_KEY:
        return PROFESSION_ID_TO_KEY[prof_id]
    cleaned = re.sub(r"[^a-z0-9]+", "", (prof_name or "").lower())
    return cleaned or f"prof_{prof_id}"


# ---------------------------------------------------------------------------
# Minimal Lua Literal Parser (for I(...) and R({...}) lines)
# ---------------------------------------------------------------------------


class LuaParseError(ValueError):
    """Raised when a Data_Recipes.lua I(...) or R(...) call cannot be parsed."""


def _unescape_lua_string(raw: str) -> str:
    out: List[str] = []
    i = 0
    n = len(raw)
    while i < n:
        ch = raw[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= n:
            break
        esc = raw[i]
        if esc == "n":
            out.append("\n")
            i += 1
        elif esc == "r":
            out.append("\r")
            i += 1
        elif esc == "t":
            out.append("\t")
            i += 1
        elif esc in ("\\", '"', "'"):
            out.append(esc)
            i += 1
        elif esc.isdigit():
            digits = esc
            i += 1
            for _ in range(2):
                if i < n and raw[i].isdigit():
                    digits += raw[i]
                    i += 1
                else:
                    break
            out.append(chr(int(digits)))
        else:
            out.append(esc)
            i += 1
    return "".join(out)


def _escape_lua_string(text: str) -> str:
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


class _LuaLineParser:
    """Recursive-descent parser for Lua literal expressions with exact spans."""

    def __init__(self, text: str, pos: int = 0) -> None:
        self.text = text
        self.pos = pos
        self.n = len(text)

    def skip_ws(self) -> None:
        while self.pos < self.n and self.text[self.pos] in " \t\r\n":
            self.pos += 1

    def parse_value(self) -> Tuple[Any, Tuple[int, int]]:
        self.skip_ws()
        start = self.pos
        if start >= self.n:
            raise LuaParseError(f"Unexpected end of expression at {start}")
        ch = self.text[start]
        if ch in ('"', "'"):
            val = self._parse_string()
            return val, (start, self.pos)
        if ch == "{":
            val = self._parse_table()
            return val, (start, self.pos)
        if ch == "-" or ch.isdigit():
            val = self._parse_number()
            return val, (start, self.pos)
        if ch.isalpha() or ch == "_":
            ident = self._parse_ident()
            if ident == "true":
                return True, (start, self.pos)
            if ident == "false":
                return False, (start, self.pos)
            if ident == "nil":
                return None, (start, self.pos)
            raise LuaParseError(f"Unexpected identifier {ident!r} at {start}")
        raise LuaParseError(f"Unexpected char {ch!r} at {start}")

    def _parse_string(self) -> str:
        quote = self.text[self.pos]
        self.pos += 1
        start = self.pos
        while self.pos < self.n:
            ch = self.text[self.pos]
            if ch == "\\":
                self.pos += 2
                continue
            if ch == quote:
                raw = self.text[start : self.pos]
                self.pos += 1
                return _unescape_lua_string(raw)
            self.pos += 1
        raise LuaParseError("Unterminated Lua string literal")

    def _parse_number(self) -> Any:
        start = self.pos
        if self.text[self.pos] == "-":
            self.pos += 1
        has_dot = False
        while self.pos < self.n:
            ch = self.text[self.pos]
            if ch.isdigit():
                self.pos += 1
            elif ch == "." and not has_dot:
                has_dot = True
                self.pos += 1
            else:
                break
        token = self.text[start : self.pos]
        return float(token) if has_dot else int(token)

    def _parse_ident(self) -> str:
        start = self.pos
        while self.pos < self.n and (self.text[self.pos].isalnum() or self.text[self.pos] == "_"):
            self.pos += 1
        return self.text[start : self.pos]

    def _parse_table(self) -> Any:
        assert self.text[self.pos] == "{"
        self.pos += 1
        seq: List[Any] = []
        mapping: Dict[Any, Any] = {}
        is_map = False
        while True:
            self.skip_ws()
            if self.pos >= self.n:
                raise LuaParseError("Unterminated Lua table")
            if self.text[self.pos] == "}":
                self.pos += 1
                break
            saved = self.pos
            # Check for [key]=val or ident=val
            if self.text[self.pos] == "[":
                self.pos += 1
                k, _ = self.parse_value()
                self.skip_ws()
                if self.pos >= self.n or self.text[self.pos] != "]":
                    raise LuaParseError("Expected ']' in table key")
                self.pos += 1
                self.skip_ws()
                if self.pos >= self.n or self.text[self.pos] != "=":
                    raise LuaParseError("Expected '=' after table key")
                self.pos += 1
                v, _ = self.parse_value()
                mapping[k] = v
                is_map = True
            elif self.text[self.pos].isalpha() or self.text[self.pos] == "_":
                ident = self._parse_ident()
                self.skip_ws()
                if self.pos < self.n and self.text[self.pos] == "=":
                    self.pos += 1
                    v, _ = self.parse_value()
                    mapping[ident] = v
                    is_map = True
                else:
                    self.pos = saved
                    v, _ = self.parse_value()
                    seq.append(v)
            else:
                v, _ = self.parse_value()
                seq.append(v)
            self.skip_ws()
            if self.pos < self.n and self.text[self.pos] in (",", ";"):
                self.pos += 1
        if is_map and not seq:
            return mapping
        if not is_map:
            return seq
        # Mixed table (rare in Data_Recipes.lua)
        out = dict(mapping)
        for idx, item in enumerate(seq, 1):
            out[idx] = item
        return out

    def parse_top_table_with_spans(
        self,
    ) -> Tuple[Dict[Any, Any], Dict[str, Tuple[int, int]], Dict[str, Tuple[int, int]]]:
        """Parse top-level R({...}) table, tracking both full-entry and value spans."""
        self.skip_ws()
        if self.pos >= self.n or self.text[self.pos] != "{":
            raise LuaParseError("Expected '{' for R(...) table")
        self.pos += 1
        data: Dict[Any, Any] = {}
        entry_spans: Dict[str, Tuple[int, int]] = {}
        value_spans: Dict[str, Tuple[int, int]] = {}
        while True:
            self.skip_ws()
            if self.pos >= self.n:
                raise LuaParseError("Unterminated R(...) table")
            if self.text[self.pos] == "}":
                self.pos += 1
                break
            entry_start = self.pos
            if self.text[self.pos] == "[":
                self.pos += 1
                k, _ = self.parse_value()
                self.skip_ws()
                if self.pos >= self.n or self.text[self.pos] != "]":
                    raise LuaParseError("Expected ']' in R(...) key")
                self.pos += 1
                self.skip_ws()
                if self.pos >= self.n or self.text[self.pos] != "=":
                    raise LuaParseError("Expected '=' in R(...) entry")
                self.pos += 1
                v, vspan = self.parse_value()
                key_str = str(k)
                data[k] = v
                entry_spans[key_str] = (entry_start, vspan[1])
                value_spans[key_str] = vspan
            else:
                ident = self._parse_ident()
                self.skip_ws()
                if self.pos >= self.n or self.text[self.pos] != "=":
                    raise LuaParseError(f"Expected '=' after key {ident!r} in R(...)")
                self.pos += 1
                v, vspan = self.parse_value()
                data[ident] = v
                entry_spans[ident] = (entry_start, vspan[1])
                value_spans[ident] = vspan
            self.skip_ws()
            if self.pos < self.n and self.text[self.pos] in (",", ";"):
                self.pos += 1
        return data, entry_spans, value_spans


# ---------------------------------------------------------------------------
# Local Catalog Data Structures & Parser
# ---------------------------------------------------------------------------


@dataclass
class LocalItem:
    item_id: int
    name: str
    sell: Optional[int]
    buy: Optional[int]
    vbuy: Any  # None | True | int
    bop: bool
    mp_flag: Any  # None | True | dict
    vendor_price: Optional[int]
    mp_name: str
    mp_sell: Optional[int]
    line_no: int  # 1-based
    raw_line: str
    arg_count: int
    args_raw: List[Any] = field(default_factory=list)


@dataclass
class LocalRecipe:
    line_no: int  # 1-based
    raw_line: str
    idx: Optional[int]
    mp_idx: Optional[int]
    prof: str
    spell_id: Optional[int]
    mp_spell_id: Optional[int]
    name: str
    mp_name: Optional[str]
    output_item_id: Optional[int]
    recipe_item_id: Optional[int]
    num_made: Any  # int or float
    mp_num_made: Any
    reagents: List[Tuple[int, int]]
    has_mp_reagents: bool
    is_enchant: bool
    mm_only: bool
    mp_only: bool
    any_char: bool
    source: Optional[str]
    acq: Optional[str]
    fields: Dict[str, Any] = field(default_factory=dict)
    entry_spans: Dict[str, Tuple[int, int]] = field(default_factory=dict)
    value_spans: Dict[str, Tuple[int, int]] = field(default_factory=dict)


@dataclass
class LocalCatalog:
    path: Path
    items: Dict[int, LocalItem]
    recipes: List[LocalRecipe]
    line_ending: str


_ITEM_CALL_PREFIX_RE = re.compile(r"^(\s*)I\(")
_RECIPE_CALL_PREFIX_RE = re.compile(r"^(\s*)R\(")


def parse_item_line(line: str, line_no: int) -> Optional[LocalItem]:
    m = _ITEM_CALL_PREFIX_RE.match(line)
    if not m:
        return None
    parser = _LuaLineParser(line, m.end())
    args: List[Any] = []
    while True:
        parser.skip_ws()
        if parser.pos >= parser.n:
            raise LuaParseError(f"Line {line_no}: unterminated I(...) call")
        if line[parser.pos] == ")":
            parser.pos += 1
            break
        val, _ = parser.parse_value()
        args.append(val)
        parser.skip_ws()
        if parser.pos < parser.n and line[parser.pos] == ",":
            parser.pos += 1
        elif parser.pos < parser.n and line[parser.pos] == ")":
            parser.pos += 1
            break
        else:
            raise LuaParseError(
                f"Line {line_no}: expected ',' or ')' in I(...) at col {parser.pos}"
            )
    if len(args) < 1 or not isinstance(args[0], int) or isinstance(args[0], bool):
        raise LuaParseError(f"Line {line_no}: invalid I(...) id arg")
    if len(args) >= 2 and args[1] is not None and not isinstance(args[1], str):
        raise LuaParseError(f"Line {line_no}: invalid I(...) name arg")

    padded = list(args) + [None] * max(0, 7 - len(args))
    item_id = int(padded[0])
    name = str(padded[1]) if isinstance(padded[1], str) else ""
    sell = int(padded[2]) if isinstance(padded[2], (int, float)) and not isinstance(padded[2], bool) else None
    raw_buy = padded[3]
    mp_buy = (
        int(raw_buy)
        if isinstance(raw_buy, (int, float))
        and not isinstance(raw_buy, bool)
        and raw_buy != -1
        else None
    )
    vbuy = padded[4]
    if vbuy is True:
        vendor_price = mp_buy
    elif isinstance(vbuy, (int, float)) and not isinstance(vbuy, bool):
        vendor_price = int(vbuy)
    else:
        vendor_price = None
    bop_bool = padded[5] is True
    mp_flag = padded[6]
    mp_name = mp_flag.get("n", name) if isinstance(mp_flag, dict) else name
    mp_sell = mp_flag.get("s", sell) if isinstance(mp_flag, dict) else sell

    return LocalItem(
        item_id=item_id,
        name=name,
        sell=sell,
        buy=mp_buy,
        vbuy=vbuy,
        bop=bop_bool,
        mp_flag=mp_flag,
        vendor_price=vendor_price,
        mp_name=str(mp_name),
        mp_sell=int(mp_sell) if isinstance(mp_sell, (int, float)) and not isinstance(mp_sell, bool) else None,
        line_no=line_no,
        raw_line=line,
        arg_count=len(args),
        args_raw=list(args),
    )


def parse_recipe_line(line: str, line_no: int) -> Optional[LocalRecipe]:
    m = _RECIPE_CALL_PREFIX_RE.match(line)
    if not m:
        return None
    parser = _LuaLineParser(line, m.end())
    fields, entry_spans, value_spans = parser.parse_top_table_with_spans()
    parser.skip_ws()
    if parser.pos >= parser.n or line[parser.pos] != ")":
        raise LuaParseError(f"Line {line_no}: expected ')' closing R(...)")

    prof = str(fields.get("prof") or fields.get("pk") or "").strip().lower()
    raw_i = fields.get("i")
    output_id: Optional[int] = None
    if isinstance(raw_i, int) and not isinstance(raw_i, bool) and raw_i > 0:
        output_id = int(raw_i)

    raw_ri = fields.get("ri")
    rec_item_id: Optional[int] = (
        int(raw_ri)
        if isinstance(raw_ri, int) and not isinstance(raw_ri, bool) and raw_ri > 0
        else None
    )

    raw_r = fields.get("mpR") if isinstance(fields.get("mpR"), list) else fields.get("r")
    reagents: List[Tuple[int, int]] = []
    if isinstance(raw_r, list):
        for pair in raw_r:
            if isinstance(pair, list) and len(pair) >= 2:
                reagents.append((int(pair[0]), int(pair[1])))

    raw_c = fields.get("c")
    num_made = raw_c if raw_c is not None else 1

    return LocalRecipe(
        line_no=line_no,
        raw_line=line,
        idx=int(fields["idx"]) if isinstance(fields.get("idx"), int) else None,
        mp_idx=int(fields["mpIdx"]) if isinstance(fields.get("mpIdx"), int) else None,
        prof=prof,
        spell_id=int(fields["s"]) if isinstance(fields.get("s"), int) else None,
        mp_spell_id=int(fields["mpS"]) if isinstance(fields.get("mpS"), int) else None,
        name=str(fields.get("n") or ""),
        mp_name=str(fields["mpN"]) if isinstance(fields.get("mpN"), str) else None,
        output_item_id=output_id,
        recipe_item_id=rec_item_id,
        num_made=num_made,
        mp_num_made=fields.get("mpC"),
        reagents=reagents,
        has_mp_reagents=isinstance(fields.get("mpR"), list),
        is_enchant=fields.get("ench") is True,
        mm_only=fields.get("mmOnly") is True,
        mp_only=fields.get("mpOnly") is True,
        any_char=fields.get("any") is True,
        source=str(fields["source"]) if isinstance(fields.get("source"), str) else None,
        acq=str(fields["acq"]) if isinstance(fields.get("acq"), str) else None,
        fields=fields,
        entry_spans=entry_spans,
        value_spans=value_spans,
    )


def parse_data_recipes(path: Path) -> LocalCatalog:
    """Parse Data_Recipes.lua cleanly into items and recipes with line spans."""
    raw_bytes = path.read_bytes()
    if raw_bytes.startswith(b"\xef\xbb\xbf"):
        text = raw_bytes[3:].decode("utf-8")
    else:
        text = raw_bytes.decode("utf-8")
    line_ending = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()

    items: Dict[int, LocalItem] = {}
    recipes: List[LocalRecipe] = []
    for idx, line in enumerate(lines, 1):
        stripped = line.lstrip()
        if stripped.startswith("I("):
            item = parse_item_line(line, idx)
            if item is not None:
                items[item.item_id] = item
        elif stripped.startswith("R({"):
            rec = parse_recipe_line(line, idx)
            if rec is not None:
                recipes.append(rec)
    return LocalCatalog(path=path, items=items, recipes=recipes, line_ending=line_ending)


# ---------------------------------------------------------------------------
# Rate-Limited Static Blizzard Client (`static-forever-{region}`)
# ---------------------------------------------------------------------------


class TokenBucketRateLimiter:
    """Thread-safe polite rate limiter (strictly capped <= 25 req/sec)."""

    def __init__(self, rate_per_sec: float = DEFAULT_RATE_PER_SEC, burst: int = 5) -> None:
        self.rate = max(1.0, min(MAX_RATE_PER_SEC, float(rate_per_sec)))
        self.capacity = max(1.0, float(burst))
        self._tokens = self.capacity
        self._last = time.monotonic()
        self._lock = threading.Lock()

    def acquire(self) -> None:
        while True:
            with self._lock:
                now = time.monotonic()
                elapsed = max(0.0, now - self._last)
                self._tokens = min(self.capacity, self._tokens + elapsed * self.rate)
                self._last = now
                if self._tokens >= 1.0:
                    self._tokens -= 1.0
                    return
                wait_s = (1.0 - self._tokens) / self.rate
            time.sleep(min(wait_s, 0.25))


class BlizzardForeverStaticClient(BlizzardForeverClient):
    """Thread-safe, rate-limited static-forever-{region} client.

    Reuses BlizzardForeverClient OAuth token handling; never prints, logs, or
    stores client credentials, Authorization headers, or OAuth tokens.
    """

    def __init__(
        self,
        client_id: str,
        client_secret: str,
        region: str = DEFAULT_BLIZZARD_REGION,
        transport: Optional[HttpTransport] = None,
        timeout: float = 30.0,
        rate_per_sec: float = DEFAULT_RATE_PER_SEC,
        max_retries: int = 4,
    ) -> None:
        super().__init__(
            client_id=client_id,
            client_secret=client_secret,
            region=region,
            db=None,
            transport=transport,
            timeout=timeout,
        )
        self.namespace = f"static-forever-{self.region}"
        self._token_lock = threading.Lock()
        self._limiter = TokenBucketRateLimiter(rate_per_sec=rate_per_sec, burst=5)
        self._max_retries = max(1, int(max_retries))
        self._stats_lock = threading.Lock()
        self.http_requests = 0
        self.http_retries = 0

    def _get_token(self) -> str:  # type: ignore[override]
        with self._token_lock:
            return super()._get_token()

    def static_get(self, path: str, locale: str = "en_US") -> Tuple[int, Optional[Any]]:
        sep = "&" if "?" in path else "?"
        url = (
            f"{self.api_base}{path}{sep}"
            f"namespace={urllib.parse.quote(self.namespace)}"
            f"&locale={urllib.parse.quote(locale)}"
        )

        last_err: Optional[str] = None
        for attempt in range(self._max_retries):
            self._limiter.acquire()
            token = self._get_token()
            headers = {
                "Authorization": f"Bearer {token}",
                "Accept-Encoding": "gzip",
                "Accept": "application/json",
            }
            with self._stats_lock:
                self.http_requests += 1
            try:
                status, resp_headers, body = self._transport(
                    "GET", url, headers, None, self._timeout
                )
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last_err = f"network error ({type(exc).__name__}) on {path}"
                if attempt + 1 < self._max_retries:
                    with self._stats_lock:
                        self.http_retries += 1
                    time.sleep(min(8.0, 0.6 * (2**attempt)))
                    continue
                raise RuntimeError(f"Blizzard static API failed: {last_err}") from None

            if status == 200:
                return 200, _decode_json_body(resp_headers, body)
            if status == 404:
                return 404, None
            if status == 401 and attempt + 1 < self._max_retries:
                # Force token refresh without exposing token details
                with self._token_lock:
                    self._token = None
                    self._token_expires_at = 0.0
                with self._stats_lock:
                    self.http_retries += 1
                continue
            if status in (429, 500, 502, 503, 504) and attempt + 1 < self._max_retries:
                retry_after = resp_headers.get("retry-after", "")
                delay = 0.75 * (2**attempt)
                if retry_after.isdigit():
                    delay = max(delay, min(15.0, float(retry_after)))
                with self._stats_lock:
                    self.http_retries += 1
                time.sleep(delay)
                continue
            raise RuntimeError(
                f"Blizzard static API request failed (HTTP {status}) for {path}"
            )
        raise RuntimeError(f"Blizzard static API failed after retries: {last_err}")


# ---------------------------------------------------------------------------
# Compact Normalization of Blizzard Static API Payloads
# ---------------------------------------------------------------------------


def compact_api_recipe(
    raw: Dict[str, Any],
    prof_key: str,
    prof_id: int,
    prof_name: str,
    tier_id: int,
    category_name: str,
) -> Dict[str, Any]:
    crafted = raw.get("crafted_item")
    crafted_out = None
    if isinstance(crafted, dict):
        cid = _extract_id_from_entry(crafted)
        if cid is not None and cid > 0:
            crafted_out = {
                "id": int(cid),
                "name": _extract_localized_name(crafted.get("name")),
            }

    cq = raw.get("crafted_quantity")
    yield_info: Dict[str, Any] = {"value": 1, "min": 1, "max": 1, "is_range": False}
    if isinstance(cq, dict):
        if "value" in cq and cq["value"] is not None:
            v = cq["value"]
            v_num = int(v) if float(v).is_integer() else float(v)
            yield_info = {"value": v_num, "min": v_num, "max": v_num, "is_range": False}
        elif "minimum" in cq or "maximum" in cq:
            lo = int(cq.get("minimum", cq.get("maximum", 1)) or 1)
            hi = int(cq.get("maximum", lo) or lo)
            mid_f = (lo + hi) / 2.0
            mid: Any = int(mid_f) if mid_f.is_integer() else mid_f
            yield_info = {"value": mid, "min": lo, "max": hi, "is_range": lo != hi}

    reagents_out: List[Dict[str, Any]] = []
    for rg in raw.get("reagents") or []:
        if not isinstance(rg, dict):
            continue
        r_obj = rg.get("reagent")
        if not isinstance(r_obj, dict):
            continue
        rid = _extract_id_from_entry(r_obj)
        qty = int(rg.get("quantity", 1) or 1)
        if rid is not None and rid > 0:
            reagents_out.append(
                {
                    "id": int(rid),
                    "name": _extract_localized_name(r_obj.get("name")),
                    "quantity": qty,
                }
            )

    return {
        "id": int(raw.get("id", 0) or 0),
        "name": _extract_localized_name(raw.get("name")),
        "prof": prof_key,
        "prof_id": int(prof_id),
        "prof_name": prof_name,
        "tier_id": int(tier_id),
        "category": category_name,
        "crafted_item": crafted_out,
        "yield": yield_info,
        "reagents": reagents_out,
        "description": _extract_localized_name(raw.get("description")),
    }


def compute_vendor_unit_buy(purchase_price: int, purchase_quantity: int) -> Tuple[int, bool]:
    """Compute per-unit vendor buy price with half-up rounding and exact-divisibility flag.

    Tier-1 Trust Rule:
      - Exact division (`pp % pq == 0`) -> `is_exact_div = True` (auto-apply safe when > 0).
      - Fractional stack (`pp % pq != 0`, e.g. 200-stack ammo `3030` Razor Arrow `300/200 = 1.5c`)
        -> half-up rounded `(pp + pq // 2) // pq` (`2c`), `is_exact_div = False` (held `safe=False`
        so `apply-safe` never floors `1.5c` to `1c`).
    """
    pp = int(purchase_price or 0)
    pq = max(1, int(purchase_quantity or 1))
    is_exact_div = (pp % pq) == 0
    unit_buy = (pp + (pq // 2)) // pq
    return unit_buy, is_exact_div


def compact_api_item(raw: Dict[str, Any]) -> Dict[str, Any]:
    preview = raw.get("preview_item") if isinstance(raw.get("preview_item"), dict) else {}
    binding_obj = preview.get("binding") if isinstance(preview.get("binding"), dict) else {}
    binding_type = str(binding_obj.get("type") or "").strip() or None

    purchase_price = int(raw.get("purchase_price", 0) or 0)
    purchase_quantity = max(1, int(raw.get("purchase_quantity", 1) or 1))
    unit_buy, is_exact_div = compute_vendor_unit_buy(purchase_price, purchase_quantity)
    sell_price = int(raw.get("sell_price", 0) or 0)

    item_class = raw.get("item_class") if isinstance(raw.get("item_class"), dict) else {}
    item_subclass = raw.get("item_subclass") if isinstance(raw.get("item_subclass"), dict) else {}
    quality = raw.get("quality") if isinstance(raw.get("quality"), dict) else {}

    return {
        "id": int(raw.get("id", 0) or 0),
        "name": _extract_localized_name(raw.get("name")),
        "sell_price": sell_price,
        "purchase_price": purchase_price,
        "purchase_quantity": purchase_quantity,
        "unit_purchase_price": unit_buy,
        "unit_purchase_exact": is_exact_div,
        "bop": binding_type == "ON_ACQUIRE",
        "binding": binding_type,
        "is_stackable": bool(raw.get("is_stackable", False)),
        "is_equippable": bool(raw.get("is_equippable", False)),
        "quality": str(quality.get("type") or ""),
        "level": int(raw.get("level", 0) or 0),
        "required_level": int(raw.get("required_level", 0) or 0),
        "item_class": _extract_localized_name(item_class.get("name")),
        "item_subclass": _extract_localized_name(item_subclass.get("name")),
        "crafting_reagent": bool(preview.get("crafting_reagent", False)),
    }


# ---------------------------------------------------------------------------
# Static Cache Loader / Saver & Parallel Fetcher
# ---------------------------------------------------------------------------


def _atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    os.replace(tmp, path)


def load_static_cache(cache_path: Path, region: str, refresh: bool) -> Dict[str, Any]:
    empty: Dict[str, Any] = {
        "schema_version": CACHE_SCHEMA_VERSION,
        "region": region,
        "namespace": f"static-forever-{region}",
        "updated_at": "",
        "professions": [],
        "skill_tiers": {},
        "recipes": {},
        "items": {},
    }
    if refresh or not cache_path.is_file():
        return empty
    try:
        data = json.loads(cache_path.read_text(encoding="utf-8"))
        if (
            isinstance(data, dict)
            and data.get("schema_version") == CACHE_SCHEMA_VERSION
            and data.get("region") == region
        ):
            data.setdefault("professions", [])
            data.setdefault("skill_tiers", {})
            data.setdefault("recipes", {})
            data.setdefault("items", {})
            return data
    except Exception:
        pass
    return empty


def fetch_static_catalog(
    client: BlizzardForeverStaticClient,
    local_catalog: LocalCatalog,
    cache_path: Path,
    region: str,
    refresh: bool = False,
    workers: int = DEFAULT_WORKERS,
    progress_cb: Optional[Callable[[str], None]] = None,
) -> Tuple[Dict[str, Any], Dict[str, int]]:
    """Fetch professions, skill-tiers, all unique recipes, and all needed items."""
    safe_workers = max(1, min(MAX_WORKERS, int(workers)))
    cache = load_static_cache(cache_path, region=region, refresh=refresh)
    stats = {
        "api_requests": 0,
        "api_retries": 0,
        "recipes_from_cache": 0,
        "recipes_fetched_live": 0,
        "recipes_not_found": 0,
        "items_from_cache": 0,
        "items_fetched_live": 0,
        "items_not_found": 0,
    }

    def log(msg: str) -> None:
        if progress_cb is not None:
            progress_cb(msg)

    # 1. Professions + skill tiers
    if refresh or not cache.get("professions") or not cache.get("skill_tiers"):
        log(f"Fetching /data/wow/profession/index ({client.namespace})...")
        status, idx_payload = client.static_get("/data/wow/profession/index")
        if status != 200 or not isinstance(idx_payload, dict):
            raise RuntimeError("Failed to fetch /data/wow/profession/index")

        professions_list: List[Dict[str, Any]] = []
        skill_tiers_map: Dict[str, Any] = {}
        for entry in idx_payload.get("professions") or []:
            if not isinstance(entry, dict):
                continue
            pid = _extract_id_from_entry(entry)
            pname = _extract_localized_name(entry.get("name"))
            if pid is None or pid in IGNORED_PROFESSION_IDS or "[DNT]" in pname.upper():
                continue
            pkey = prof_key_from_api(pid, pname)
            p_status, p_detail = client.static_get(f"/data/wow/profession/{pid}")
            if p_status != 200 or not isinstance(p_detail, dict):
                continue
            tiers_out: List[Dict[str, Any]] = []
            for tier_entry in p_detail.get("skill_tiers") or []:
                if not isinstance(tier_entry, dict):
                    continue
                tid = _extract_id_from_entry(tier_entry)
                if tid is None:
                    continue
                t_status, t_detail = client.static_get(
                    f"/data/wow/profession/{pid}/skill-tier/{tid}"
                )
                if t_status != 200 or not isinstance(t_detail, dict):
                    continue
                cats_out: List[Dict[str, Any]] = []
                for cat in t_detail.get("categories") or []:
                    if not isinstance(cat, dict):
                        continue
                    cname = _extract_localized_name(cat.get("name"))
                    cat_recipes: List[Dict[str, Any]] = []
                    for r_entry in cat.get("recipes") or []:
                        if not isinstance(r_entry, dict):
                            continue
                        rid = _extract_id_from_entry(r_entry)
                        if rid is not None:
                            cat_recipes.append(
                                {
                                    "id": int(rid),
                                    "name": _extract_localized_name(r_entry.get("name")),
                                }
                            )
                    cats_out.append({"name": cname, "recipes": cat_recipes})
                t_key = f"{pid}:{tid}"
                skill_tiers_map[t_key] = {
                    "prof_id": int(pid),
                    "prof_key": pkey,
                    "prof_name": pname,
                    "tier_id": int(tid),
                    "tier_name": _extract_localized_name(t_detail.get("name")),
                    "categories": cats_out,
                }
                tiers_out.append({"id": int(tid), "name": _extract_localized_name(t_detail.get("name"))})
            professions_list.append(
                {
                    "id": int(pid),
                    "key": pkey,
                    "name": pname,
                    "skill_tiers": tiers_out,
                }
            )
        cache["professions"] = professions_list
        cache["skill_tiers"] = skill_tiers_map
        cache["updated_at"] = datetime.now(timezone.utc).isoformat()
        _atomic_write_json(cache_path, cache)
        log(f"Loaded {len(professions_list)} real professions from API.")
    else:
        log(f"Using cached professions ({len(cache['professions'])}) from {cache_path}.")

    # 2. Collect unique recipe IDs across all real professions
    recipe_meta: Dict[int, Tuple[str, int, str, int, str]] = {}
    for tier_data in cache["skill_tiers"].values():
        pkey = str(tier_data["prof_key"])
        pid = int(tier_data["prof_id"])
        pname = str(tier_data["prof_name"])
        tid = int(tier_data["tier_id"])
        for cat in tier_data.get("categories") or []:
            cname = str(cat.get("name") or "")
            for r_entry in cat.get("recipes") or []:
                rid = int(r_entry["id"])
                if rid not in recipe_meta:
                    recipe_meta[rid] = (pkey, pid, pname, tid, cname)

    recipes_cache: Dict[str, Any] = cache["recipes"]
    missing_recipe_ids: List[int] = []
    for rid in sorted(recipe_meta.keys()):
        if str(rid) in recipes_cache and not refresh:
            stats["recipes_from_cache"] += 1
        else:
            missing_recipe_ids.append(rid)

    if missing_recipe_ids:
        log(
            f"Fetching {len(missing_recipe_ids)} unique recipes "
            f"(workers={safe_workers}, cached={stats['recipes_from_cache']})..."
        )

        def _fetch_one_recipe(rid: int) -> Tuple[int, Dict[str, Any]]:
            status, payload = client.static_get(f"/data/wow/recipe/{rid}")
            if status == 404 or not isinstance(payload, dict):
                return rid, {"id": rid, "_not_found": True}
            pkey, pid, pname, tid, cname = recipe_meta[rid]
            return rid, compact_api_recipe(payload, pkey, pid, pname, tid, cname)

        completed = 0
        with ThreadPoolExecutor(max_workers=safe_workers) as pool:
            futs = [pool.submit(_fetch_one_recipe, rid) for rid in missing_recipe_ids]
            for fut in as_completed(futs):
                rid, compact = fut.result()
                recipes_cache[str(rid)] = compact
                if compact.get("_not_found"):
                    stats["recipes_not_found"] += 1
                else:
                    stats["recipes_fetched_live"] += 1
                completed += 1
                if completed % 500 == 0:
                    cache["updated_at"] = datetime.now(timezone.utc).isoformat()
                    _atomic_write_json(cache_path, cache)
                    log(f"  recipes progress: {completed}/{len(missing_recipe_ids)}")
        cache["updated_at"] = datetime.now(timezone.utc).isoformat()
        _atomic_write_json(cache_path, cache)

    # 3. Determine item IDs to fetch:
    #    ALL items in Data_Recipes.lua I(...) + any reagent / crafted_item IDs
    #    referenced by matched recipes (preliminary match uses fetched recipes!).
    api_recipes_valid: Dict[int, Dict[str, Any]] = {
        int(k): v
        for k, v in recipes_cache.items()
        if isinstance(v, dict) and not v.get("_not_found")
    }
    prelim_matches, _, _ = match_recipes(local_catalog.recipes, api_recipes_valid)

    item_ids_needed: Set[int] = set(local_catalog.items.keys())
    for m in prelim_matches:
        api_rec = api_recipes_valid[m["api_recipe_id"]]
        crafted = api_rec.get("crafted_item")
        if isinstance(crafted, dict) and crafted.get("id"):
            item_ids_needed.add(int(crafted["id"]))
        for rg in api_rec.get("reagents") or []:
            if rg.get("id"):
                item_ids_needed.add(int(rg["id"]))

    items_cache: Dict[str, Any] = cache["items"]
    missing_item_ids: List[int] = []
    for iid in sorted(item_ids_needed):
        if str(iid) in items_cache and not refresh:
            stats["items_from_cache"] += 1
        else:
            missing_item_ids.append(iid)

    if missing_item_ids:
        log(
            f"Fetching {len(missing_item_ids)} catalog & matched-recipe items "
            f"(workers={safe_workers}, cached={stats['items_from_cache']})..."
        )

        def _fetch_one_item(iid: int) -> Tuple[int, Dict[str, Any]]:
            status, payload = client.static_get(f"/data/wow/item/{iid}")
            if status == 404 or not isinstance(payload, dict):
                return iid, {"id": iid, "_not_found": True}
            return iid, compact_api_item(payload)

        completed = 0
        with ThreadPoolExecutor(max_workers=safe_workers) as pool:
            futs = [pool.submit(_fetch_one_item, iid) for iid in missing_item_ids]
            for fut in as_completed(futs):
                iid, compact = fut.result()
                items_cache[str(iid)] = compact
                if compact.get("_not_found"):
                    stats["items_not_found"] += 1
                else:
                    stats["items_fetched_live"] += 1
                completed += 1
                if completed % 500 == 0:
                    cache["updated_at"] = datetime.now(timezone.utc).isoformat()
                    _atomic_write_json(cache_path, cache)
                    log(f"  items progress: {completed}/{len(missing_item_ids)}")
        cache["updated_at"] = datetime.now(timezone.utc).isoformat()
        _atomic_write_json(cache_path, cache)

    stats["api_requests"] = client.http_requests
    stats["api_retries"] = client.http_retries
    return cache, stats


# ---------------------------------------------------------------------------
# Recipe Matching (Strictly NEVER recipe.id == spellID!)
# ---------------------------------------------------------------------------

_PUNCT_SPACE_RE = re.compile(r"\s*[:\-–—]\s*")
_NON_ALNUM_RE = re.compile(r"[^a-z0-9 ]+")
_WS_RE = re.compile(r"\s+")


def normalize_recipe_name(name: str) -> str:
    """Normalize recipe name for fallback matching across punctuation variants."""
    s = (name or "").strip().lower()
    s = s.replace("\u2019", "'").replace("\u2018", "'").replace("`", "'")
    s = _PUNCT_SPACE_RE.sub(" - ", s)
    s = s.replace("'", "")
    s = _NON_ALNUM_RE.sub(" ", s)
    return _WS_RE.sub(" ", s).strip()


def _reagent_id_set_local(rec: LocalRecipe) -> Set[int]:
    return {rid for rid, _ in rec.reagents}


def _reagent_id_set_api(api_rec: Dict[str, Any]) -> Set[int]:
    return {int(rg["id"]) for rg in (api_rec.get("reagents") or []) if rg.get("id")}


def _jaccard(a: Set[int], b: Set[int]) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _name_token_similarity(a: str, b: str) -> float:
    ta = set(normalize_recipe_name(a).split())
    tb = set(normalize_recipe_name(b).split())
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def _local_name_keys(rec: LocalRecipe) -> Set[str]:
    keys = {normalize_recipe_name(rec.name)}
    if rec.mp_name:
        keys.add(normalize_recipe_name(rec.mp_name))
    keys.discard("")
    return keys


def match_recipes(
    local_recipes: Sequence[LocalRecipe],
    api_recipes: Dict[int, Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], List[int], List[int]]:
    """Join Blizzard API recipes to Data_Recipes.lua recipes.

    Rules (per #50):
      1. NEVER join on `api_recipe.id == local.spell_id` (SkillLineAbilityID != spellID).
      2. Pass 1: `(prof, crafted_item.id)` primary join (disambiguated by name, then
         reagent Jaccard when multiple recipes output the same item, e.g. Transmutes).
      3. Pass 2: `(prof, normalized_name)` fallback (required for Enchanting where
         `crafted_item` is omitted, plus any item-ID drift).

    Returns:
      - matches: list of dicts `{local_idx, api_recipe_id, match_method, name_changed}`
      - unmatched_local_indices: list of indices into `local_recipes`
      - unmatched_api_ids: sorted list of unmatched API recipe IDs
    """
    api_profs: Set[str] = {
        str(r.get("prof") or "") for r in api_recipes.values() if r.get("prof")
    }

    matched_local: Set[int] = set()
    matched_api: Set[int] = set()
    matches: List[Dict[str, Any]] = []

    def record_match(l_idx: int, a_id: int, method: str) -> None:
        matched_local.add(l_idx)
        matched_api.add(a_id)
        loc = local_recipes[l_idx]
        api = api_recipes[a_id]
        api_norm = normalize_recipe_name(api.get("name", ""))
        name_changed = api_norm not in _local_name_keys(loc)
        matches.append(
            {
                "local_idx": l_idx,
                "api_recipe_id": a_id,
                "match_method": method,
                "name_changed": name_changed,
            }
        )

    # Pass 1: (prof, crafted_item.id)
    local_by_prof_item: Dict[Tuple[str, int], List[int]] = defaultdict(list)
    for idx, loc in enumerate(local_recipes):
        if loc.prof in api_profs and loc.output_item_id and not loc.is_enchant:
            local_by_prof_item[(loc.prof, loc.output_item_id)].append(idx)

    api_by_prof_item: Dict[Tuple[str, int], List[int]] = defaultdict(list)
    for aid, api in sorted(api_recipes.items()):
        crafted = api.get("crafted_item")
        if isinstance(crafted, dict) and crafted.get("id"):
            api_by_prof_item[(str(api["prof"]), int(crafted["id"]))].append(aid)

    for key in sorted(set(local_by_prof_item.keys()) & set(api_by_prof_item.keys())):
        l_list = [i for i in local_by_prof_item[key] if i not in matched_local]
        a_list = [a for a in api_by_prof_item[key] if a not in matched_api]
        if len(l_list) == 1 and len(a_list) == 1:
            record_match(l_list[0], a_list[0], "prof_output_item_id")
            continue

        # Prefer non-SoD API recipes over SEASON OF DISCOVERY clones when disambiguating
        non_sod_a = [
            a
            for a in a_list
            if str(api_recipes[a].get("category") or "").strip().upper() != "SEASON OF DISCOVERY"
        ]
        if non_sod_a and len(non_sod_a) < len(a_list):
            a_list = non_sod_a
            if len(l_list) == 1 and len(a_list) == 1:
                record_match(l_list[0], a_list[0], "prof_output_item_id")
                continue

        # Multiple recipes produce same item (e.g., Transmute: Earth/Undeath to Water)
        # Step 1a: exact normalized name match within the bucket
        for l_idx in list(l_list):
            if l_idx in matched_local:
                continue
            l_keys = _local_name_keys(local_recipes[l_idx])
            name_hits = [
                aid
                for aid in a_list
                if aid not in matched_api
                and normalize_recipe_name(api_recipes[aid].get("name", "")) in l_keys
            ]
            if len(name_hits) == 1:
                record_match(l_idx, name_hits[0], "prof_output_item_id+name")

        # Step 1b: if exactly 1 remains on each side, pair them
        rem_l = [i for i in l_list if i not in matched_local]
        rem_a = [a for a in a_list if a not in matched_api]
        if len(rem_l) == 1 and len(rem_a) == 1:
            record_match(rem_l[0], rem_a[0], "prof_output_item_id")
        elif rem_l and rem_a:
            # Step 1c: unambiguous best reagent Jaccard >= 0.5
            for l_idx in rem_l:
                if l_idx in matched_local:
                    continue
                l_set = _reagent_id_set_local(local_recipes[l_idx])
                scored = sorted(
                    (
                        (_jaccard(l_set, _reagent_id_set_api(api_recipes[aid])), aid)
                        for aid in rem_a
                        if aid not in matched_api
                    ),
                    key=lambda x: (-x[0], x[1]),
                )
                if scored and scored[0][0] >= 0.5:
                    if len(scored) == 1 or scored[0][0] > scored[1][0]:
                        record_match(l_idx, scored[0][1], "prof_output_item_id+reagents")

    # Pass 2: (prof, normalized_name) fallback
    local_by_prof_name: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for idx, loc in enumerate(local_recipes):
        if idx in matched_local or loc.prof not in api_profs:
            continue
        for nk in _local_name_keys(loc):
            local_by_prof_name[(loc.prof, nk)].append(idx)

    api_by_prof_name: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for aid, api in sorted(api_recipes.items()):
        if aid in matched_api:
            continue
        nk = normalize_recipe_name(api.get("name", ""))
        if nk:
            api_by_prof_name[(str(api["prof"]), nk)].append(aid)

    for key in sorted(set(local_by_prof_name.keys()) & set(api_by_prof_name.keys())):
        l_list = [i for i in local_by_prof_name[key] if i not in matched_local]
        a_list = [a for a in api_by_prof_name[key] if a not in matched_api]
        if not l_list or not a_list:
            continue
        non_sod_a = [
            a
            for a in a_list
            if str(api_recipes[a].get("category") or "").strip().upper() != "SEASON OF DISCOVERY"
        ]
        if non_sod_a and len(non_sod_a) < len(a_list):
            a_list = non_sod_a
        if len(l_list) == 1 and len(a_list) == 1:
            record_match(l_list[0], a_list[0], "prof_normalized_name")
            continue
        # Disambiguate duplicate names by reagent similarity
        for l_idx in l_list:
            if l_idx in matched_local:
                continue
            l_set = _reagent_id_set_local(local_recipes[l_idx])
            scored = sorted(
                (
                    (_jaccard(l_set, _reagent_id_set_api(api_recipes[aid])), aid)
                    for aid in a_list
                    if aid not in matched_api
                ),
                key=lambda x: (-x[0], x[1]),
            )
            if scored and (len(scored) == 1 or scored[0][0] > scored[1][0]):
                record_match(l_idx, scored[0][1], "prof_normalized_name+reagents")

    matches.sort(key=lambda m: (local_recipes[m["local_idx"]].line_no, m["api_recipe_id"]))
    unmatched_local = [i for i in range(len(local_recipes)) if i not in matched_local]
    unmatched_api = sorted(aid for aid in api_recipes.keys() if aid not in matched_api)
    return matches, unmatched_local, unmatched_api


# ---------------------------------------------------------------------------
# Drift Computation (All 7 Categories)
# ---------------------------------------------------------------------------


def _reagent_map_from_local(reagents: Sequence[Tuple[int, int]]) -> Dict[int, int]:
    out: Dict[int, int] = {}
    for rid, qty in reagents:
        out[int(rid)] = out.get(int(rid), 0) + int(qty)
    return out


def _reagent_map_from_api(reagents: Sequence[Dict[str, Any]]) -> Dict[int, int]:
    out: Dict[int, int] = {}
    for rg in reagents:
        rid = int(rg["id"])
        qty = int(rg["quantity"])
        out[rid] = out.get(rid, 0) + qty
    return out


def _item_name_lookup(
    item_id: int,
    local_catalog: LocalCatalog,
    api_items: Dict[int, Dict[str, Any]],
    fallback: str = "",
) -> str:
    if item_id in api_items and api_items[item_id].get("name"):
        return str(api_items[item_id]["name"])
    if item_id in local_catalog.items:
        return local_catalog.items[item_id].name
    return fallback or f"Item#{item_id}"


def _format_lua_reagents(reagents: Sequence[Tuple[int, int]]) -> str:
    parts = [f"{{{int(rid)},{int(qty)}}}" for rid, qty in reagents]
    return "{" + ",".join(parts) + "}"


def _build_new_recipe_lua_skeleton(api_rec: Dict[str, Any]) -> str:
    prof = str(api_rec["prof"])
    name = _escape_lua_string(str(api_rec["name"]))
    crafted = api_rec.get("crafted_item")
    out_part = f",i={int(crafted['id'])}" if isinstance(crafted, dict) and crafted.get("id") else ",ench=true"
    yinfo = api_rec.get("yield") or {"value": 1, "is_range": False}
    yval = yinfo.get("value", 1)
    c_part = f",c={yval}" if yval != 1 else ""
    r_pairs = [(int(rg["id"]), int(rg["quantity"])) for rg in (api_rec.get("reagents") or [])]
    r_lua = _format_lua_reagents(r_pairs)
    return (
        f'R({{idx=TODO_IDX,pk="{prof}",s=TODO_SPELL_ID{out_part},n={name}'
        f'{c_part},skill=TODO_SKILL,source="TODO",acq="TODO",r={r_lua}}})'
        f' -- api_recipe_id={api_rec["id"]}'
    )


# ---------------------------------------------------------------------------
# Tier-2 Liveness Evidence & New-Recipe Classification Gate
# ---------------------------------------------------------------------------

_PP_RECIPE_START_RE = re.compile(r"^ {16}\[(\d+)\]\s*=\s*\{\s*$")
_PP_RECIPE_END_RE = re.compile(r"^ {16}\},?\s*$")
_PP_ABILITY_RE = re.compile(r"^ {20}abilityID\s*=\s*(\d+)")
_PP_SEEN_START_RE = re.compile(r"^ {20}seen\s*=\s*\{(.*)$")
_OFA_SPELL_RE = re.compile(r"\{s=(\d+)\b")
_OFA_RI_RE = re.compile(r"\bri=(\d+)\b")
_OFA_ITEM_RE = re.compile(r"\bi=(\d+)\b")


def default_snapshots_db_path() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    base = Path(local_app_data) if local_app_data else Path.home()
    return base / "MerchantMaster" / "snapshots.sqlite3"


def load_liveness_evidence(
    profplanner_path: Optional[Path] = None,
    oneforall_prof_dir: Optional[Path] = None,
    snapshots_db_path: Optional[Path] = None,
) -> Dict[str, Any]:
    """Load optional local Forever liveness evidence (ProfPlanner, OneForAll, AH SQLite DB).

    Pure Python stdlib; all inputs are read-only and optional.
    """
    pp_by_ability: Dict[int, Dict[str, Any]] = {}
    ofa_by_spell: Dict[int, Dict[str, Any]] = {}
    ah_item_ids: Set[int] = set()
    sources_loaded: List[str] = []

    if profplanner_path and profplanner_path.is_file():
        in_recipes = False
        cur_spell: Optional[int] = None
        cur_ability: Optional[int] = None
        cur_seen = False
        for line in profplanner_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if not in_recipes:
                if line.strip() == "recipes = {":
                    in_recipes = True
                continue
            if line == "            }," or line == "            }":
                in_recipes = False
                cur_spell = None
                continue
            m_start = _PP_RECIPE_START_RE.match(line)
            if m_start:
                cur_spell = int(m_start.group(1))
                cur_ability = None
                cur_seen = False
                continue
            if cur_spell is not None:
                m_ab = _PP_ABILITY_RE.match(line)
                if m_ab:
                    cur_ability = int(m_ab.group(1))
                    continue
                m_seen = _PP_SEEN_START_RE.match(line)
                if m_seen:
                    rest = m_seen.group(1).strip()
                    cur_seen = not rest.startswith("}")
                    continue
                if _PP_RECIPE_END_RE.match(line):
                    if cur_ability is not None:
                        pp_by_ability[cur_ability] = {
                            "spell_id": cur_spell,
                            "seen": cur_seen,
                        }
                    cur_spell = None
                    cur_ability = None
                    cur_seen = False
        if pp_by_ability:
            sources_loaded.append("profplanner")

    if oneforall_prof_dir and oneforall_prof_dir.is_dir():
        for lua_path in sorted(oneforall_prof_dir.glob("*.lua")):
            if lua_path.name == "BossDrops.lua":
                continue
            for line in lua_path.read_text(encoding="utf-8", errors="replace").splitlines():
                m_s = _OFA_SPELL_RE.search(line)
                if not m_s:
                    continue
                sid = int(m_s.group(1))
                m_ri = _OFA_RI_RE.search(line)
                m_i = _OFA_ITEM_RE.search(line)
                ofa_by_spell[sid] = {
                    "spell_id": sid,
                    "recipe_item_id": int(m_ri.group(1)) if m_ri else None,
                    "output_item_id": int(m_i.group(1)) if m_i else None,
                }
        if ofa_by_spell:
            sources_loaded.append("oneforall")

    if snapshots_db_path and snapshots_db_path.is_file():
        conn = None
        try:
            conn = sqlite3.connect(f"file:{snapshots_db_path}?mode=ro", uri=True)
            cur = conn.cursor()
            for tbl in ("item_latest", "snapshots"):
                try:
                    for row in cur.execute(
                        f"SELECT DISTINCT item_id FROM {tbl} WHERE qty > 0 OR num_auctions > 0"
                    ):
                        ah_item_ids.add(int(row[0]))
                except sqlite3.OperationalError:
                    pass
            if ah_item_ids:
                sources_loaded.append("snapshots_db")
        except sqlite3.Error:
            pass
        finally:
            if conn is not None:
                conn.close()

    return {
        "has_external_evidence": bool(sources_loaded),
        "sources_loaded": sources_loaded,
        "pp_by_ability": pp_by_ability,
        "ofa_by_spell": ofa_by_spell,
        "ah_item_ids": ah_item_ids,
    }


def classify_new_api_recipe(
    api_rec: Dict[str, Any],
    liveness_evidence: Optional[Dict[str, Any]] = None,
) -> Tuple[str, str, Dict[str, Any]]:
    """Classify an API-only recipe into `excluded` vs `live_forever` (Tier-2 gate).

    Hard exclusions (always applied):
      - `category == "SEASON OF DISCOVERY"` (SoD DB2 bleed)
      - Any reagent whose name contains `"DEPRECATED"`

    When optional `liveness_evidence` (ProfPlanner / OneForAll / live AH SQLite DB)
    is supplied, any remaining recipe with zero AH craft activity, zero AH scroll
    activity, `pp_seen == False`, and no native Forever OneForAll scroll (`ri >= 200000`)
    is classified `excluded` (`unseen_dead`).
    """
    cat_name = str(api_rec.get("category") or "").strip()
    if cat_name.upper() == "SEASON OF DISCOVERY":
        return "excluded", "sod_category", {}

    for rg in api_rec.get("reagents") or []:
        if "DEPRECATED" in str(rg.get("name") or "").upper():
            return "excluded", "deprecated_reagent", {}

    if not liveness_evidence or not liveness_evidence.get("has_external_evidence"):
        return "live_forever", "candidate_unfiltered", {}

    rid = int(api_rec["id"])
    crafted = api_rec.get("crafted_item")
    crafted_id = int(crafted["id"]) if isinstance(crafted, dict) and crafted.get("id") else None

    pp_map = liveness_evidence.get("pp_by_ability") or {}
    ofa_map = liveness_evidence.get("ofa_by_spell") or {}
    ah_ids = liveness_evidence.get("ah_item_ids") or set()

    pp_entry = pp_map.get(rid)
    spell_id = int(pp_entry["spell_id"]) if isinstance(pp_entry, dict) and pp_entry.get("spell_id") else None
    pp_seen = bool(pp_entry.get("seen")) if isinstance(pp_entry, dict) else False
    ofa_entry = ofa_map.get(spell_id) if spell_id is not None else None
    ri = int(ofa_entry["recipe_item_id"]) if isinstance(ofa_entry, dict) and ofa_entry.get("recipe_item_id") else None

    ah_craft = bool(crafted_id is not None and crafted_id in ah_ids)
    ah_scroll = bool(ri is not None and ri in ah_ids)
    forever_ofa_scroll = bool(ofa_entry is not None and ri is not None and ri >= 200000)

    meta = {
        "spell_id": spell_id,
        "recipe_item_id": ri,
        "ah_craft": ah_craft,
        "ah_scroll": ah_scroll,
        "pp_seen": pp_seen,
    }
    if ah_craft or ah_scroll or pp_seen or forever_ofa_scroll:
        return "live_forever", "verified_live_forever", meta
    return "excluded", "unseen_dead", meta


def compute_drift_report(
    local_catalog: LocalCatalog,
    static_cache: Dict[str, Any],
    fetch_stats: Optional[Dict[str, int]] = None,
    liveness_evidence: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Compute all 7 drift categories between Data_Recipes.lua and static-forever API."""
    api_recipes: Dict[int, Dict[str, Any]] = {
        int(k): v
        for k, v in (static_cache.get("recipes") or {}).items()
        if isinstance(v, dict) and not v.get("_not_found")
    }
    api_items: Dict[int, Dict[str, Any]] = {
        int(k): v
        for k, v in (static_cache.get("items") or {}).items()
        if isinstance(v, dict) and not v.get("_not_found")
    }
    api_items_not_found: List[int] = sorted(
        int(k)
        for k, v in (static_cache.get("items") or {}).items()
        if isinstance(v, dict) and v.get("_not_found")
    )

    # Category 1, 2, 3: Item drifts
    item_sell_drifts: List[Dict[str, Any]] = []
    vendor_reagent_drifts: List[Dict[str, Any]] = []
    item_bop_drifts: List[Dict[str, Any]] = []
    items_checked = 0
    vendor_reagents_checked = 0

    for item_id in sorted(local_catalog.items.keys()):
        loc = local_catalog.items[item_id]
        api = api_items.get(item_id)
        if api is None:
            continue
        items_checked += 1

        # 1. Item vendor sell_price drift
        api_sell = int(api.get("sell_price", 0) or 0)
        if loc.sell is None:
            if api_sell > 0:
                item_sell_drifts.append(
                    {
                        "item_id": item_id,
                        "line_no": loc.line_no,
                        "name": loc.name,
                        "api_name": api.get("name", ""),
                        "local_sell": None,
                        "api_sell": api_sell,
                        "delta": api_sell,
                        "kind": "backfill",
                    }
                )
        elif loc.sell != api_sell:
            item_sell_drifts.append(
                {
                    "item_id": item_id,
                    "line_no": loc.line_no,
                    "name": loc.name,
                    "api_name": api.get("name", ""),
                    "local_sell": loc.sell,
                    "api_sell": api_sell,
                    "delta": api_sell - loc.sell,
                    "kind": "changed",
                }
            )

        # 2. Vendor reagent unit buy drift (ONLY items already marked vendor reagents)
        if loc.vendor_price is not None:
            vendor_reagents_checked += 1
            purchase_price = int(api.get("purchase_price", 0) or 0)
            purchase_qty = max(1, int(api.get("purchase_quantity", 1) or 1))
            api_unit_buy, is_exact_div = compute_vendor_unit_buy(purchase_price, purchase_qty)
            if api_unit_buy != loc.vendor_price:
                safe = (api_unit_buy > 0) and is_exact_div
                reason = (
                    "exact_divisible_vendor_reagent"
                    if safe
                    else (
                        "fractional_purchase_price_per_unit"
                        if not is_exact_div
                        else "non_positive_api_purchase_price"
                    )
                )
                vendor_reagent_drifts.append(
                    {
                        "item_id": item_id,
                        "line_no": loc.line_no,
                        "name": loc.name,
                        "api_name": api.get("name", ""),
                        "local_vendor_price": loc.vendor_price,
                        "api_purchase_price": purchase_price,
                        "api_purchase_quantity": purchase_qty,
                        "api_unit_buy": api_unit_buy,
                        "api_unit_buy_exact": round(purchase_price / purchase_qty, 4),
                        "is_exact_div": is_exact_div,
                        "delta": api_unit_buy - loc.vendor_price,
                        "safe_to_apply": safe,
                        "reason": reason,
                    }
                )

        # 3. Item bop (ON_ACQUIRE) drift
        api_bop = bool(api.get("bop", False))
        if api_bop != loc.bop:
            item_bop_drifts.append(
                {
                    "item_id": item_id,
                    "line_no": loc.line_no,
                    "name": loc.name,
                    "api_name": api.get("name", ""),
                    "local_bop": loc.bop,
                    "api_bop": api_bop,
                    "api_binding": api.get("binding"),
                }
            )

    # Recipe matching
    matches, unmatched_local_idxs, unmatched_api_ids = match_recipes(
        local_catalog.recipes, api_recipes
    )

    # Category 4 & 5: Matched recipe reagent & numMade drifts
    recipe_reagent_drifts: List[Dict[str, Any]] = []
    recipe_yield_drifts: List[Dict[str, Any]] = []
    matched_renamed: List[Dict[str, Any]] = []

    for m in matches:
        loc = local_catalog.recipes[m["local_idx"]]
        api = api_recipes[m["api_recipe_id"]]

        if m["name_changed"]:
            matched_renamed.append(
                {
                    "line_no": loc.line_no,
                    "idx": loc.idx,
                    "prof": loc.prof,
                    "spell_id": loc.spell_id,
                    "output_item_id": loc.output_item_id,
                    "local_name": loc.name,
                    "mp_name": loc.mp_name,
                    "api_recipe_id": api["id"],
                    "api_name": api["name"],
                    "match_method": m["match_method"],
                }
            )

        # 4. Reagents drift
        loc_rmap = _reagent_map_from_local(loc.reagents)
        api_rmap = _reagent_map_from_api(api.get("reagents") or [])
        if loc_rmap != api_rmap:
            added = [
                {
                    "id": rid,
                    "name": _item_name_lookup(rid, local_catalog, api_items),
                    "qty": api_rmap[rid],
                }
                for rid in sorted(api_rmap.keys() - loc_rmap.keys())
            ]
            removed = [
                {
                    "id": rid,
                    "name": _item_name_lookup(rid, local_catalog, api_items),
                    "qty": loc_rmap[rid],
                }
                for rid in sorted(loc_rmap.keys() - api_rmap.keys())
            ]
            qty_changed = [
                {
                    "id": rid,
                    "name": _item_name_lookup(rid, local_catalog, api_items),
                    "local_qty": loc_rmap[rid],
                    "api_qty": api_rmap[rid],
                }
                for rid in sorted(loc_rmap.keys() & api_rmap.keys())
                if loc_rmap[rid] != api_rmap[rid]
            ]
            api_reagents_ordered = [
                [int(rg["id"]), int(rg["quantity"])] for rg in (api.get("reagents") or [])
            ]
            missing_in_catalog = sorted(
                rid for rid in api_rmap.keys() if rid not in local_catalog.items
            )
            # Tier-2 Standard Trust Rule: NEVER auto-apply reagent removals (e.g., API omission bug
            # dropping 2324 Bleach on 6622 White Wedding Dress); require 2nd-source confirmation.
            if len(removed) > 0:
                reagent_safe = False
                reagent_reason = "reagent_removal_requires_second_source"
            elif len(missing_in_catalog) > 0:
                reagent_safe = False
                reagent_reason = "missing_reagent_item_ids_in_catalog"
            elif loc.has_mp_reagents:
                reagent_safe = False
                reagent_reason = "has_mpR_override"
            else:
                reagent_safe = True
                reagent_reason = (
                    "verified_quantity_update" if not added else "reagent_addition_in_catalog"
                )
            recipe_reagent_drifts.append(
                {
                    "line_no": loc.line_no,
                    "idx": loc.idx,
                    "prof": loc.prof,
                    "spell_id": loc.spell_id,
                    "output_item_id": loc.output_item_id,
                    "local_name": loc.name,
                    "api_recipe_id": api["id"],
                    "api_name": api["name"],
                    "match_method": m["match_method"],
                    "local_reagents": [[rid, qty] for rid, qty in loc.reagents],
                    "api_reagents": api_reagents_ordered,
                    "added": added,
                    "removed": removed,
                    "qty_changed": qty_changed,
                    "missing_reagent_item_ids": missing_in_catalog,
                    "safe_to_apply": reagent_safe,
                    "reason": reagent_reason,
                }
            )

        # 5. numMade (crafted_quantity) drift
        #    Skip enchants / recipes with no crafted_item: Blizzard's static API maps
        #    spell EffectBasePoints (e.g. +65 Spellpower) into crafted_quantity on
        #    enchants, which is stat magnitude, NOT crafted item yield.
        if loc.is_enchant or not api.get("crafted_item"):
            continue
        yinfo = api.get("yield") or {"value": 1, "min": 1, "max": 1, "is_range": False}
        api_val = yinfo.get("value", 1)
        is_range = bool(yinfo.get("is_range", False))
        api_min = yinfo.get("min", api_val)
        api_max = yinfo.get("max", api_val)
        # Skip synthetic mpOnly world-veins or 0-yield entries if somehow matched
        local_num = loc.num_made
        has_yield_drift = False
        if is_range:
            if not (api_min <= local_num <= api_max) or float(local_num) != float(api_val):
                has_yield_drift = True
        else:
            if float(local_num) != float(api_val):
                has_yield_drift = True

        if has_yield_drift:
            has_crafted_item = isinstance(api.get("crafted_item"), dict) and bool(
                api["crafted_item"].get("id")
            )
            yield_safe = (
                has_crafted_item
                and (not is_range)
                and isinstance(api_val, int)
                and not isinstance(api_val, bool)
            )
            yield_reason = (
                "exact_integer_yield"
                if yield_safe
                else (
                    "range_yield_requires_second_source"
                    if is_range
                    else "non_integer_or_missing_crafted_item"
                )
            )
            recipe_yield_drifts.append(
                {
                    "line_no": loc.line_no,
                    "idx": loc.idx,
                    "prof": loc.prof,
                    "spell_id": loc.spell_id,
                    "output_item_id": loc.output_item_id,
                    "local_name": loc.name,
                    "api_recipe_id": api["id"],
                    "api_name": api["name"],
                    "match_method": m["match_method"],
                    "local_num_made": local_num,
                    "api_yield": api_val,
                    "api_min": api_min,
                    "api_max": api_max,
                    "is_range": is_range,
                    "safe_to_apply": yield_safe,
                    "reason": yield_reason,
                }
            )

    # Category 6: Renamed / local-only recipes
    unmatched_api_by_prof: Dict[str, List[int]] = defaultdict(list)
    for aid in unmatched_api_ids:
        unmatched_api_by_prof[str(api_recipes[aid]["prof"])].append(aid)

    unmatched_possible_renames: List[Dict[str, Any]] = []
    unmatched_api_prof_local_only: List[Dict[str, Any]] = []
    non_api_local_only: List[Dict[str, Any]] = []

    for l_idx in unmatched_local_idxs:
        loc = local_catalog.recipes[l_idx]
        is_synthetic = (
            loc.prof in NON_API_PROFESSIONS
            or loc.any_char
            or (loc.mp_only and loc.source == "gather")
            or "(World Veins)" in loc.name
        )
        base_entry = {
            "line_no": loc.line_no,
            "idx": loc.idx,
            "mp_idx": loc.mp_idx,
            "prof": loc.prof,
            "spell_id": loc.spell_id,
            "output_item_id": loc.output_item_id,
            "name": loc.name,
            "mp_name": loc.mp_name,
            "mm_only": loc.mm_only,
            "mp_only": loc.mp_only,
            "source": loc.source,
        }
        if is_synthetic:
            non_api_local_only.append(base_entry)
            continue

        # Look for candidate Forever rename in unmatched API recipes of same prof
        candidates = unmatched_api_by_prof.get(loc.prof, [])
        l_rset = _reagent_id_set_local(loc)
        best_cand: Optional[Tuple[float, float, int]] = None
        for aid in candidates:
            api = api_recipes[aid]
            r_sim = _jaccard(l_rset, _reagent_id_set_api(api)) if l_rset else 0.0
            n_sim = _name_token_similarity(loc.name, api.get("name", ""))
            score = max(r_sim, n_sim * 0.9)
            if r_sim >= 0.67 or (r_sim >= 0.5 and n_sim >= 0.34) or n_sim >= 0.6:
                if best_cand is None or score > best_cand[0]:
                    best_cand = (score, r_sim, aid)

        if best_cand is not None:
            score, r_sim, aid = best_cand
            api = api_recipes[aid]
            unmatched_possible_renames.append(
                {
                    **base_entry,
                    "candidate_api_recipe_id": aid,
                    "candidate_api_name": api.get("name", ""),
                    "candidate_crafted_item_id": (
                        api["crafted_item"]["id"] if isinstance(api.get("crafted_item"), dict) else None
                    ),
                    "reagent_jaccard": round(r_sim, 3),
                    "score": round(score, 3),
                }
            )
        else:
            unmatched_api_prof_local_only.append(base_entry)

    # Category 7: New Forever recipes in API not yet in Data_Recipes.lua
    new_by_prof: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    new_live_by_prof: Counter = Counter()
    new_excluded_by_reason: Counter = Counter()
    for aid in unmatched_api_ids:
        api = api_recipes[aid]
        crafted = api.get("crafted_item")
        crafted_id = int(crafted["id"]) if isinstance(crafted, dict) and crafted.get("id") else None
        crafted_name = str(crafted.get("name") or "") if isinstance(crafted, dict) else ""
        reagents_list = [
            {
                "id": int(rg["id"]),
                "name": _item_name_lookup(
                    int(rg["id"]), local_catalog, api_items, fallback=str(rg.get("name") or "")
                ),
                "quantity": int(rg["quantity"]),
            }
            for rg in (api.get("reagents") or [])
        ]
        missing_items: List[int] = []
        if crafted_id is not None and crafted_id not in local_catalog.items:
            missing_items.append(crafted_id)
        for rg in reagents_list:
            if rg["id"] not in local_catalog.items:
                missing_items.append(rg["id"])

        classification, cls_reason, cls_meta = classify_new_api_recipe(api, liveness_evidence)
        if classification == "live_forever":
            new_live_by_prof[str(api["prof"])] += 1
        else:
            new_excluded_by_reason[cls_reason] += 1

        new_by_prof[str(api["prof"])].append(
            {
                "api_recipe_id": int(api["id"]),
                "name": str(api["name"]),
                "prof": str(api["prof"]),
                "category": str(api.get("category") or ""),
                "classification": classification,
                "classification_reason": cls_reason,
                "liveness": cls_meta,
                "crafted_item_id": crafted_id,
                "crafted_item_name": crafted_name,
                "yield": api.get("yield"),
                "reagents": reagents_list,
                "missing_catalog_item_ids": sorted(set(missing_items)),
                "lua_skeleton": _build_new_recipe_lua_skeleton(api),
            }
        )

    new_by_prof_sorted = {
        prof: sorted(entries, key=lambda e: (e["api_recipe_id"], e["name"]))
        for prof, entries in sorted(new_by_prof.items())
    }
    new_counts_by_prof = {prof: len(entries) for prof, entries in new_by_prof_sorted.items()}
    new_live_counts_by_prof = dict(sorted(new_live_by_prof.items()))
    new_excluded_reasons_dict = dict(sorted(new_excluded_by_reason.items()))

    # Per-profession breakdown
    api_prof_counts = Counter(str(r["prof"]) for r in api_recipes.values())
    local_prof_counts = Counter(r.prof for r in local_catalog.recipes)
    matched_prof_counts = Counter(local_catalog.recipes[m["local_idx"]].prof for m in matches)
    all_profs = sorted(set(api_prof_counts.keys()) | set(local_prof_counts.keys()))
    prof_summary = [
        {
            "prof": p,
            "api_recipes": api_prof_counts.get(p, 0),
            "local_recipes": local_prof_counts.get(p, 0),
            "matched_recipes": matched_prof_counts.get(p, 0),
            "new_in_api": new_counts_by_prof.get(p, 0),
        }
        for p in all_profs
    ]

    match_method_counts = Counter(m["match_method"] for m in matches)

    summary = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "region": static_cache.get("region", DEFAULT_BLIZZARD_REGION),
        "namespace": static_cache.get("namespace", ""),
        "catalog_path": str(local_catalog.path),
        "professions_in_api": len(static_cache.get("professions") or []),
        "api_recipes_total": len(api_recipes),
        "api_items_total": len(api_items),
        "api_items_not_found": len(api_items_not_found),
        "local_items_total": len(local_catalog.items),
        "local_items_checked": items_checked,
        "local_vendor_reagents_checked": vendor_reagents_checked,
        "local_recipes_total": len(local_catalog.recipes),
        "matched_recipes_total": len(matches),
        "match_methods": dict(sorted(match_method_counts.items())),
        "drifts": {
            "item_sell_price_total": len(item_sell_drifts),
            "item_sell_price_changed": sum(1 for d in item_sell_drifts if d["kind"] == "changed"),
            "item_sell_price_backfill": sum(1 for d in item_sell_drifts if d["kind"] == "backfill"),
            "vendor_reagent_buy_total": len(vendor_reagent_drifts),
            "vendor_reagent_buy_safe": sum(1 for d in vendor_reagent_drifts if d["safe_to_apply"]),
            "item_bop_total": len(item_bop_drifts),
            "recipe_reagent_total": len(recipe_reagent_drifts),
            "recipe_reagent_safe": sum(1 for d in recipe_reagent_drifts if d["safe_to_apply"]),
            "recipe_yield_total": len(recipe_yield_drifts),
            "recipe_yield_safe": sum(1 for d in recipe_yield_drifts if d["safe_to_apply"]),
            "matched_renamed_total": len(matched_renamed),
            "unmatched_possible_renames_total": len(unmatched_possible_renames),
            "unmatched_api_prof_local_only_total": len(unmatched_api_prof_local_only),
            "non_api_local_only_total": len(non_api_local_only),
            "new_forever_recipes_total": sum(new_counts_by_prof.values()),
            "new_forever_recipes_by_prof": new_counts_by_prof,
            "new_forever_live_candidates_total": sum(new_live_counts_by_prof.values()),
            "new_forever_live_candidates_by_prof": new_live_counts_by_prof,
            "new_forever_excluded_total": sum(new_excluded_reasons_dict.values()),
            "new_forever_excluded_by_reason": new_excluded_reasons_dict,
        },
        "liveness_sources": (
            list(liveness_evidence.get("sources_loaded") or [])
            if isinstance(liveness_evidence, dict)
            else []
        ),
        "fetch_stats": fetch_stats or {},
    }

    return {
        "schema_version": 1,
        "summary": summary,
        "professions_summary": prof_summary,
        "item_sell_price_drifts": item_sell_drifts,
        "vendor_reagent_buy_drifts": vendor_reagent_drifts,
        "item_bop_drifts": item_bop_drifts,
        "recipe_reagent_drifts": recipe_reagent_drifts,
        "recipe_yield_drifts": recipe_yield_drifts,
        "renamed_and_local_only": {
            "matched_renamed": matched_renamed,
            "unmatched_possible_renames": unmatched_possible_renames,
            "unmatched_api_prof_local_only": unmatched_api_prof_local_only,
            "non_api_local_only": non_api_local_only,
        },
        "new_forever_recipes": new_by_prof_sorted,
        "api_items_not_found": api_items_not_found,
    }


# ---------------------------------------------------------------------------
# Markdown Report Generator
# ---------------------------------------------------------------------------


def _fmt_copper(val: Optional[int]) -> str:
    if val is None:
        return "nil"
    return f"{int(val)}c"


def _fmt_reagents_short(pairs: Sequence[Sequence[int]]) -> str:
    return ", ".join(f"{int(r[0])}x{int(r[1])}" for r in pairs)


def render_markdown_report(report: Dict[str, Any]) -> str:
    s = report["summary"]
    d = s["drifts"]
    lines: List[str] = []

    lines.append("# Blizzard WoW: Forever Static Catalog Drift Report")
    lines.append("")
    lines.append(f"- **Generated:** `{s['generated_at']}`")
    lines.append(f"- **Namespace:** `{s['namespace']}` (region `{s['region']}`)")
    lines.append(f"- **Catalog:** `{s['catalog_path']}`")
    lines.append(
        f"- **API Coverage:** `{s['professions_in_api']}` real professions, "
        f"`{s['api_recipes_total']}` unique recipes, `{s['api_items_total']}` items fetched "
        f"(`{s['api_items_not_found']}` HTTP 404)"
    )
    lines.append(
        f"- **Local Coverage:** `{s['local_items_total']}` `I(...)` items "
        f"(`{s['local_items_checked']}` checked, `{s['local_vendor_reagents_checked']}` vendor reagents), "
        f"`{s['local_recipes_total']}` `R(...)` recipes (`{s['matched_recipes_total']}` matched)"
    )
    lines.append(
        f"- **Match Methods (strictly never `recipe.id == spellID`):** "
        + ", ".join(f"`{k}={v}`" for k, v in s["match_methods"].items())
    )
    lines.append("")

    # Executive Summary Table
    lines.append("## Drift Summary")
    lines.append("")
    lines.append("| Category | Count | Notes |")
    lines.append("|---|---:|---|")
    lines.append(
        f"| 1. Item vendor `sell_price` drift | **{d['item_sell_price_total']}** | "
        f"`{d['item_sell_price_changed']}` changed + `{d['item_sell_price_backfill']}` nil->positive backfill |"
    )
    lines.append(
        f"| 2. Vendor reagent unit `buy` drift | **{d['vendor_reagent_buy_total']}** | "
        f"`{d['vendor_reagent_buy_safe']}` exact-divisible safe (`pp % pq == 0`), vendor reagents only |"
    )
    lines.append(
        f"| 3. Item `bop` (`ON_ACQUIRE`) drift | **{d['item_bop_total']}** | "
        f"Verified against `preview_item.binding.type == ON_ACQUIRE` |"
    )
    lines.append(
        f"| 4. Matched recipe `reagents` drift | **{d['recipe_reagent_total']}** | "
        f"`{d['recipe_reagent_safe']}` safe (`removed` always held for 2nd-source confirmation) |"
    )
    lines.append(
        f"| 5. Matched recipe `numMade` drift | **{d['recipe_yield_total']}** | "
        f"`{d['recipe_yield_safe']}` exact-int safe (`is_range` & enchants never auto-applied) |"
    )
    lines.append(
        f"| 6. Renamed / local-only recipes | **{d['matched_renamed_total'] + d['unmatched_possible_renames_total'] + d['unmatched_api_prof_local_only_total']}** | "
        f"`{d['matched_renamed_total']}` matched renames, `{d['unmatched_possible_renames_total']}` possible renames, "
        f"`{d['unmatched_api_prof_local_only_total']}` other API-prof local-only (`{d['non_api_local_only_total']}` Poisons/Others/synthetic excluded) |"
    )
    lines.append(
        f"| 7. New Forever recipes in API | **{d['new_forever_recipes_total']}** | "
        f"`{d.get('new_forever_live_candidates_total', d['new_forever_recipes_total'])}` `live_forever` candidates, "
        f"`{d.get('new_forever_excluded_total', 0)}` `excluded` ({d.get('new_forever_excluded_by_reason', {})}) |"
    )
    lines.append("")

    # Per-Profession Coverage
    lines.append("## Per-Profession Recipe Coverage")
    lines.append("")
    lines.append("| Profession | API Unique | Local `R(...)` | Matched | New in API |")
    lines.append("|---|---:|---:|---:|---:|")
    for row in report["professions_summary"]:
        lines.append(
            f"| `{row['prof']}` | {row['api_recipes']} | {row['local_recipes']} | "
            f"{row['matched_recipes']} | {row['new_in_api']} |"
        )
    lines.append("")

    # 1. Item sell_price drift
    sell_drifts = report["item_sell_price_drifts"]
    lines.append(f"## 1. Item Vendor `sell_price` Drift ({len(sell_drifts)})")
    lines.append("")
    if not sell_drifts:
        lines.append("None.")
    else:
        lines.append("| Item ID | Line | Name | Local `sell` | API `sell_price` | Delta | Kind |")
        lines.append("|---:|---:|---|---:|---:|---:|---|")
        for row in sell_drifts[:120]:
            disp_name = row["name"] or f"_(nil -> {row['api_name']})_"
            lines.append(
                f"| `{row['item_id']}` | {row['line_no']} | {disp_name} | "
                f"{_fmt_copper(row['local_sell'])} | {_fmt_copper(row['api_sell'])} | "
                f"{row['delta']:+d}c | `{row['kind']}` |"
            )
        if len(sell_drifts) > 120:
            lines.append(f"\n_Showing first 120 of {len(sell_drifts)}; see JSON for full list._")
    lines.append("")

    # 2. Vendor reagent unit buy drift
    vbuy_drifts = report["vendor_reagent_buy_drifts"]
    lines.append(f"## 2. Vendor Reagent Unit `buy` Drift ({len(vbuy_drifts)})")
    lines.append("")
    if not vbuy_drifts:
        lines.append("None.")
    else:
        lines.append(
            "| Item ID | Line | Name | Local `vendorPrice` | API `purchase_price / qty` | Unit Buy | Safe |"
        )
        lines.append("|---:|---:|---|---:|---|---:|---|")
        for row in vbuy_drifts:
            disp_name = row["name"] or f"_(nil -> {row['api_name']})_"
            lines.append(
                f"| `{row['item_id']}` | {row['line_no']} | {disp_name} | "
                f"{row['local_vendor_price']}c | "
                f"{row['api_purchase_price']}c / {row['api_purchase_quantity']} | "
                f"{row['api_unit_buy']}c | `{row['safe_to_apply']}` |"
            )
    lines.append("")

    # 3. Item bop drift
    bop_drifts = report["item_bop_drifts"]
    lines.append(f"## 3. Item `bop` (`ON_ACQUIRE`) Drift ({len(bop_drifts)})")
    lines.append("")
    if not bop_drifts:
        lines.append("None.")
    else:
        lines.append("| Item ID | Line | Name | Local `bop` | API `bop` | API `binding` |")
        lines.append("|---:|---:|---|---|---|---|")
        for row in bop_drifts[:120]:
            disp_name = row["name"] or f"_(nil -> {row['api_name']})_"
            lines.append(
                f"| `{row['item_id']}` | {row['line_no']} | {disp_name} | "
                f"`{row['local_bop']}` | `{row['api_bop']}` | `{row['api_binding']}` |"
            )
        if len(bop_drifts) > 120:
            lines.append(f"\n_Showing first 120 of {len(bop_drifts)}; see JSON for full list._")
    lines.append("")

    # 4. Matched recipe reagents drift
    rg_drifts = report["recipe_reagent_drifts"]
    lines.append(f"## 4. Matched Recipe `reagents` Drift ({len(rg_drifts)})")
    lines.append("")
    if not rg_drifts:
        lines.append("None.")
    else:
        lines.append(
            "| Prof | Line | Recipe | API ID | Local Reagents | API Reagents | Safe | Reason |"
        )
        lines.append("|---|---:|---|---:|---|---|---|---|")
        for row in rg_drifts[:120]:
            reason = row.get("reason") or "-"
            lines.append(
                f"| `{row['prof']}` | {row['line_no']} | {row['local_name']} | "
                f"`{row['api_recipe_id']}` | `{_fmt_reagents_short(row['local_reagents'])}` | "
                f"`{_fmt_reagents_short(row['api_reagents'])}` | `{row['safe_to_apply']}` | `{reason}` |"
            )
        if len(rg_drifts) > 120:
            lines.append(f"\n_Showing first 120 of {len(rg_drifts)}; see JSON for full list._")
    lines.append("")

    # 5. Matched recipe numMade drift
    y_drifts = report["recipe_yield_drifts"]
    lines.append(f"## 5. Matched Recipe `numMade` (`crafted_quantity`) Drift ({len(y_drifts)})")
    lines.append("")
    if not y_drifts:
        lines.append("None.")
    else:
        lines.append("| Prof | Line | Recipe | API ID | Local `c` | API Yield | Range? | Safe |")
        lines.append("|---|---:|---|---:|---:|---|---|---|")
        for row in y_drifts:
            api_y = (
                f"{row['api_min']}..{row['api_max']} (mid {row['api_yield']})"
                if row["is_range"]
                else str(row["api_yield"])
            )
            lines.append(
                f"| `{row['prof']}` | {row['line_no']} | {row['local_name']} | "
                f"`{row['api_recipe_id']}` | {row['local_num_made']} | {api_y} | "
                f"`{row['is_range']}` | `{row['safe_to_apply']}` |"
            )
    lines.append("")

    # 6. Renamed / local-only recipes
    ren = report["renamed_and_local_only"]
    lines.append("## 6. Renamed & Local-Only Recipes")
    lines.append("")
    lines.append(f"### 6a. Confirmed Forever Renames (Matched by `(prof, outputItemID)`): {len(ren['matched_renamed'])}")
    lines.append("")
    if not ren["matched_renamed"]:
        lines.append("None.")
    else:
        lines.append("| Prof | Line | Output ID | Local Name | API Forever Name | API ID |")
        lines.append("|---|---:|---:|---|---|---:|")
        for row in ren["matched_renamed"][:80]:
            lines.append(
                f"| `{row['prof']}` | {row['line_no']} | `{row['output_item_id']}` | "
                f"{row['local_name']} | {row['api_name']} | `{row['api_recipe_id']}` |"
            )
        if len(ren["matched_renamed"]) > 80:
            lines.append(f"\n_Showing first 80 of {len(ren['matched_renamed'])}; see JSON._")
    lines.append("")

    lines.append(f"### 6b. Unmatched Possible Forever Renames: {len(ren['unmatched_possible_renames'])}")
    lines.append("")
    if not ren["unmatched_possible_renames"]:
        lines.append("None.")
    else:
        lines.append("| Prof | Line | Local Name | Candidate API Name | API ID | Reagent Jaccard |")
        lines.append("|---|---:|---|---|---:|---:|")
        for row in ren["unmatched_possible_renames"][:60]:
            lines.append(
                f"| `{row['prof']}` | {row['line_no']} | {row['name']} | "
                f"{row['candidate_api_name']} | `{row['candidate_api_recipe_id']}` | "
                f"{row['reagent_jaccard']:.2f} |"
            )
    lines.append("")

    lines.append(
        f"### 6c. Other Local-Only Recipes in API Professions: {len(ren['unmatched_api_prof_local_only'])}"
    )
    lines.append("")
    if not ren["unmatched_api_prof_local_only"]:
        lines.append("None.")
    else:
        lines.append("| Prof | Line | Spell ID | Output ID | Name | Flags |")
        lines.append("|---|---:|---:|---:|---|---|")
        for row in ren["unmatched_api_prof_local_only"][:60]:
            flags = ",".join(
                f for f, v in (("mmOnly", row["mm_only"]), ("mpOnly", row["mp_only"])) if v
            ) or "-"
            lines.append(
                f"| `{row['prof']}` | {row['line_no']} | `{row['spell_id']}` | "
                f"`{row['output_item_id']}` | {row['name']} | `{flags}` |"
            )
        if len(ren["unmatched_api_prof_local_only"]) > 60:
            lines.append(
                f"\n_Showing first 60 of {len(ren['unmatched_api_prof_local_only'])}; see JSON._"
            )
    lines.append("")

    non_api_counts = Counter(r["prof"] for r in ren["non_api_local_only"])
    lines.append(
        f"### 6d. Non-API & Synthetic Local-Only Recipes: {len(ren['non_api_local_only'])}"
    )
    lines.append("")
    lines.append(
        "Excluded from rename drift (absent from Blizzard static API by design): "
        + ", ".join(f"`{p}={c}`" for p, c in sorted(non_api_counts.items()))
    )
    lines.append("")

    # 7. New Forever recipes in API
    new_by_prof = report["new_forever_recipes"]
    lines.append(f"## 7. New Forever Recipes in API Not Yet in `Data_Recipes.lua` ({d['new_forever_recipes_total']})")
    lines.append("")
    lines.append("| Profession | Total API-Only | `live_forever` | `excluded` |")
    lines.append("|---|---:|---:|---:|")
    live_by_p = d.get("new_forever_live_candidates_by_prof") or {}
    for prof, cnt in sorted(d["new_forever_recipes_by_prof"].items()):
        live_c = int(live_by_p.get(prof, 0))
        excl_c = cnt - live_c
        lines.append(f"| `{prof}` | {cnt} | {live_c} | {excl_c} |")
    lines.append("")
    for prof, entries in sorted(new_by_prof.items()):
        live_entries = [e for e in entries if e.get("classification") == "live_forever"]
        lines.append(f"### `{prof}` (`{len(entries)}` total; `{len(live_entries)}` `live_forever`, `{len(entries) - len(live_entries)}` `excluded`)")
        lines.append("")
        lines.append("| API ID | Name | Class | Output Item | Yield | Reagents |")
        lines.append("|---:|---|---|---|---|---|")
        display_entries = live_entries + [e for e in entries if e.get("classification") != "live_forever"]
        for entry in display_entries[:25]:
            out_s = (
                f"`{entry['crafted_item_id']}` {entry['crafted_item_name']}"
                if entry["crafted_item_id"]
                else "_enchant/none_"
            )
            yinfo = entry.get("yield") or {"value": 1, "is_range": False}
            y_s = (
                f"{yinfo['min']}..{yinfo['max']}"
                if yinfo.get("is_range")
                else str(yinfo.get("value", 1))
            )
            rg_s = ", ".join(f"{rg['id']}x{rg['quantity']}" for rg in entry["reagents"]) or "-"
            cls_s = f"{entry.get('classification', 'live_forever')} ({entry.get('classification_reason', '-')})"
            lines.append(
                f"| `{entry['api_recipe_id']}` | {entry['name']} | `{cls_s}` | {out_s} | {y_s} | `{rg_s}` |"
            )
        if len(entries) > 25:
            lines.append(f"\n_Showing first 25 of {len(entries)}; full list + Lua skeletons in JSON._")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


# ---------------------------------------------------------------------------
# Safe Patcher (`apply-safe --dry-run | --apply`)
# ---------------------------------------------------------------------------


def _format_lua_val(val: Any) -> str:
    if val is None:
        return "nil"
    if val is True:
        return "true"
    if val is False:
        return "false"
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, str):
        return _escape_lua_string(val)
    if isinstance(val, dict):
        # Preserve compact Data_Recipes.lua table style: {n="...",s=123}
        parts = []
        for k, v in val.items():
            parts.append(f"{k}={_format_lua_val(v)}")
        return "{" + ",".join(parts) + "}"
    if isinstance(val, list):
        return "{" + ",".join(_format_lua_val(v) for v in val) + "}"
    raise ValueError(f"Unsupported Lua literal value: {val!r}")


def _patch_item_line(
    item: LocalItem,
    new_sell: Optional[int],
    new_vendor_price: Optional[int],
    new_bop: Optional[bool],
) -> str:
    """Rebuild a single I(...) line modifying ONLY verified safe fields."""
    indent_match = _ITEM_CALL_PREFIX_RE.match(item.raw_line)
    indent = indent_match.group(1) if indent_match else "\t"

    args = list(item.args_raw)
    while len(args) < 7:
        args.append(None)

    old_sell = item.sell
    old_vendor_price = item.vendor_price

    if new_sell is not None:
        args[2] = int(new_sell)
        # Keep mpFlag.s aligned if mpFlag is a dict with an explicit 's' field
        if isinstance(args[6], dict) and "s" in args[6]:
            mp_dict = dict(args[6])
            if mp_dict.get("s") == old_sell or mp_dict.get("s") is not None:
                mp_dict["s"] = int(new_sell)
            args[6] = mp_dict

    if new_vendor_price is not None:
        # Update vbuy (arg 5) and keep buy (arg 4) synced if vbuy was true or equaled old_vendor_price
        if args[4] is True:
            args[3] = int(new_vendor_price)
        else:
            args[4] = int(new_vendor_price)
            if args[3] == old_vendor_price:
                args[3] = int(new_vendor_price)

    if new_bop is not None:
        args[5] = True if new_bop else None

    # Trim trailing None args down to original arg_count (or min 1), matching Data_Recipes.lua style
    last_non_nil = 0
    for i in range(len(args) - 1, 0, -1):
        if args[i] is not None:
            last_non_nil = i
            break
    keep_len = max(last_non_nil + 1, min(item.arg_count, len(args)))
    while keep_len > 1 and keep_len > last_non_nil + 1 and args[keep_len - 1] is None:
        keep_len -= 1

    rendered_args = [_format_lua_val(a) for a in args[:keep_len]]
    return f"{indent}I({', '.join(rendered_args)})"


def _patch_recipe_line(
    rec: LocalRecipe,
    new_reagents: Optional[List[Tuple[int, int]]],
    new_num_made: Optional[int],
) -> str:
    """Patch only `r=...` and/or `c=...` inside an R({...}) line, preserving all other fields."""
    line = rec.raw_line
    edits: List[Tuple[int, int, str]] = []

    if new_reagents is not None:
        if "r" not in rec.value_spans:
            raise LuaParseError(f"Line {rec.line_no}: R(...) missing 'r=' span")
        r_start, r_end = rec.value_spans["r"]
        edits.append((r_start, r_end, _format_lua_reagents(new_reagents)))

    if new_num_made is not None:
        if "c" in rec.value_spans:
            c_start, c_end = rec.value_spans["c"]
            edits.append((c_start, c_end, str(int(new_num_made))))
        elif int(new_num_made) != 1:
            # Insert `,c=<val>` right after `skill=...` (or `n=...` fallback)
            anchor_key = "skill" if "skill" in rec.entry_spans else "n"
            if anchor_key not in rec.entry_spans:
                raise LuaParseError(f"Line {rec.line_no}: cannot find anchor to insert c=")
            pos = rec.entry_spans[anchor_key][1]
            edits.append((pos, pos, f",c={int(new_num_made)}"))

    # Apply edits from right to left so earlier character spans remain exact
    edits.sort(key=lambda e: (e[0], e[1]), reverse=True)
    for start, end, repl in edits:
        line = line[:start] + repl + line[end:]
    return line


def check_bad_glyphs(text: str) -> List[str]:
    bad: List[str] = []
    for line_no, line in enumerate(text.splitlines(), 1):
        for ch in line:
            if ord(ch) >= 128 and ch not in ALLOWED_NON_ASCII_GLYPHS:
                bad.append(f"line {line_no}: U+{ord(ch):04X} ({ch!r})")
    return bad


def apply_safe_patches(
    catalog_path: Path,
    report: Dict[str, Any],
    include_recipes: bool = False,
    apply_write: bool = False,
) -> Dict[str, Any]:
    """Compute (and optionally write) zero-data-loss patches to Data_Recipes.lua."""
    local_catalog = parse_data_recipes(catalog_path)
    raw_bytes = catalog_path.read_bytes()
    has_bom = raw_bytes.startswith(b"\xef\xbb\xbf")
    text = (raw_bytes[3:] if has_bom else raw_bytes).decode("utf-8")
    had_trailing_newline = text.endswith("\n")
    lines = text.splitlines()

    # Collect item-level safe patches
    item_sell_updates: Dict[int, int] = {}
    for row in report.get("item_sell_price_drifts") or []:
        iid = int(row["item_id"])
        if iid in local_catalog.items:
            item_sell_updates[iid] = int(row["api_sell"])

    item_vbuy_updates: Dict[int, int] = {}
    vbuy_skipped_unsafe = 0
    for row in report.get("vendor_reagent_buy_drifts") or []:
        if not row.get("safe_to_apply", False):
            vbuy_skipped_unsafe += 1
            continue
        iid = int(row["item_id"])
        if iid in local_catalog.items and local_catalog.items[iid].vendor_price is not None:
            item_vbuy_updates[iid] = int(row["api_unit_buy"])

    item_bop_updates: Dict[int, bool] = {}
    for row in report.get("item_bop_drifts") or []:
        iid = int(row["item_id"])
        if iid in local_catalog.items:
            item_bop_updates[iid] = bool(row["api_bop"])

    patched_lines = list(lines)
    counts = {
        "item_lines_changed": 0,
        "sell_price_patched": 0,
        "vendor_reagent_patched": 0,
        "vendor_reagent_skipped_unsafe": vbuy_skipped_unsafe,
        "bop_patched": 0,
        "recipe_lines_changed": 0,
        "recipe_reagents_patched": 0,
        "recipe_yield_patched": 0,
        "recipe_reagents_skipped_unsafe": 0,
        "recipe_yield_skipped_unsafe": 0,
    }

    affected_item_ids = sorted(
        set(item_sell_updates.keys())
        | set(item_vbuy_updates.keys())
        | set(item_bop_updates.keys())
    )
    for iid in affected_item_ids:
        item = local_catalog.items[iid]
        new_sell = item_sell_updates.get(iid)
        new_vbuy = item_vbuy_updates.get(iid)
        new_bop = item_bop_updates.get(iid)
        new_line = _patch_item_line(item, new_sell, new_vbuy, new_bop)
        if new_line != patched_lines[item.line_no - 1]:
            patched_lines[item.line_no - 1] = new_line
            counts["item_lines_changed"] += 1
            if new_sell is not None:
                counts["sell_price_patched"] += 1
            if new_vbuy is not None:
                counts["vendor_reagent_patched"] += 1
            if new_bop is not None:
                counts["bop_patched"] += 1

    # Optionally collect recipe-level safe patches
    if include_recipes:
        recipes_by_line = {r.line_no: r for r in local_catalog.recipes}
        reagent_updates: Dict[int, List[Tuple[int, int]]] = {}
        yield_updates: Dict[int, int] = {}

        for row in report.get("recipe_reagent_drifts") or []:
            if not row.get("safe_to_apply", False):
                counts["recipe_reagents_skipped_unsafe"] += 1
                continue
            lno = int(row["line_no"])
            if lno in recipes_by_line:
                reagent_updates[lno] = [(int(r[0]), int(r[1])) for r in row["api_reagents"]]

        for row in report.get("recipe_yield_drifts") or []:
            if not row.get("safe_to_apply", False):
                counts["recipe_yield_skipped_unsafe"] += 1
                continue
            lno = int(row["line_no"])
            if lno in recipes_by_line:
                yield_updates[lno] = int(row["api_yield"])

        for lno in sorted(set(reagent_updates.keys()) | set(yield_updates.keys())):
            rec = recipes_by_line[lno]
            new_r = reagent_updates.get(lno)
            new_c = yield_updates.get(lno)
            new_line = _patch_recipe_line(rec, new_r, new_c)
            if new_line != patched_lines[lno - 1]:
                patched_lines[lno - 1] = new_line
                counts["recipe_lines_changed"] += 1
                if new_r is not None:
                    counts["recipe_reagents_patched"] += 1
                if new_c is not None:
                    counts["recipe_yield_patched"] += 1

    new_text = local_catalog.line_ending.join(patched_lines)
    if had_trailing_newline:
        new_text += local_catalog.line_ending

    bad_glyphs = check_bad_glyphs(new_text)
    if bad_glyphs:
        raise RuntimeError(f"Refusing patch: BAD_GLYPHS={len(bad_glyphs)} ({bad_glyphs[:5]})")

    diff_lines = list(
        difflib.unified_diff(
            lines,
            patched_lines,
            fromfile=f"a/{catalog_path.name}",
            tofile=f"b/{catalog_path.name}",
            lineterm="",
            n=1,
        )
    )

    wrote_file = False
    if apply_write and new_text != text:
        # Validate round-trip parse before committing to disk
        tmp = catalog_path.with_suffix(catalog_path.suffix + ".audit_tmp")
        tmp.write_bytes(new_text.encode("utf-8"))
        try:
            reparsed = parse_data_recipes(tmp)
            if len(reparsed.items) != len(local_catalog.items) or len(reparsed.recipes) != len(
                local_catalog.recipes
            ):
                raise RuntimeError(
                    "Round-trip verification failed: item/recipe count changed unexpectedly"
                )
            os.replace(tmp, catalog_path)
            wrote_file = True
        finally:
            if tmp.exists():
                tmp.unlink()

    return {
        "mode": "apply" if apply_write else "dry-run",
        "catalog_path": str(catalog_path),
        "wrote_file": wrote_file,
        "include_recipes": include_recipes,
        "bad_glyphs": len(bad_glyphs),
        "counts": counts,
        "diff_lines": diff_lines,
    }


# ---------------------------------------------------------------------------
# CLI Entrypoints
# ---------------------------------------------------------------------------


def cmd_audit(args: argparse.Namespace) -> int:
    region = (args.region or DEFAULT_BLIZZARD_REGION).strip().lower()
    catalog_path = Path(args.catalog).resolve()
    out_dir = Path(args.out_dir).resolve()
    cache_path = Path(args.cache_file).resolve() if args.cache_file else default_cache_path()
    workers = max(1, min(MAX_WORKERS, int(args.workers)))
    rate = max(1.0, min(MAX_RATE_PER_SEC, float(args.rate)))

    if not catalog_path.is_file():
        print(f"ERROR: Catalog file not found: {catalog_path}", file=sys.stderr)
        return 2

    local_catalog = parse_data_recipes(catalog_path)
    print(
        f"Parsed {catalog_path.name}: {len(local_catalog.items)} I(...) items, "
        f"{len(local_catalog.recipes)} R(...) recipes."
    )

    creds = get_blizzard_credentials()
    if creds is None:
        print(
            "ERROR: Missing BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET "
            "(checked os.environ and HKCU\\Environment).",
            file=sys.stderr,
        )
        return 2

    client = BlizzardForeverStaticClient(
        client_id=creds[0],
        client_secret=creds[1],
        region=region,
        rate_per_sec=rate,
    )

    t0 = time.monotonic()
    static_cache, fetch_stats = fetch_static_catalog(
        client=client,
        local_catalog=local_catalog,
        cache_path=cache_path,
        region=region,
        refresh=bool(args.refresh),
        workers=workers,
        progress_cb=lambda msg: print(msg, flush=True),
    )
    elapsed = round(time.monotonic() - t0, 2)
    fetch_stats["elapsed_seconds"] = elapsed  # type: ignore[assignment]

    liveness_evidence: Optional[Dict[str, Any]] = None
    if not getattr(args, "no_liveness_gate", False):
        addons_root = MM_ROOT.parent
        pp_path = (
            Path(args.profplanner).resolve()
            if getattr(args, "profplanner", "")
            else addons_root / "ProfPlanner" / "CommunityData.lua"
        )
        ofa_dir = (
            Path(args.oneforall).resolve()
            if getattr(args, "oneforall", "")
            else addons_root / "OneForAll" / "Data" / "Professions"
        )
        snap_db = (
            Path(args.snapshots_db).resolve()
            if getattr(args, "snapshots_db", "")
            else default_snapshots_db_path()
        )
        liveness_evidence = load_liveness_evidence(
            profplanner_path=pp_path,
            oneforall_prof_dir=ofa_dir,
            snapshots_db_path=snap_db,
        )

    report = compute_drift_report(
        local_catalog,
        static_cache,
        fetch_stats=fetch_stats,
        liveness_evidence=liveness_evidence,
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "blizzard_catalog_drift.json"
    md_path = out_dir / "blizzard_catalog_drift_report.md"
    _atomic_write_json(json_path, report)
    md_path.write_text(render_markdown_report(report), encoding="utf-8")

    s = report["summary"]
    d = s["drifts"]
    print("")
    print("=== Blizzard Static Catalog Audit Complete ===")
    print(f"Elapsed:                {elapsed}s (HTTP reqs={fetch_stats['api_requests']}, retries={fetch_stats['api_retries']})")
    print(f"API professions:        {s['professions_in_api']}")
    print(f"API recipes fetched:    {s['api_recipes_total']}")
    print(f"API items fetched:      {s['api_items_total']} (404={s['api_items_not_found']})")
    print(f"Local recipes matched:  {s['matched_recipes_total']} / {s['local_recipes_total']}")
    print(f"1. Item sell drifts:    {d['item_sell_price_total']} (changed={d['item_sell_price_changed']}, backfill={d['item_sell_price_backfill']})")
    print(f"2. Vendor buy drifts:   {d['vendor_reagent_buy_total']} (safe={d['vendor_reagent_buy_safe']})")
    print(f"3. Item BoP drifts:     {d['item_bop_total']}")
    print(f"4. Recipe reagent:      {d['recipe_reagent_total']} (safe={d['recipe_reagent_safe']})")
    print(f"5. Recipe yield:        {d['recipe_yield_total']} (safe={d['recipe_yield_safe']})")
    print(f"6. Renamed/local-only:  matched_renamed={d['matched_renamed_total']}, possible_renames={d['unmatched_possible_renames_total']}, other_local={d['unmatched_api_prof_local_only_total']}, non_api={d['non_api_local_only_total']}")
    print(
        f"7. New Forever recipes: {d['new_forever_recipes_total']} "
        f"(live_forever={d.get('new_forever_live_candidates_total', 0)}, "
        f"excluded={d.get('new_forever_excluded_total', 0)}, "
        f"by_prof={d['new_forever_recipes_by_prof']})"
    )
    print(f"Cache file:             {cache_path}")
    print(f"JSON report:            {json_path}")
    print(f"Markdown report:        {md_path}")
    return 0


def cmd_apply_safe(args: argparse.Namespace) -> int:
    catalog_path = Path(args.catalog).resolve()
    report_path = Path(args.report).resolve()
    if not catalog_path.is_file():
        print(f"ERROR: Catalog file not found: {catalog_path}", file=sys.stderr)
        return 2
    if not report_path.is_file():
        print(f"ERROR: Drift report JSON not found: {report_path}", file=sys.stderr)
        return 2

    report = json.loads(report_path.read_text(encoding="utf-8"))
    apply_write = bool(args.apply) and not bool(args.dry_run)
    res = apply_safe_patches(
        catalog_path=catalog_path,
        report=report,
        include_recipes=bool(args.include_recipes),
        apply_write=apply_write,
    )
    c = res["counts"]
    print(f"=== apply-safe ({res['mode']}) ===")
    print(f"Catalog:                {res['catalog_path']}")
    print(f"Wrote file:             {res['wrote_file']}")
    print(f"Include recipes:        {res['include_recipes']}")
    print(f"BAD_GLYPHS:             {res['bad_glyphs']}")
    print(
        f"Item lines changed:     {c['item_lines_changed']} "
        f"(sell={c['sell_price_patched']}, vendor_reagent={c['vendor_reagent_patched']}, "
        f"skipped_vendor_reagent={c.get('vendor_reagent_skipped_unsafe', 0)}, bop={c['bop_patched']})"
    )
    print(
        f"Recipe lines changed:   {c['recipe_lines_changed']} "
        f"(reagents={c['recipe_reagents_patched']}, yield={c['recipe_yield_patched']}, "
        f"skipped_reagents={c['recipe_reagents_skipped_unsafe']}, skipped_yield={c['recipe_yield_skipped_unsafe']})"
    )

    diff_lines = res["diff_lines"]
    max_diff = int(args.max_diff_lines)
    if diff_lines:
        print("")
        print(f"--- Unified Diff ({len(diff_lines)} lines total; showing up to {max_diff}) ---")
        for dl in diff_lines[:max_diff]:
            print(dl)
        if len(diff_lines) > max_diff:
            print(f"... ({len(diff_lines) - max_diff} more diff lines truncated) ...")
    else:
        print("No changes required.")
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Blizzard Official WoW: Forever Static Catalog Verifier & Safe Importer"
    )
    sub = p.add_subparsers(dest="command", required=True)

    p_audit = sub.add_parser("audit", help="Audit Data_Recipes.lua against static-forever API")
    p_audit.add_argument("--region", default=DEFAULT_BLIZZARD_REGION, help="Blizzard region (default: eu)")
    p_audit.add_argument("--catalog", default=str(DEFAULT_CATALOG_PATH), help="Path to Data_Recipes.lua")
    p_audit.add_argument(
        "--out-dir",
        default=str(MM_ROOT / "tools" / "dist"),
        help="Output directory for JSON and Markdown drift reports",
    )
    p_audit.add_argument("--cache-file", default="", help="Override static_catalog_cache.json path")
    p_audit.add_argument("--refresh", action="store_true", help="Ignore cache and refetch from Blizzard API")
    p_audit.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help=f"Concurrent fetch threads (capped at {MAX_WORKERS})",
    )
    p_audit.add_argument(
        "--rate",
        type=float,
        default=DEFAULT_RATE_PER_SEC,
        help=f"Polite max requests/sec (capped at {MAX_RATE_PER_SEC})",
    )
    p_audit.add_argument(
        "--profplanner",
        default="",
        help="Optional path to ProfPlanner\\CommunityData.lua for Tier-2 liveness gate",
    )
    p_audit.add_argument(
        "--oneforall",
        default="",
        help="Optional path to OneForAll\\Data\\Professions directory for Tier-2 liveness gate",
    )
    p_audit.add_argument(
        "--snapshots-db",
        default="",
        help="Optional path to snapshots.sqlite3 for Tier-2 live AH gate",
    )
    p_audit.add_argument(
        "--no-liveness-gate",
        action="store_true",
        help="Disable external ProfPlanner/OneForAll/AH liveness classification (SoD/DEPRECATED still excluded)",
    )
    p_audit.set_defaults(func=cmd_audit)

    p_apply = sub.add_parser(
        "apply-safe",
        help="Safely patch verified zero-data-loss fields in Data_Recipes.lua (--dry-run default)",
    )
    mode = p_apply.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Preview unified diff without writing (default)")
    mode.add_argument("--apply", action="store_true", help="Write verified safe patches to Data_Recipes.lua")
    p_apply.add_argument("--report", required=True, help="Path to blizzard_catalog_drift.json")
    p_apply.add_argument("--catalog", default=str(DEFAULT_CATALOG_PATH), help="Path to Data_Recipes.lua")
    p_apply.add_argument(
        "--include-recipes",
        action="store_true",
        help="Also patch verified matched recipe reagents and exact yields",
    )
    p_apply.add_argument(
        "--max-diff-lines",
        type=int,
        default=120,
        help="Max unified diff lines to print (default: 120)",
    )
    p_apply.set_defaults(func=cmd_apply_safe)

    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
