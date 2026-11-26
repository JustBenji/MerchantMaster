# Changelog

All notable player-facing changes to **MerchantMaster** are documented in this file.

## v3.3.0 — Initial Standalone Public Release (WoW Forever `16001`)

### Standalone Live Auction House & First-Run Experience
*   **Full Standalone Mode:** All headline views—**Dashboard (Daily Velocity Crafts)**, **Profit Spread**, **Gap Sniper**, **Vendor Sniper**, **Outliers**, **All Recipes**, **Craftsman's Writs**, **Waylaid Crates**, **Professor 1-300 Leveling**, **MM Sell**, and **Analytics Ledger**—work directly from in-game Live AH scans with zero external setup or third-party addon dependencies.
*   **Live AH Velocity & Baseline Pricing:** Added local scan-pair velocity (`Sales / Day` from scans spaced 15+ minutes apart) feeding **Profit Spread**, Dashboard daily profit estimates, and **Professor** Smart Mode, plus median historical reference pricing (`ahDaily` / `ahHistory`) powering **Gap Sniper**.
*   **Clear Cold-Start & First-Scan Guidance:** Replaced misleading ready indicators on empty profiles with an amber **No AH Scan Yet** header status, an explicit **Scan AH** button, a dismissible 2-step Dashboard onboarding card (including an option to disable auto-opening at the Auction House), and clear warm-up guidance in **Gap Sniper** and **Profit Spread** until 2+ scans are recorded.
*   **Slash Help & Blizzard Settings:** Added `/mm help` (and `/mm ?`), helpful usage hints on unknown `/mm` arguments, and updated Blizzard **Options > AddOns > MerchantMaster** controls and command reference.

### Visual Polish, Fonts & Localization
*   **Bundled Static `Inter` Font (`SIL OFL 1.1`):** Unified typography across all panels on unmodified official `Inter-Regular.ttf` and `Inter-SemiBold.ttf`, with automatic `STANDARD_TEXT_FONT` fallback on non-Latin game clients (`ruRU`, `koKR`, `zhCN`, `zhTW`) and refined spacing across **Goblin Baron** KPI cards and table headers.
*   **UI Skins & Table Styles:** Set **Goblin Baron** as the default skin and signature style, with **Human**, **Night Elf**, **Orc**, **Undead**, and **Modern Glass** (Dark/Light) available as extra optional themes alongside table styles (**Ruled Lines**, **Deep Well**, and **Card Strips**) and optimized textures for faster loading and smaller downloads.

### Privacy, Performance & Extensibility
*   **Privacy-Safe Debug Bundle:** **Console -> Perf & Debug -> Generate Debug Bundle** now enables **Redact Names** by default, masking character and realm names for safe sharing in bug reports while reporting live addon version and WoW Forever build metadata.
*   **Clean SavedVariables & Reduced Reload Overhead:** Simplified SavedVariables to `MerchantMasterDB` and `MerchantMasterLedgerDB` (with lossless one-time migration of existing Professor leveling settings), ensuring fresh installs start completely empty.
*   **Versioned Companion API (`MerchantMasterAPI` v1):** Added clean, opt-in extension hooks (`RegisterSnapshotExtension`, `RegisterMapPins`) so optional local companions stay cleanly decoupled while standalone players see zero inactive clutter.
