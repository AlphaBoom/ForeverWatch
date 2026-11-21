# ForeverWatch

**English** | [简体中文](README_zh.md)

**Hostile Player Threat Monitor & Player Tagging Addon for World of Warcraft: Forever (`1.60.1` / Interface `16001`)**

ForeverWatch automatically monitors nearby hostile players, escalates threat & nemesis levels based on attacks and kills, warns you with multi-enemy stacked screen banners and a lockable floating radar panel, and lets you tag both friendly and hostile players from right-click menus across the entire UI.

---

## Features

### 1. Automatic Hostile Threat & Nemesis Monitor
- **Dynamic Threat Escalation**:
  - **Lv.1 Dangerous**: Hostile player attacks a friendly player
  - **Lv.2 High Threat**: 1–2 ally kills
  - **Lv.3 Bloodthirsty**: 3–4 ally kills
  - **Lv.4 Butcher**: 5–9 ally kills
  - **Lv.5 Nightmare**: 10+ ally kills
  - **Nemesis**: Automatically flagged via `C_DeathRecap` and combat tracking whenever a hostile player kills you (stacks with kill tiers)
- **Multi-Enemy Stacked Alert Banners**:
  - Up to 3 simultaneous stacked banners sorted by threat priority (Nemesis always on top), clickable to target the hostile player directly
  - Overflow summary bar when 4+ hostile threats trigger at once, plus 1.5s sound throttling and adjustable banner duration (`2s–15s`)
- **Lockable Floating Radar Panel**:
  - Fixed max height (top 8 highest-threat nearby hostiles + overflow counter), right-click to target directly (even when locked), adjustable auto-clear timeout (`3s–60s`), and throttled updates for large-scale PvP clashes
  - **Lock Mode**: Click the header padlock (or `/fw lock`) to make the panel semi-transparent (adjustable `20%–100%`), disable dragging/menus, and keep right-click targeting active
- **PvP Kill & Death Statistics (`/fw stats`)**:
  - Tracks hostile players slain and deaths to hostile players (Forever 16001 safe), overall K/D ratio, kill streaks (current & best), session vs. lifetime stats, visual win/loss ratio bar, opponent leaderboard, and chronological combat log
  - Click any row across **Threats / Nemesis**, **Player Tags**, and **Kill Stats** (or via the radar menu) to open a detailed view with opponent level, class, realm, full notes/tags, and per-opponent encounter history

### 2. Player Tagging System
- **Right-Click Context Menus Everywhere**:
  - Works on unit portraits, target/focus frames, party/raid frames, guild/communities roster, chat names, Friends List, Battle.net Friends, Recent Allies, and hostile players (1-click **Add/Edit Tag** + 1-click **Mark Nemesis**)
- **Multi-Location Display**:
  - **Tooltip**: HD marker icon beside player name + colored tags, notes, and hostile threat stats (supports world units, Friends List, and Recent Allies)
  - **Chat Frame**: Displays colored tags directly beside sender names via native `ChatFrameUtil.AddSenderNameFilter`
  - **NamePlates**: Compact marker icon beside player names (compatible with Blizzard default nameplates and BetterBlizzPlates)
- **Customizable & Localized**:
  - 4 built-in HD marker icon styles (`Pin`, `Note`, `Pencil`, `Star`), 7 tag colors, customizable quick-preset tags
  - Full localization: **English**, **简体中文**, **繁體中文** (auto-follow client or switch manually in settings)

---

## Slash Commands

| Command | Description |
| --- | --- |
| `/fw` | Open the ForeverWatch Manager & Settings window |
| `/fw stats` | Open the PvP Kill & Death Statistics tab |
| `/fw radar` | Show or hide the nearby hostile radar panel |
| `/fw lock` | Lock or unlock the floating radar panel |
| `/fw tag [Name]` | Tag current target or specified player |
| `/fw nemesis [Name]` | Manually mark target or specified hostile player as Nemesis |
| `/fw lang [auto\|enUS\|zhCN\|zhTW]` | Switch addon language |
| `/fw test [multi]` | Preview single or multi-enemy alert banners |

---

## Installation

1. Download the latest `ForeverWatch-v*.zip` from [GitHub Releases](https://github.com/AlphaBoom/ForeverWatch/releases).
2. Extract the `ForeverWatch` folder into:
   ```text
   World of Warcraft\_forever_\Interface\AddOns\ForeverWatch
   ```
3. Launch World of Warcraft: Forever and enable **ForeverWatch** in the AddOns menu.
