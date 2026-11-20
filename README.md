# ForeverWatch

**Hostile Player Monitor & Player Tagging Addon for World of Warcraft: Forever (`1.60.1` / Interface `16001`)**

ForeverWatch automatically monitors nearby hostile players in World of Warcraft: Forever, escalates danger & nemesis tiers based on attacks and kills, displays stacked screen alerts and a lockable floating radar panel, and lets you tag both friendly and hostile players directly from right-click menus.

---

## Features

### Hostile Threat & Nemesis Monitoring
- **Automatic Threat Escalation**:
  - **Lv.1 Dangerous**: Hostile player attacks a friendly player
  - **Lv.2 High Threat**: 1–2 ally kills
  - **Lv.3 Bloodthirsty**: 3–4 ally kills
  - **Lv.4 Butcher**: 5–9 ally kills
  - **Lv.5 Nightmare**: 10+ ally kills
  - **Nemesis**: Automatically flagged via `C_DeathRecap` & combat tracking whenever a hostile player kills you (stacks with kill tiers)
- **Multi-Enemy Stacked Alert Banners**:
  - Up to 3 simultaneous stacked alert banners sorted by threat priority (Nemesis always on top)
  - Overflow summary bar for 4+ simultaneous threats + 1.5s sound throttling
- **Lockable Floating Radar Panel**:
  - Capped height (top 8 highest-threat nearby enemies + overflow counter) and throttled for large-scale PvP clashes
  - One-click **Lock mode**: becomes click-through with adjustable opacity (`20%–100%`) and hides other header buttons so you never misclick in combat

### Player Tagging System
- **Right-Click Context Menus Everywhere**: Tag players from unit portraits, target/focus frames, party/raid frames, guild/communities roster, chat names, Friends List, Recent Allies, and hostile player menus (1-click tag + 1-click mark Nemesis).
- **Rich Display Locations**:
  - **Tooltip**: Marker icon beside player name + colored tags, detailed notes, and hostile threat stats (works on world units, Friends List, and Recent Allies)
  - **Chat Frame**: Appends colored tags directly beside sender names via native `ChatFrameUtil.AddSenderNameFilter`
  - **NamePlates**: Compact marker icon beside player names (compatible with both Blizzard default nameplates and BetterBlizzPlates)
- **Customizable**: 4 built-in HD marker icon styles, 7 tag colors, customizable quick-preset tag chips, and full localization (**English / 简体中文 / 繁體中文**).

---

## Slash Commands

| Command | Description |
| --- | --- |
| `/fw` | Open the ForeverWatch Manager & Settings window |
| `/fw radar` | Show or hide the nearby hostile radar panel |
| `/fw lock` | Lock or unlock the floating radar panel |
| `/fw tag [Name]` | Tag current target or specified player |
| `/fw nemesis [Name]` | Manually mark target or specified hostile player as Nemesis |
| `/fw lang [auto\|enUS\|zhCN\|zhTW]` | Switch UI language |
| `/fw test [multi]` | Preview single or multi-enemy alert banners |

---

## 简介（中文）

专为 **魔兽世界 Forever (`1.60.1` / Interface `16001`)** 打造的**敌情自动监控 + 玩家标签**插件：
- **自动监控周围敌对玩家**：攻击我方自动记为危险人物，击杀我方按击杀人数逐级升级，击杀自己自动标记为【仇人】，支持多人并发堆叠横幅预警、音效节流与可锁定半透明（透明度 20%–100% 可调）的附近敌情雷达。
- **全场景右键打标签**：支持右键头像、队友/团员、好友/最近盟友（Recent Allies）、公会、聊天名字以及敌对玩家（支持一键打标签与一键记仇人），并在 **Tooltip、聊天栏、姓名板**（兼容 `BetterBlizzPlates`）多端展示。
- **完整三语支持**：内置 `简体中文 / 繁體中文 / English`，支持跟随客户端或设置内手动切换。

---

## Installation

1. Download or clone the `ForeverWatch` folder into:
   ```text
   World of Warcraft\_forever_\Interface\AddOns\ForeverWatch
   ```
2. Enable **ForeverWatch** in the AddOns list and log in.
