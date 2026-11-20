local ADDON_NAME, FW = ...
_G.ForeverWatch = FW
local L = FW.L

FW.version = "1.1.0"
FW.prefix = "|cffFFD100[Forever|r|cffFF4444Watch]|r "

-- Selectable crisp tag badge icon styles (HD Forever 16001 atlases & textures)
FW.TAG_ICON_STYLES = {
    { id = "PIN",    nameKey = "ICON_PIN",    name = L.ICON_PIN,    atlas = "friendslist-recentallies-pin-yellow" },
    { id = "NOTE",   nameKey = "ICON_NOTE",   name = L.ICON_NOTE,   texture = "Interface\\FriendsFrame\\UI-FriendsFrame-Note" },
    { id = "PENCIL", nameKey = "ICON_PENCIL", name = L.ICON_PENCIL, atlas = "Pencil-Icon" },
    { id = "STAR",   nameKey = "ICON_STAR",   name = L.ICON_STAR,   atlas = "auctionhouse-icon-favorite" },
}

FW.ICONS = {
    EDIT_TAG     = { atlas = "Pencil-Icon" },
    NEMESIS      = { atlas = "icons_16x16_deadly" },
    DANGER_SWORD = { atlas = "countdown-swords" },
}

function FW.GetTagIconDef()
    local styleId = FW.settings and FW.settings.tagIconStyle or "PIN"
    for _, s in ipairs(FW.TAG_ICON_STYLES) do
        if s.id == styleId then
            return s
        end
    end
    return FW.TAG_ICON_STYLES[1]
end

function FW.ApplyIconToTexture(tex, iconDef)
    if not tex or not iconDef then return end
    if iconDef.atlas then
        tex:SetAtlas(iconDef.atlas, false)
    elseif iconDef.texture then
        tex:SetTexture(iconDef.texture)
    end
end

function FW.GetIconMarkup(iconDef, size)
    size = size or 14
    if not iconDef then return "" end
    if iconDef.atlas then
        if CreateAtlasMarkup then
            return CreateAtlasMarkup(iconDef.atlas, size, size)
        end
        return string.format("|A:%s:%d:%d|a", iconDef.atlas, size, size)
    elseif iconDef.texture then
        return string.format("|T%s:%d:%d:0:0|t", iconDef.texture, size, size)
    end
    return ""
end

function FW.GetTagIconMarkup(size)
    return FW.GetIconMarkup(FW.GetTagIconDef(), size or 14)
end

function FW.GetEditIconMarkup(size)
    return FW.GetIconMarkup(FW.ICONS.EDIT_TAG, size or 14)
end

function FW.GetEnemyIconMarkup(isNemesis, size)
    return FW.GetIconMarkup(isNemesis and FW.ICONS.NEMESIS or FW.ICONS.DANGER_SWORD, size or 14)
end

-- Preset tag color options
FW.TAG_COLORS = {
    { id = "GOLD",   nameKey = "COLOR_GOLD",   name = L.COLOR_GOLD,   hex = "FFD100", r = 1.00, g = 0.82, b = 0.00 },
    { id = "GREEN",  nameKey = "COLOR_GREEN",  name = L.COLOR_GREEN,  hex = "4CFF6B", r = 0.30, g = 1.00, b = 0.42 },
    { id = "CYAN",   nameKey = "COLOR_CYAN",   name = L.COLOR_CYAN,   hex = "33E5FF", r = 0.20, g = 0.90, b = 1.00 },
    { id = "BLUE",   nameKey = "COLOR_BLUE",   name = L.COLOR_BLUE,   hex = "55AAFF", r = 0.33, g = 0.67, b = 1.00 },
    { id = "PURPLE", nameKey = "COLOR_PURPLE", name = L.COLOR_PURPLE, hex = "C77DFF", r = 0.78, g = 0.49, b = 1.00 },
    { id = "ORANGE", nameKey = "COLOR_ORANGE", name = L.COLOR_ORANGE, hex = "FF8C24", r = 1.00, g = 0.55, b = 0.14 },
    { id = "RED",    nameKey = "COLOR_RED",    name = L.COLOR_RED,    hex = "FF4444", r = 1.00, g = 0.27, b = 0.27 },
}

FW.DEFAULT_PRESET_TAGS = L.PRESET_TAGS

-- Danger tiers sorted from lowest to highest
FW.DANGER_TIERS = {
    [1] = { level = 1, nameKey = "TIER_1", name = L.TIER_1, minKills = 0,  hex = "FFAA00", r = 1.00, g = 0.67, b = 0.00, sound = "MAP_PING" },
    [2] = { level = 2, nameKey = "TIER_2", name = L.TIER_2, minKills = 1,  hex = "FF5500", r = 1.00, g = 0.33, b = 0.00, sound = "READY_CHECK" },
    [3] = { level = 3, nameKey = "TIER_3", name = L.TIER_3, minKills = 3,  hex = "FF2222", r = 1.00, g = 0.13, b = 0.13, sound = "RAID_WARNING" },
    [4] = { level = 4, nameKey = "TIER_4", name = L.TIER_4, minKills = 5,  hex = "DC143C", r = 0.86, g = 0.08, b = 0.24, sound = "RAID_WARNING" },
    [5] = { level = 5, nameKey = "TIER_5", name = L.TIER_5, minKills = 10, hex = "FF0066", r = 1.00, g = 0.00, b = 0.40, sound = "ALARM_CLOCK_WARNING_3" },
}

FW.NEMESIS_STYLE = {
    name = L.NEMESIS,
    hex = "E040FB",
    r = 0.88, g = 0.25, b = 0.98,
    sound = "ALARM_CLOCK_WARNING_3",
}

function FW.RefreshLocalizedTables()
    for _, s in ipairs(FW.TAG_ICON_STYLES) do
        s.name = L[s.nameKey]
    end
    for _, c in ipairs(FW.TAG_COLORS) do
        c.name = L[c.nameKey]
    end
    for _, t in ipairs(FW.DANGER_TIERS) do
        t.name = L[t.nameKey]
    end
    FW.NEMESIS_STYLE.name = L.NEMESIS
    FW.DEFAULT_PRESET_TAGS = L.PRESET_TAGS
end

FW.DEFAULTS = {
    settings = {
        language            = "AUTO",
        enableMonitor       = true,
        enableSound         = true,
        enableBanner        = true,
        enableRadar         = true,
        radarLocked         = false,
        radarLockedAlpha    = 0.55,
        radarShowNormalEnemy = false,
        radarCollapsed      = false,
        radarPoint          = nil,
        bannerPoint         = nil,
        enableTooltipTags   = true,
        enableChatTags      = true,
        enableNameplateIcon = true,
        tagIconStyle        = "PIN",
        alertCooldown       = 45,
        presetTags          = nil,
    },
    enemies = {},      -- [normalizedKey] = enemyRecord
    tags = {},         -- [normalizedKey] = tagRecord
    guidToKey = {},    -- [guid] = normalizedKey
}

-- Runtime caches (not saved)
FW.shortNameToEnemyKey = {}
FW.shortNameToTagKey = {}
FW.nearbyEnemies = {}    -- [key] = live enemy snapshot
FW.myKey = nil
FW.myShortName = nil
FW.myRealm = nil

-- ============================================================
-- Secret Value Safety Helpers (Forever 16001 / 12.x Engine)
-- ============================================================

function FW.IsSecret(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then
        return true
    end
    if type(val) == "table" and issecrettable and issecrettable(val) then
        return true
    end
    return false
end

function FW.CanAccess(val)
    if val == nil then return false end
    if FW.IsSecret(val) then return false end
    if canaccessvalue and not canaccessvalue(val) then
        return false
    end
    return true
end

function FW.SafeUnitCall(fn, ...)
    local ok, r1, r2, r3 = pcall(fn, ...)
    if not ok then return nil end
    if FW.IsSecret(r1) then return nil end
    if FW.IsSecret(r2) then r2 = nil end
    if FW.IsSecret(r3) then r3 = nil end
    return r1, r2, r3
end

function FW.SafeBool(val)
    if FW.IsSecret(val) then return false end
    return val == true
end

-- ============================================================
-- String & Player Key Normalization
-- ============================================================

function FW.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(FW.prefix .. tostring(msg))
    end
end

function FW.Trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

function FW.GetMyRealm()
    if FW.myRealm and FW.myRealm ~= "" then
        return FW.myRealm
    end
    local r = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName() or ""
    r = r:gsub("%s+", "")
    if r ~= "" then
        FW.myRealm = r
    end
    return r
end

function FW.SplitNameRealm(rawName, explicitRealm)
    if not FW.CanAccess(rawName) or type(rawName) ~= "string" then
        return nil, nil
    end
    -- Strip color/escape sequences if any leaked in
    local clean = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    clean = FW.Trim(clean)
    if clean == "" then return nil, nil end

    local name, realm = clean:match("^([^%-]+)%-(.+)$")
    if not name then
        name = clean
        realm = explicitRealm
    end
    if not FW.CanAccess(realm) or type(realm) ~= "string" or realm == "" then
        realm = FW.GetMyRealm()
    else
        realm = realm:gsub("%s+", "")
    end
    return name, realm
end

function FW.NormalizePlayerKey(rawName, explicitRealm)
    local name, realm = FW.SplitNameRealm(rawName, explicitRealm)
    if not name or name == "" then return nil, nil, nil end
    local key = (realm and realm ~= "") and (name .. "-" .. realm) or name
    return key, name, realm
end

function FW.GetShortName(keyOrName)
    if not FW.CanAccess(keyOrName) or type(keyOrName) ~= "string" then return "" end
    return keyOrName:match("^([^%-]+)") or keyOrName
end

function FW.GetDisplayName(keyOrName)
    local short, realm = FW.SplitNameRealm(keyOrName)
    if not short then return tostring(keyOrName or "") end
    local myRealm = FW.GetMyRealm()
    if realm and realm ~= "" and myRealm ~= "" and realm ~= myRealm then
        return short .. "-" .. realm
    end
    return short
end

function FW.GetUnitIdentity(unit)
    if not unit or not FW.SafeBool(FW.SafeUnitCall(UnitExists, unit)) then
        return nil
    end
    local name, realm = FW.SafeUnitCall(UnitName, unit)
    if not name or name == "" or name == UNKNOWNOBJECT then
        return nil
    end
    local key, shortName, normRealm = FW.NormalizePlayerKey(name, realm)
    if not key then return nil end
    local guid = FW.SafeUnitCall(UnitGUID, unit)
    local _, classFile = FW.SafeUnitCall(UnitClass, unit)
    local level = FW.SafeUnitCall(UnitLevel, unit)
    return {
        key = key,
        name = shortName,
        realm = normRealm,
        guid = guid,
        class = classFile,
        level = type(level) == "number" and level or 0,
        unit = unit,
    }
end

function FW.GetClassColorHex(classFile)
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        if c.colorStr and #c.colorStr == 8 then
            return c.colorStr:sub(3)
        end
        return string.format("%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
    end
    return "FFFFFF"
end

function FW.ColorizeName(name, classFile)
    local hex = FW.GetClassColorHex(classFile)
    return "|cff" .. hex .. tostring(name or "?") .. "|r"
end

function FW.GetTagColorInfo(colorId)
    for _, c in ipairs(FW.TAG_COLORS) do
        if c.id == colorId then
            return c
        end
    end
    return FW.TAG_COLORS[1]
end

-- ============================================================
-- Danger Tier Calculation & Lookup
-- ============================================================

function FW.GetDangerTier(rec)
    if not rec then return nil end
    local kills = rec.kills or 0
    local manualTier = rec.manualTier or 0

    local autoLevel = 1
    for i = #FW.DANGER_TIERS, 1, -1 do
        if kills >= FW.DANGER_TIERS[i].minKills then
            autoLevel = i
            break
        end
    end
    if kills == 0 and (rec.attacks or 0) == 0 and not rec.isNemesis and manualTier == 0 then
        autoLevel = 1
    end

    local finalLevel = math.max(autoLevel, manualTier)
    if finalLevel > #FW.DANGER_TIERS then finalLevel = #FW.DANGER_TIERS end
    if finalLevel < 1 then finalLevel = 1 end
    return FW.DANGER_TIERS[finalLevel]
end

function FW.GetDangerLabel(rec)
    if not rec then return "" end
    local tier = FW.GetDangerTier(rec)
    if rec.isNemesis then
        local ns = FW.NEMESIS_STYLE
        if (rec.kills or 0) >= 1 or (rec.manualTier or 0) >= 2 then
            return string.format("|cff%s%s|r · |cff%sLv.%d %s|r", ns.hex, ns.name, tier.hex, tier.level, tier.name)
        end
        return string.format("|cff%s%s|r", ns.hex, ns.name)
    end
    return string.format("|cff%sLv.%d %s|r", tier.hex, tier.level, tier.name)
end

function FW.GetDangerColor(rec)
    if rec and rec.isNemesis then
        return FW.NEMESIS_STYLE.r, FW.NEMESIS_STYLE.g, FW.NEMESIS_STYLE.b, FW.NEMESIS_STYLE.hex
    end
    local tier = FW.GetDangerTier(rec)
    if tier then
        return tier.r, tier.g, tier.b, tier.hex
    end
    return 1, 0.67, 0, "FFAA00"
end

function FW.RebuildIndexes()
    wipe(FW.shortNameToEnemyKey)
    wipe(FW.shortNameToTagKey)
    if not ForeverWatchDB then return end

    for key, rec in pairs(ForeverWatchDB.enemies) do
        local short = FW.GetShortName(key)
        if short ~= "" then
            -- Prefer same-realm match when multiple realms share a short name
            if not FW.shortNameToEnemyKey[short] or key == (short .. "-" .. FW.GetMyRealm()) then
                FW.shortNameToEnemyKey[short] = key
            end
        end
        if rec.guid and rec.guid ~= "" then
            ForeverWatchDB.guidToKey[rec.guid] = key
        end
    end

    for key, rec in pairs(ForeverWatchDB.tags) do
        local short = FW.GetShortName(key)
        if short ~= "" then
            if not FW.shortNameToTagKey[short] or key == (short .. "-" .. FW.GetMyRealm()) then
                FW.shortNameToTagKey[short] = key
            end
        end
        if rec.guid and rec.guid ~= "" then
            ForeverWatchDB.guidToKey[rec.guid] = key
        end
    end
end

function FW.FindEnemyRecord(nameOrKey, guid, explicitRealm)
    if not ForeverWatchDB then return nil, nil end
    if guid and FW.CanAccess(guid) then
        local gKey = ForeverWatchDB.guidToKey[guid]
        if gKey and ForeverWatchDB.enemies[gKey] then
            return ForeverWatchDB.enemies[gKey], gKey
        end
    end
    if nameOrKey and FW.CanAccess(nameOrKey) then
        local key, short = FW.NormalizePlayerKey(nameOrKey, explicitRealm)
        if key and ForeverWatchDB.enemies[key] then
            return ForeverWatchDB.enemies[key], key
        end
        if short and FW.shortNameToEnemyKey[short] then
            local sk = FW.shortNameToEnemyKey[short]
            if ForeverWatchDB.enemies[sk] then
                return ForeverWatchDB.enemies[sk], sk
            end
        end
    end
    return nil, nil
end

function FW.FindTagRecord(nameOrKey, guid, explicitRealm)
    if not ForeverWatchDB then return nil, nil end
    if guid and FW.CanAccess(guid) then
        local gKey = ForeverWatchDB.guidToKey[guid]
        if gKey and ForeverWatchDB.tags[gKey] then
            return ForeverWatchDB.tags[gKey], gKey
        end
    end
    if nameOrKey and FW.CanAccess(nameOrKey) then
        local key, short = FW.NormalizePlayerKey(nameOrKey, explicitRealm)
        if key and ForeverWatchDB.tags[key] then
            return ForeverWatchDB.tags[key], key
        end
        if short and FW.shortNameToTagKey[short] then
            local sk = FW.shortNameToTagKey[short]
            if ForeverWatchDB.tags[sk] then
                return ForeverWatchDB.tags[sk], sk
            end
        end
    end
    return nil, nil
end

function FW.FormatTagsInline(tagRec)
    if not tagRec or not tagRec.tags or #tagRec.tags == 0 then
        return ""
    end
    return table.concat(tagRec.tags, "/")
end

function FW.FormatRelativeTime(ts)
    if not ts or ts <= 0 then return L.UNKNOWN end
    local diff = math.max(0, time() - ts)
    if diff < 60 then
        return string.format(L.TIME_SEC_AGO, diff)
    elseif diff < 3600 then
        return string.format(L.TIME_MIN_AGO, math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format(L.TIME_HOUR_AGO, math.floor(diff / 3600))
    else
        return string.format(L.TIME_DAY_AGO, math.floor(diff / 86400))
    end
end

function FW.PlayAlertSound(soundKey)
    if not ForeverWatchDB or not ForeverWatchDB.settings.enableSound then return end
    if not PlaySound or not SOUNDKIT then return end
    local id = SOUNDKIT[soundKey] or SOUNDKIT.RAID_WARNING
    if id then
        pcall(PlaySound, id, "Master")
    end
end

-- ============================================================
-- Database Init & Refresh Hooks
-- ============================================================

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function TablesEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

function FW.IsDefaultPresetList(list)
    if type(list) ~= "table" or #list == 0 then
        return true
    end
    for _, locTbl in pairs(FW.LOCALES) do
        if locTbl.PRESET_TAGS and TablesEqual(list, locTbl.PRESET_TAGS) then
            return true
        end
    end
    return false
end

function FW.GetPresetTags()
    if FW.settings and type(FW.settings.presetTags) == "table" and #FW.settings.presetTags > 0 then
        return FW.settings.presetTags
    end
    return FW.DEFAULT_PRESET_TAGS
end

function FW.InitDB()
    if type(ForeverWatchDB) ~= "table" then
        ForeverWatchDB = {}
    end
    CopyDefaults(ForeverWatchDB, FW.DEFAULTS)
    FW.db = ForeverWatchDB
    FW.settings = ForeverWatchDB.settings
    FW.ApplyLocale(FW.settings.language)
    -- If presetTags was auto-populated with a built-in default list, clear it so it follows language dynamically
    if FW.IsDefaultPresetList(FW.settings.presetTags) then
        FW.settings.presetTags = nil
    end
    FW.RebuildIndexes()
end

function FW.SetLanguage(langCode)
    local valid = { AUTO = true, enUS = true, zhCN = true, zhTW = true }
    if not valid[langCode] then langCode = "AUTO" end
    FW.settings.language = langCode
    FW.ApplyLocale(langCode)
    if FW.IsDefaultPresetList(FW.settings.presetTags) then
        FW.settings.presetTags = nil
    end
    FW.RefreshAllUI()
    local labelMap = { AUTO = L.LANG_AUTO, enUS = L.LANG_ENUS, zhCN = L.LANG_ZHCN, zhTW = L.LANG_ZHTW }
    FW.Print(string.format(L.CMD_LANG_CHANGED, labelMap[langCode] or langCode))
end

function FW.RefreshAllUI()
    if FW.RefreshAllNameplates then
        FW.RefreshAllNameplates()
    end
    if FW.RefreshRadar then
        FW.RefreshRadar()
    end
    if FW.RefreshManagerUI then
        FW.RefreshManagerUI()
    end
end

-- ============================================================
-- Slash Commands (/fw, /foreverwatch)
-- ============================================================

SLASH_FOREVERWATCH1 = "/fw"
SLASH_FOREVERWATCH2 = "/foreverwatch"
SlashCmdList["FOREVERWATCH"] = function(msg)
    local cmd, rest = FW.Trim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "ui" or cmd == "config" or cmd == "open" then
        if FW.ToggleManagerUI then
            FW.ToggleManagerUI()
        end
    elseif cmd == "radar" then
        FW.settings.enableRadar = not FW.settings.enableRadar
        FW.Print(string.format(L.CMD_RADAR_TOGGLED, FW.settings.enableRadar and ("|cff4CFF6B" .. L.ON .. "|r") or ("|cffFF4444" .. L.OFF .. "|r")))
        if FW.RefreshRadar then FW.RefreshRadar() end
    elseif cmd == "lock" then
        FW.settings.radarLocked = not FW.settings.radarLocked
        if FW.ApplyRadarLockState then FW.ApplyRadarLockState() end
        FW.RefreshAllUI()
        FW.Print(string.format(L.CMD_LOCK_TOGGLED, FW.settings.radarLocked and ("|cffFFD100" .. L.LOCKED .. "|r") or ("|cff4CFF6B" .. L.UNLOCKED .. "|r")))
    elseif cmd == "tag" then
        local targetName = FW.Trim(rest)
        if targetName == "" then
            local info = FW.GetUnitIdentity("target")
            if info
                and FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, "target"))
                and not FW.SafeBool(FW.SafeUnitCall(UnitIsUnit, "target", "player"))
            then
                FW.OpenTagDialog(info.key, info.guid, info.class)
                return
            end
            FW.Print(L.CMD_TAG_USAGE)
            return
        end
        local key = FW.NormalizePlayerKey(targetName)
        if key and key == FW.myKey then
            FW.Print(L.CMD_SELF_TAG_DENIED)
            return
        end
        if key and FW.OpenTagDialog then
            FW.OpenTagDialog(key)
        end
    elseif cmd == "enemy" or cmd == "nemesis" then
        local targetName = FW.Trim(rest)
        if targetName == "" then
            local info = FW.GetUnitIdentity("target")
            if info and FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, "target")) and FW.SafeBool(FW.SafeUnitCall(UnitIsEnemy, "player", "target")) then
                FW.RecordEnemyAction(info, cmd == "nemesis" and "manual_nemesis" or "manual_danger")
                return
            end
            FW.Print(L.CMD_NEMESIS_USAGE)
            return
        end
        local key, short, realm = FW.NormalizePlayerKey(targetName)
        if key and FW.RecordEnemyAction then
            FW.RecordEnemyAction({ key = key, name = short, realm = realm }, cmd == "nemesis" and "manual_nemesis" or "manual_danger")
        end
    elseif cmd == "lang" or cmd == "language" then
        local map = { auto = "AUTO", enus = "enUS", en = "enUS", zhcn = "zhCN", cn = "zhCN", zhtw = "zhTW", tw = "zhTW" }
        local code = map[(rest or ""):lower()]
        if code then
            FW.SetLanguage(code)
        else
            FW.Print(L.CMD_HELP_LANG)
        end
    elseif cmd == "test" then
        if rest:lower() == "multi" then
            if FW.TriggerMultiAlertTest then FW.TriggerMultiAlertTest() end
            FW.Print(L.CMD_TEST_MULTI)
        else
            if FW.ShowAlertBanner then
                FW.ShowAlertBanner(L.TEST_SINGLE_NAME, "ROGUE", {
                    key = "TestEnemySingle-Test",
                    isNemesis = true,
                    kills = 4,
                    killedMe = 1,
                    attacks = 5,
                }, L.TEST_SINGLE_REASON, 5)
            end
            FW.Print(L.CMD_TEST_SINGLE)
        end
    else
        FW.Print(L.CMD_HELP_HEADER)
        FW.Print(L.CMD_HELP_OPEN)
        FW.Print(L.CMD_HELP_RADAR)
        FW.Print(L.CMD_HELP_LOCK)
        FW.Print(L.CMD_HELP_TAG)
        FW.Print(L.CMD_HELP_NEMESIS)
        FW.Print(L.CMD_HELP_TEST)
        FW.Print(L.CMD_HELP_LANG)
    end
end

-- ============================================================
-- Addon Bootstrap
-- ============================================================

local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("ADDON_LOADED")
bootFrame:RegisterEvent("PLAYER_LOGIN")
bootFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        FW.InitDB()
    elseif event == "PLAYER_LOGIN" then
        if not FW.db then FW.InitDB() end
        local myName = FW.SafeUnitCall(UnitName, "player")
        local myRealm = FW.GetMyRealm()
        if myName then
            FW.myShortName = myName
            FW.myKey = (myRealm ~= "") and (myName .. "-" .. myRealm) or myName
        end
        FW.RebuildIndexes()

        if FW.InitDangerMonitor then FW.InitDangerMonitor() end
        if FW.InitPlayerTags then FW.InitPlayerTags() end
        if FW.InitDisplayHooks then FW.InitDisplayHooks() end
        if FW.InitManagerUI then FW.InitManagerUI() end

        FW.Print(string.format(L.LOADED_MSG, FW.version))
    end
end)
