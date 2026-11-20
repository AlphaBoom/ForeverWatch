local _, FW = ...
local L = FW.L

-- Runtime tracking tables
local liveEnemies = {}         -- [key] = { key, name, realm, guid, class, level, unit, lastSeen, inCombat, targetKey, targetSince, zone }
local friendlyState = {}       -- [key] = { alive, hp, lastSeen, name, lastDeathCredit }
local recentAttackers = {}     -- [victimKey] = { [enemyKey] = { time, reason, enemySnapshot } }
local lastProximityAlert = {}  -- [enemyKey] = GetTime()
local lastAttackRecord = {}    -- [enemyKey .. ":" .. victimKey] = GetTime()
local lastMyDeathHandled = 0

local alertBanners = {}
local alertOverflowBar
local overflowEnemies = {}     -- [enemyKey] = { isNemesis = bool }
local MAX_ALERT_SLOTS = 3
local lastSoundTime = 0
local lastSoundPriority = 0

local radarFrame
local radarRows = {}
local MAX_RADAR_ROWS = 8
local MAX_LIVE_ENEMIES = 160
local radarRefreshPending = false
local lastRadarRefresh = 0

local function GetZoneTextSafe()
    local z = GetRealZoneText and GetRealZoneText() or ""
    if not z or z == "" then
        z = GetZoneText and GetZoneText() or L.UNKNOWN_ZONE
    end
    return z
end

local function IsFriendlyPlayerUnit(unit)
    if not unit then return false end
    if not FW.SafeBool(FW.SafeUnitCall(UnitExists, unit)) then return false end
    if not FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, unit)) then return false end
    if FW.SafeBool(FW.SafeUnitCall(UnitIsUnit, unit, "player")) then return true end
    return FW.SafeBool(FW.SafeUnitCall(UnitIsFriend, "player", unit))
end

local function IsEnemyPlayerUnit(unit)
    if not unit then return false end
    if not FW.SafeBool(FW.SafeUnitCall(UnitExists, unit)) then return false end
    if not FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, unit)) then return false end
    return FW.SafeBool(FW.SafeUnitCall(UnitIsEnemy, "player", unit))
end

local function IsUnitDeadSafe(unit)
    return FW.SafeBool(FW.SafeUnitCall(UnitIsDeadOrGhost, unit))
end

local function GetUnitHealthSafe(unit)
    local hp = FW.SafeUnitCall(UnitHealth, unit)
    if type(hp) == "number" then
        return hp
    end
    return nil
end

-- ============================================================
-- Enemy Record Management
-- ============================================================

local function EnsureEnemyRecord(snapshot)
    if not snapshot or not snapshot.key then return nil end
    local rec = FW.db.enemies[snapshot.key]
    local isNew = false
    if not rec then
        rec = {
            key = snapshot.key,
            name = snapshot.name or FW.GetShortName(snapshot.key),
            realm = snapshot.realm or FW.GetMyRealm(),
            guid = snapshot.guid,
            class = snapshot.class,
            level = snapshot.level or 0,
            attacks = 0,
            kills = 0,
            killedMe = 0,
            isNemesis = false,
            manualTier = 0,
            note = "",
            firstSeen = time(),
            lastSeen = time(),
            lastZone = GetZoneTextSafe(),
            lastEvent = "",
        }
        FW.db.enemies[snapshot.key] = rec
        isNew = true
    else
        if snapshot.guid and snapshot.guid ~= "" then rec.guid = snapshot.guid end
        if snapshot.class and snapshot.class ~= "" then rec.class = snapshot.class end
        if snapshot.level and snapshot.level > 0 then rec.level = snapshot.level end
        rec.lastSeen = time()
        rec.lastZone = GetZoneTextSafe()
    end

    if rec.guid and rec.guid ~= "" then
        FW.db.guidToKey[rec.guid] = rec.key
    end
    local short = FW.GetShortName(rec.key)
    if short ~= "" then
        FW.shortNameToEnemyKey[short] = rec.key
    end
    return rec, isNew
end

function FW.DeleteEnemyRecord(key)
    if not key or not FW.db.enemies[key] then return end
    FW.db.enemies[key] = nil
    FW.RebuildIndexes()
    FW.RefreshAllUI()
end

function FW.SetEnemyNemesis(key, isNemesis)
    local rec = FW.db.enemies[key]
    if not rec then return end
    rec.isNemesis = isNemesis and true or false
    FW.RefreshAllUI()
end

function FW.AdjustEnemyManualTier(key, tierLevel)
    local rec = FW.db.enemies[key]
    if not rec then return end
    rec.manualTier = math.max(0, math.min(#FW.DANGER_TIERS, tierLevel or 0))
    FW.RefreshAllUI()
end

function FW.SetEnemyNote(key, note)
    local rec = FW.db.enemies[key]
    if not rec then return end
    rec.note = FW.Trim(note or "")
    FW.RefreshAllUI()
end

-- ============================================================
-- Multi-Enemy Stacked Screen Alert Banners + Overflow Summary
-- ============================================================

local function GetBannerAnchorBase()
    if FW.settings and FW.settings.bannerPoint then
        local p = FW.settings.bannerPoint
        return p[1], p[2], p[3], p[4]
    end
    return "TOP", "TOP", 0, -120
end

local function CreateAlertOverflowBar()
    local bar = CreateFrame("Frame", "ForeverWatchAlertOverflowBar", UIParent, "BackdropTemplate")
    bar:SetSize(460, 28)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(false)
    bar:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bar:SetBackdropColor(0.24, 0.05, 0.08, 0.94)
    bar:SetBackdropBorderColor(1.0, 0.30, 0.25, 0.95)

    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text = txt
    bar:Hide()
    return bar
end

local function LayoutAlertBanners()
    local active = {}
    for i = 1, #alertBanners do
        local b = alertBanners[i]
        if b and b:IsShown() then
            active[#active + 1] = b
        end
    end

    table.sort(active, function(a, b)
        if (a.priority or 0) ~= (b.priority or 0) then
            return (a.priority or 0) > (b.priority or 0)
        end
        return (a.shownAt or 0) > (b.shownAt or 0)
    end)

    local p1, p2, baseX, baseY = GetBannerAnchorBase()
    local stepY = 78
    for idx, b in ipairs(active) do
        b:ClearAllPoints()
        b:SetPoint(p1, UIParent, p2, baseX, baseY - (idx - 1) * stepY)
    end

    -- Update or hide overflow summary bar when 4+ enemies trigger simultaneously
    local extraCount = 0
    local extraNemesis = 0
    for k, info in pairs(overflowEnemies) do
        -- Exclude anyone currently visible in active slots
        local visible = false
        for _, b in ipairs(active) do
            if b.enemyKey == k then
                visible = true
                break
            end
        end
        if visible then
            overflowEnemies[k] = nil
        else
            extraCount = extraCount + 1
            if info.isNemesis then extraNemesis = extraNemesis + 1 end
        end
    end

    if #active == 0 then
        wipe(overflowEnemies)
        if alertOverflowBar then alertOverflowBar:Hide() end
        return
    end

    if extraCount > 0 then
        if not alertOverflowBar then
            alertOverflowBar = CreateAlertOverflowBar()
        end
        local nemStr = extraNemesis > 0 and string.format(L.ALERT_OVERFLOW_NEMESIS, extraNemesis) or ""
        alertOverflowBar.text:SetText(string.format(L.ALERT_OVERFLOW_FMT,
            FW.GetEnemyIconMarkup(extraNemesis > 0, 14), extraCount, nemStr))
        alertOverflowBar:ClearAllPoints()
        alertOverflowBar:SetPoint(p1, UIParent, p2, baseX, baseY - (#active) * stepY + 4)
        alertOverflowBar:Show()
    elseif alertOverflowBar then
        alertOverflowBar:Hide()
    end
end

local function CreateAlertBannerSlot(index)
    local f = CreateFrame("Frame", "ForeverWatchAlertFrame" .. index, UIParent, "BackdropTemplate")
    f:SetSize(460, 74)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)

    f:SetBackdrop({
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 256, edgeSize = 22,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.20, 0.08, 0.08, 0.94)
    f:SetBackdropBorderColor(1, 0.30, 0.25, 1)

    local bgOverlay = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgOverlay:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
    bgOverlay:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    bgOverlay:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
    bgOverlay:SetAlpha(0.75)

    local topGlow = f:CreateTexture(nil, "ARTWORK")
    topGlow:SetHeight(22)
    topGlow:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -7)
    topGlow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
    topGlow:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    topGlow:SetBlendMode("ADD")
    topGlow:SetAlpha(0.32)
    f.topGlow = topGlow

    local iconBg = f:CreateTexture(nil, "ARTWORK")
    iconBg:SetSize(38, 38)
    iconBg:SetPoint("LEFT", f, "LEFT", 16, 0)
    iconBg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall")
    iconBg:SetVertexColor(0.08, 0.04, 0.06, 0.9)

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    FW.ApplyIconToTexture(icon, FW.ICONS.DANGER_SWORD)
    f.icon = icon

    local iconRing = f:CreateTexture(nil, "OVERLAY", nil, 2)
    iconRing:SetSize(52, 52)
    iconRing:SetPoint("CENTER", iconBg, "CENTER", 9, -9)
    iconRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    f.iconRing = iconRing

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 14, -1)
    title:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    f.title = title

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    f.sub = sub

    f.elapsed = 0
    f.duration = 4.6
    f.fadeIn = 0.20
    f.fadeOut = 0.80
    f.priority = 0
    f.enemyKey = nil
    f.shownAt = 0

    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < self.fadeIn then
            self:SetAlpha(self.elapsed / self.fadeIn)
        elseif self.elapsed < (self.duration - self.fadeOut) then
            self:SetAlpha(1)
        elseif self.elapsed < self.duration then
            local rem = self.duration - self.elapsed
            self:SetAlpha(math.max(0, rem / self.fadeOut))
        else
            self:Hide()
            self.priority = 0
            self.enemyKey = nil
            LayoutAlertBanners()
        end
    end)

    f:Hide()
    return f
end

local function PopulateAlertSlot(slot, enemyKey, enemyName, classFile, rec, reason, priority)
    local r, g, b = FW.GetDangerColor(rec)
    local label = FW.GetDangerLabel(rec)

    slot:SetBackdropBorderColor(r, g, b, 1)
    slot:SetBackdropColor(r * 0.25, g * 0.12, b * 0.18, 0.94)
    slot.topGlow:SetVertexColor(r, g, b, 0.40)
    if rec and rec.isNemesis then
        FW.ApplyIconToTexture(slot.icon, FW.ICONS.NEMESIS)
        slot.icon:SetVertexColor(1, 0.65, 1, 1)
    else
        FW.ApplyIconToTexture(slot.icon, FW.ICONS.DANGER_SWORD)
        slot.icon:SetVertexColor(1, 0.85, 0.65, 1)
    end

    local displayName = FW.ColorizeName(FW.GetDisplayName(enemyName), classFile)
    slot.title:SetText(string.format("%s  %s", label, displayName))
    slot.sub:SetText(reason or L.ALERT_DEFAULT_REASON)

    slot.enemyKey = enemyKey
    slot.isNemesis = rec and rec.isNemesis or false
    slot.priority = priority
    slot.elapsed = 0
    slot.shownAt = GetTime()
    slot:SetAlpha(0.05)
    slot:Show()
end

local function PlayThrottledAlertSound(rec, priority)
    local now = GetTime()
    -- Prevent ear-blasting sound overlap when multiple enemies trigger at once
    if (now - lastSoundTime) < 1.5 and priority <= lastSoundPriority then
        return
    end
    lastSoundTime = now
    lastSoundPriority = priority

    if rec and rec.isNemesis then
        FW.PlayAlertSound(FW.NEMESIS_STYLE.sound)
    else
        local tier = FW.GetDangerTier(rec)
        if tier then
            FW.PlayAlertSound(tier.sound)
        end
    end
end

function FW.ShowAlertBanner(enemyName, classFile, rec, reason, priority)
    if not FW.settings.enableBanner then return end

    for i = 1, MAX_ALERT_SLOTS do
        if not alertBanners[i] then
            alertBanners[i] = CreateAlertBannerSlot(i)
        end
    end

    priority = priority or 1
    local enemyKey = (rec and rec.key) or FW.NormalizePlayerKey(enemyName) or tostring(enemyName or "")

    -- 1. If this same enemy is already displayed in an active slot, update in place (no duplicate)
    local targetSlot = nil
    for i = 1, MAX_ALERT_SLOTS do
        local b = alertBanners[i]
        if b:IsShown() and b.enemyKey == enemyKey then
            targetSlot = b
            break
        end
    end

    -- 2. Otherwise pick the first free slot
    if not targetSlot then
        for i = 1, MAX_ALERT_SLOTS do
            local b = alertBanners[i]
            if not b:IsShown() then
                targetSlot = b
                break
            end
        end
    end

    -- 3. All 3 slots occupied (4+ enemies simultaneously):
    --    Promote if higher priority (moving displaced enemy to overflow summary),
    --    or aggregate into overflow summary bar so no alert is silently lost!
    if not targetSlot then
        local weakest = nil
        for i = 1, MAX_ALERT_SLOTS do
            local b = alertBanners[i]
            if not weakest
                or (b.priority or 0) < (weakest.priority or 0)
                or ((b.priority or 0) == (weakest.priority or 0) and (b.shownAt or 0) < (weakest.shownAt or 0))
            then
                weakest = b
            end
        end

        if weakest and priority > (weakest.priority or 0) then
            if weakest.enemyKey then
                overflowEnemies[weakest.enemyKey] = { isNemesis = weakest.isNemesis }
            end
            targetSlot = weakest
        else
            overflowEnemies[enemyKey] = { isNemesis = rec and rec.isNemesis or false }
            LayoutAlertBanners()
            PlayThrottledAlertSound(rec, priority)
            return
        end
    end

    overflowEnemies[enemyKey] = nil
    PopulateAlertSlot(targetSlot, enemyKey, enemyName, classFile, rec, reason, priority)
    LayoutAlertBanners()
    PlayThrottledAlertSound(rec, priority)
end

function FW.TriggerMultiAlertTest()
    local samples = {
        { name = L.TEST_MULTI_1_NAME, class = "ROGUE",   rec = { key = "TestMulti1-Test", isNemesis = true,  kills = 6, killedMe = 2, attacks = 9 }, reason = L.TEST_MULTI_1_REASON, prio = 5 },
        { name = L.TEST_MULTI_2_NAME, class = "MAGE",    rec = { key = "TestMulti2-Test", isNemesis = false, kills = 4, killedMe = 0, attacks = 5 }, reason = L.TEST_MULTI_2_REASON, prio = 3 },
        { name = L.TEST_MULTI_3_NAME, class = "WARRIOR", rec = { key = "TestMulti3-Test", isNemesis = false, kills = 1, killedMe = 0, attacks = 3 }, reason = L.TEST_MULTI_3_REASON, prio = 2 },
        { name = L.TEST_MULTI_4_NAME, class = "PRIEST",  rec = { key = "TestMulti4-Test", isNemesis = true,  kills = 2, killedMe = 1, attacks = 2 }, reason = L.TEST_MULTI_4_REASON, prio = 4 },
        { name = L.TEST_MULTI_5_NAME, class = "HUNTER",  rec = { key = "TestMulti5-Test", isNemesis = false, kills = 0, killedMe = 0, attacks = 1 }, reason = L.TEST_MULTI_5_REASON, prio = 1 },
    }
    for i, s in ipairs(samples) do
        C_Timer.After((i - 1) * 0.25, function()
            FW.ShowAlertBanner(s.name, s.class, s.rec, s.reason, s.prio)
        end)
    end
end

-- ============================================================
-- Recording Enemy Actions (Attack / Kill / Killed Me / Manual)
-- ============================================================

function FW.RecordEnemyAction(snapshot, actionType, victimName)
    if not snapshot or not snapshot.key then return end
    local oldRec = FW.db.enemies[snapshot.key]
    local oldTierLevel = oldRec and FW.GetDangerTier(oldRec).level or 0
    local wasNemesis = oldRec and oldRec.isNemesis or false

    local rec, isNew = EnsureEnemyRecord(snapshot)
    if not rec then return end

    local now = GetTime()
    local reason = nil
    local priority = 1
    local shouldAlert = false

    if actionType == "attack" then
        local throttleKey = rec.key .. ":" .. (victimName or "")
        if not lastAttackRecord[throttleKey] or (now - lastAttackRecord[throttleKey]) >= 10 then
            lastAttackRecord[throttleKey] = now
            rec.attacks = (rec.attacks or 0) + 1
            rec.lastEvent = victimName and string.format(L.ALERT_EVENT_ATTACK_NAMED, victimName) or L.ALERT_EVENT_ATTACK_GENERIC
            if isNew or not lastProximityAlert[rec.key] or (now - lastProximityAlert[rec.key]) >= 20 then
                lastProximityAlert[rec.key] = now
                reason = victimName and string.format(L.ALERT_ATTACK_NAMED, victimName) or L.ALERT_ATTACK_GENERIC
                priority = rec.isNemesis and 4 or 2
                shouldAlert = true
            end
        end

    elseif actionType == "kill_friendly" then
        rec.kills = (rec.kills or 0) + 1
        rec.lastEvent = victimName and string.format(L.ALERT_EVENT_KILL_NAMED, victimName) or L.ALERT_EVENT_KILL_GENERIC
        local newTier = FW.GetDangerTier(rec)
        local tierMsg = (newTier.level > oldTierLevel)
            and string.format(L.ALERT_TIER_UP, newTier.level, newTier.name)
            or string.format(L.ALERT_TOTAL_KILLS, rec.kills)
        reason = (victimName and string.format(L.ALERT_KILL_PREFIX_NAMED, victimName) or L.ALERT_KILL_PREFIX_GENERIC) .. tierMsg
        lastProximityAlert[rec.key] = now
        priority = rec.isNemesis and 5 or 3
        shouldAlert = true

        FW.Print(string.format("%s %s %s",
            FW.GetDangerLabel(rec),
            FW.ColorizeName(FW.GetDisplayName(rec.key), rec.class),
            reason))

    elseif actionType == "killed_me" then
        rec.isNemesis = true
        rec.killedMe = (rec.killedMe or 0) + 1
        rec.kills = (rec.kills or 0) + 1
        rec.lastEvent = L.ALERT_KILLED_ME_EVENT
        reason = string.format(L.ALERT_KILLED_ME_REASON, rec.killedMe, rec.kills)
        lastProximityAlert[rec.key] = now
        priority = 5
        shouldAlert = true

        FW.Print(string.format("%s %s %s",
            FW.GetEnemyIconMarkup(true, 14) .. " " .. FW.GetDangerLabel(rec),
            FW.ColorizeName(FW.GetDisplayName(rec.key), rec.class),
            reason))

    elseif actionType == "manual_nemesis" then
        rec.isNemesis = true
        rec.lastEvent = L.ALERT_MANUAL_NEMESIS_EVENT
        reason = L.ALERT_MANUAL_NEMESIS_REASON
        priority = 4
        shouldAlert = not wasNemesis
        FW.Print(string.format(L.ALERT_MARKED_AS, FW.ColorizeName(FW.GetDisplayName(rec.key), rec.class), FW.GetDangerLabel(rec)))

    elseif actionType == "manual_danger" then
        rec.attacks = math.max(rec.attacks or 0, 1)
        rec.lastEvent = L.ALERT_MANUAL_DANGER_EVENT
        FW.Print(string.format(L.ALERT_MARKED_AS, FW.ColorizeName(FW.GetDisplayName(rec.key), rec.class), FW.GetDangerLabel(rec)))
    end

    if shouldAlert and reason then
        FW.ShowAlertBanner(rec.key, rec.class, rec, reason, priority)
    end

    FW.RefreshAllUI()
end

-- ============================================================
-- Proximity & Combat Inference Engine (Forever 16001 Safe)
-- ============================================================

local function NoteRecentAttacker(victimKey, victimName, enemySnap, reason)
    if not victimKey or not enemySnap or not enemySnap.key then return end
    local now = GetTime()
    if not recentAttackers[victimKey] then
        recentAttackers[victimKey] = {}
    end
    recentAttackers[victimKey][enemySnap.key] = {
        time = now,
        reason = reason,
        snapshot = enemySnap,
    }
    FW.RecordEnemyAction(enemySnap, "attack", victimName)
end

local function TriggerProximityCheck(snap)
    if not snap or not snap.key then return end
    local rec = FW.FindEnemyRecord(snap.key, snap.guid, snap.realm)
    if not rec then return end

    -- Refresh stored metadata
    if snap.guid and snap.guid ~= "" then
        rec.guid = snap.guid
        FW.db.guidToKey[snap.guid] = rec.key
    end
    if snap.class and snap.class ~= "" then rec.class = snap.class end
    if snap.level and snap.level > 0 then rec.level = snap.level end
    rec.lastSeen = time()
    rec.lastZone = GetZoneTextSafe()

    local now = GetTime()
    local cd = FW.settings.alertCooldown or 45
    if not lastProximityAlert[rec.key] or (now - lastProximityAlert[rec.key]) >= cd then
        lastProximityAlert[rec.key] = now
        local extra = rec.isNemesis
            and string.format(L.ALERT_PROX_NEMESIS, rec.killedMe or 0, rec.kills or 0)
            or string.format(L.ALERT_PROX_DANGER, rec.kills or 0)
        FW.ShowAlertBanner(rec.key, rec.class, rec, extra, rec.isNemesis and 4 or 2)
    end
end

local function InspectFriendlyUnit(unit)
    if not IsFriendlyPlayerUnit(unit) then return nil end
    local info = FW.GetUnitIdentity(unit)
    if not info then return nil end

    local now = GetTime()
    local dead = IsUnitDeadSafe(unit)
    local hp = GetUnitHealthSafe(unit)
    local prev = friendlyState[info.key]

    local hpDropped = false
    if prev and prev.hp and hp and hp < prev.hp then
        hpDropped = true
    end

    -- Detect alive -> dead transition (excluding "player" which is handled specifically by PLAYER_DEAD)
    if dead and prev and prev.alive and info.key ~= FW.myKey then
        if not prev.lastDeathCredit or (now - prev.lastDeathCredit) >= 15 then
            prev.lastDeathCredit = now
            local credited = {}

            -- 1) Recent confirmed attackers of this victim within 14s
            local attMap = recentAttackers[info.key]
            if attMap then
                for eKey, entry in pairs(attMap) do
                    if (now - entry.time) <= 14 then
                        credited[eKey] = entry.snapshot
                    end
                end
            end

            -- 2) Any currently-tracked in-combat enemy targeting this victim at death
            for eKey, eSnap in pairs(liveEnemies) do
                if (now - eSnap.lastSeen) <= 5 and eSnap.inCombat and eSnap.targetKey == info.key then
                    credited[eKey] = eSnap
                end
            end

            for _, eSnap in pairs(credited) do
                FW.RecordEnemyAction(eSnap, "kill_friendly", info.name)
            end
            recentAttackers[info.key] = nil
        end
    end

    friendlyState[info.key] = {
        alive = not dead,
        hp = hp or (prev and prev.hp),
        lastSeen = now,
        name = info.name,
        lastDeathCredit = prev and prev.lastDeathCredit or 0,
    }
    return info, hpDropped
end

local function InspectEnemyUnit(unit)
    if not IsEnemyPlayerUnit(unit) then return nil end
    local info = FW.GetUnitIdentity(unit)
    if not info then return nil end

    local now = GetTime()
    local inCombat = FW.SafeBool(FW.SafeUnitCall(UnitAffectingCombat, unit))
    local prev = liveEnemies[info.key]

    local targetUnit = unit .. "target"
    local targetKey = nil
    local targetInfo = nil
    local targetHpDropped = false

    if IsFriendlyPlayerUnit(targetUnit) then
        targetInfo, targetHpDropped = InspectFriendlyUnit(targetUnit)
        if targetInfo then
            targetKey = targetInfo.key
        end
    end

    local targetSince = now
    if prev and prev.targetKey == targetKey and targetKey ~= nil then
        targetSince = prev.targetSince or now
    end

    local snap = {
        key = info.key,
        name = info.name,
        realm = info.realm,
        guid = info.guid or (prev and prev.guid),
        class = info.class or (prev and prev.class),
        level = (info.level and info.level > 0) and info.level or (prev and prev.level) or 0,
        unit = unit,
        lastSeen = now,
        inCombat = inCombat,
        targetKey = targetKey,
        targetName = targetInfo and targetInfo.name or nil,
        targetSince = targetSince,
        zone = GetZoneTextSafe(),
    }
    liveEnemies[info.key] = snap
    FW.nearbyEnemies = liveEnemies

    -- Proximity alert if already a known dangerous enemy or nemesis
    TriggerProximityCheck(snap)

    -- Infer active attack on friendly player:
    -- Enemy is in combat + targeting a living friendly player who is also in combat
    -- and either HP dropped, or enemy is actively casting, or sustained lock >= 1.2s
    if inCombat and targetInfo and not IsUnitDeadSafe(targetUnit) then
        local targetInCombat = FW.SafeBool(FW.SafeUnitCall(UnitAffectingCombat, targetUnit))
        local casting = FW.SafeUnitCall(UnitCastingInfo, unit) ~= nil or FW.SafeUnitCall(UnitChannelInfo, unit) ~= nil
        if casting or (targetInCombat and (targetHpDropped or (now - targetSince) >= 1.2)) then
            NoteRecentAttacker(targetInfo.key, targetInfo.name, snap, casting and "cast" or "combat_lock")
        end
    end

    return snap
end

local function ScanUnitAndTarget(unit)
    if not unit then return end
    if IsEnemyPlayerUnit(unit) then
        InspectEnemyUnit(unit)
    elseif IsFriendlyPlayerUnit(unit) then
        InspectFriendlyUnit(unit)
        local t = unit .. "target"
        if IsEnemyPlayerUnit(t) then
            InspectEnemyUnit(t)
        end
    end
end

local function ScanAllNearbyUnits()
    if not FW.settings or not FW.settings.enableMonitor then return end

    local now = GetTime()

    -- Scan player, target, focus, mouseover
    InspectFriendlyUnit("player")
    ScanUnitAndTarget("target")
    ScanUnitAndTarget("focus")
    ScanUnitAndTarget("mouseover")

    -- Scan visible nameplates
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for i = 1, #plates do
                local plate = plates[i]
                local unit = plate and plate.namePlateUnitToken
                if not unit and plate and plate.UnitFrame then
                    unit = plate.UnitFrame.unit
                end
                if unit then
                    ScanUnitAndTarget(unit)
                end
            end
        end
    end

    -- Scan party / raid members & their targets
    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, math.min(n, 40) do
            ScanUnitAndTarget("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            ScanUnitAndTarget("party" .. i)
        end
    end

    -- Prune stale live enemy snapshots (> 18s unseen) and enforce cap in massive battles
    local liveCount = 0
    for k, snap in pairs(liveEnemies) do
        if (now - snap.lastSeen) > 18 then
            liveEnemies[k] = nil
        else
            liveCount = liveCount + 1
        end
    end

    if liveCount > MAX_LIVE_ENEMIES then
        local victims = {}
        for k, snap in pairs(liveEnemies) do
            if not FW.FindEnemyRecord(k, snap.guid, snap.realm) then
                victims[#victims + 1] = { key = k, lastSeen = snap.lastSeen or 0 }
            end
        end
        table.sort(victims, function(a, b) return a.lastSeen < b.lastSeen end)
        local toDrop = math.min(#victims, liveCount - MAX_LIVE_ENEMIES)
        for i = 1, toDrop do
            liveEnemies[victims[i].key] = nil
        end
    end

    -- Prune stale attacker memory (> 20s)
    for vKey, map in pairs(recentAttackers) do
        local any = false
        for eKey, entry in pairs(map) do
            if (now - entry.time) > 20 then
                map[eKey] = nil
            else
                any = true
            end
        end
        if not any then
            recentAttackers[vKey] = nil
        end
    end

    FW.ScheduleRadarRefresh()
end

-- Handle PLAYER_DEAD via C_DeathRecap + recentAttackers fallback
local function HandlePlayerDeath(isRetry)
    if not FW.settings or not FW.settings.enableMonitor then return end
    local now = GetTime()
    if not isRetry then
        if (now - lastMyDeathHandled) < 3 then return end
    end

    local killers = {}

    -- Method 1: Blizzard C_DeathRecap.GetRecapEvents() (official Forever 16001 API)
    if C_DeathRecap and C_DeathRecap.GetRecapEvents then
        local ok, events = pcall(C_DeathRecap.GetRecapEvents)
        if ok and type(events) == "table" and not FW.IsSecret(events) then
            for i = 1, #events do
                local ev = events[i]
                if type(ev) == "table" and not FW.IsSecret(ev) then
                    local srcName = ev.sourceName
                    local causedDeath = ev.causedDeath
                    if FW.CanAccess(srcName) and type(srcName) == "string" and srcName ~= "" then
                        local isFatal = FW.CanAccess(causedDeath) and causedDeath == true
                        local key, short, realm = FW.NormalizePlayerKey(srcName)
                        -- Match against live nearby enemy players or already-known enemies
                        -- so NPCs/mobs are never misclassified as enemy players
                        local matchedSnap = nil
                        if key and liveEnemies[key] then
                            matchedSnap = liveEnemies[key]
                        else
                            for _, s in pairs(liveEnemies) do
                                if s.name == short then
                                    matchedSnap = s
                                    break
                                end
                            end
                        end
                        if not matchedSnap then
                            local existing = FW.FindEnemyRecord(srcName)
                            if existing then
                                matchedSnap = existing
                            end
                        end
                        if matchedSnap and (isFatal or not next(killers)) then
                            killers[matchedSnap.key] = matchedSnap
                            if isFatal then break end
                        end
                    end
                end
            end
        end
    end

    -- Method 2: Fallback to recent confirmed enemy attackers of "player"
    if not next(killers) and FW.myKey then
        local attMap = recentAttackers[FW.myKey]
        if attMap then
            local newestTime = 0
            local newestSnap = nil
            for _, entry in pairs(attMap) do
                if (now - entry.time) <= 15 and entry.time > newestTime then
                    newestTime = entry.time
                    newestSnap = entry.snapshot
                end
            end
            if newestSnap then
                killers[newestSnap.key] = newestSnap
            end
        end
    end

    -- Method 3: Fallback to any in-combat nearby enemy player targeting us right now
    if not next(killers) and FW.myKey then
        for _, snap in pairs(liveEnemies) do
            if (now - snap.lastSeen) <= 6 and snap.inCombat and snap.targetKey == FW.myKey then
                killers[snap.key] = snap
            end
        end
    end

    if next(killers) then
        lastMyDeathHandled = now
        for _, snap in pairs(killers) do
            FW.RecordEnemyAction(snap, "killed_me", FW.myShortName)
        end
    elseif not isRetry then
        -- Retry once after 0.25s in case DeathRecap finishes populating slightly after PLAYER_DEAD
        C_Timer.After(0.25, function()
            if (GetTime() - lastMyDeathHandled) >= 3 then
                HandlePlayerDeath(true)
            end
        end)
    end
end

-- ============================================================
-- Floating Nearby Danger Radar Panel
-- ============================================================

local function OpenRadarRowMenu(anchor, entry)
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end
    MenuUtil.CreateContextMenu(anchor, function(owner, rootDescription)
        local displayName = FW.GetDisplayName(entry.key)
        rootDescription:CreateTitle(FW.ColorizeName(displayName, entry.class))
        local tagRec = FW.FindTagRecord(entry.key, entry.snap and entry.snap.guid)
        rootDescription:CreateButton(FW.GetEditIconMarkup(14) .. " " .. (tagRec and string.format(L.MENU_EDIT_TAG, FW.GetTagColorInfo(tagRec.color).hex, FW.FormatTagsInline(tagRec) ~= "" and FW.FormatTagsInline(tagRec) or L.TAG_NOTE_FALLBACK) or L.MENU_ADD_TAG), function()
            FW.OpenTagDialog(entry.key, entry.snap and entry.snap.guid, entry.class)
        end)
        local rec = FW.db.enemies[entry.key]
        if rec then
            rootDescription:CreateButton(rec.isNemesis and L.RADAR_MENU_UNMARK_NEMESIS or L.RADAR_MENU_MARK_NEMESIS, function()
                FW.SetEnemyNemesis(entry.key, not rec.isNemesis)
            end)
            rootDescription:CreateButton(L.RADAR_MENU_UPGRADE, function()
                local cur = FW.GetDangerTier(rec).level
                FW.AdjustEnemyManualTier(entry.key, math.min(#FW.DANGER_TIERS, cur + 1))
            end)
            rootDescription:CreateButton(L.RADAR_MENU_DELETE, function()
                FW.DeleteEnemyRecord(entry.key)
            end)
        else
            rootDescription:CreateButton(L.RADAR_MENU_MARK_DANGER, function()
                FW.RecordEnemyAction(entry.snap, "manual_danger")
            end)
            rootDescription:CreateButton(L.RADAR_MENU_MARK_NEMESIS, function()
                FW.RecordEnemyAction(entry.snap, "manual_nemesis")
            end)
        end
        rootDescription:CreateDivider()
        rootDescription:CreateButton(L.RADAR_MENU_OPEN_MGR, function()
            if FW.ShowManagerUI then FW.ShowManagerUI("enemies") end
        end)
    end)
end

local function CreateRadarFrame()
    local f = CreateFrame("Frame", "ForeverWatchRadarFrame", UIParent, "BackdropTemplate")
    f:SetSize(244, 38)
    if FW.settings.radarPoint then
        local p = FW.settings.radarPoint
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -220)
    end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if FW.settings and FW.settings.radarLocked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p1, _, p2, x, y = self:GetPoint()
        FW.settings.radarPoint = { p1, p2, math.floor(x + 0.5), math.floor(y + 0.5) }
    end)

    f:SetBackdrop({
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 128, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.20, 0.19, 0.22, 0.90)
    f:SetBackdropBorderColor(0.75, 0.62, 0.30, 0.95)

    -- Header bar using Blizzard's modern Forever tracker header texture
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    f.header = header

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetAtlas("ui-damagemeters-header-bar", false)

    local headerIcon = header:CreateTexture(nil, "OVERLAY")
    headerIcon:SetSize(16, 16)
    headerIcon:SetPoint("LEFT", header, "LEFT", 8, 0)
    FW.ApplyIconToTexture(headerIcon, FW.ICONS.DANGER_SWORD)

    local headerTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTitle:SetPoint("LEFT", headerIcon, "RIGHT", 5, 0)
    headerTitle:SetText(string.format(L.RADAR_TITLE_SAFE, 0))
    f.headerTitle = headerTitle

    -- Collapse/Expand icon button (native Blizzard quest tracker button with hover glow)
    local btnMin = CreateFrame("Button", nil, header)
    btnMin:SetSize(18, 18)
    btnMin:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    f.btnMin = btnMin

    local function UpdateCollapseButtonArt(btn)
        if FW.settings.radarCollapsed then
            btn:SetNormalAtlas("ui-questtrackerbutton-expand-all")
            btn:SetPushedAtlas("ui-questtrackerbutton-expand-all-pressed")
        else
            btn:SetNormalAtlas("ui-questtrackerbutton-collapse-all")
            btn:SetPushedAtlas("ui-questtrackerbutton-collapse-all-pressed")
        end
    end
    btnMin:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
    UpdateCollapseButtonArt(btnMin)

    btnMin:SetScript("OnClick", function(self)
        if FW.settings and FW.settings.radarLocked then return end
        FW.settings.radarCollapsed = not FW.settings.radarCollapsed
        UpdateCollapseButtonArt(self)
        FW.RefreshRadar()
    end)
    btnMin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(FW.settings.radarCollapsed and L.RADAR_EXPAND_TT or L.RADAR_COLLAPSE_TT)
        GameTooltip:Show()
    end)
    btnMin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Settings Gear icon button (native Blizzard Forever HD gear with hover & pressed states)
    local btnMgr = CreateFrame("Button", nil, header)
    btnMgr:SetSize(22, 22)
    btnMgr:SetPoint("RIGHT", btnMin, "LEFT", -3, 0)
    f.btnMgr = btnMgr
    btnMgr.icon = btnMgr:CreateTexture(nil, "ARTWORK")
    btnMgr.icon:SetAllPoints()
    btnMgr.icon:SetAtlas("common-dropdown-a-button-settings-shadowless", false)

    btnMgr:SetScript("OnEnter", function(self)
        self.icon:SetAtlas("common-dropdown-a-button-settings-hover-shadowless", false)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L.RADAR_SETTINGS_TT_TITLE, 1, 0.82, 0)
        GameTooltip:AddLine(L.RADAR_SETTINGS_TT_DESC, 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    btnMgr:SetScript("OnLeave", function(self)
        self.icon:SetAtlas("common-dropdown-a-button-settings-shadowless", false)
        GameTooltip:Hide()
    end)
    btnMgr:SetScript("OnMouseDown", function(self)
        self.icon:SetAtlas("common-dropdown-a-button-settings-pressed-shadowless", false)
    end)
    btnMgr:SetScript("OnMouseUp", function(self)
        if self:IsMouseOver() then
            self.icon:SetAtlas("common-dropdown-a-button-settings-hover-shadowless", false)
        else
            self.icon:SetAtlas("common-dropdown-a-button-settings-shadowless", false)
        end
    end)
    btnMgr:SetScript("OnClick", function()
        if FW.settings and FW.settings.radarLocked then return end
        if FW.ToggleManagerUI then FW.ToggleManagerUI() end
    end)

    -- Lock/Unlock button (distinct framed button: unpinned gray when unlocked, gold padlock when locked)
    -- When locked: panel becomes semi-transparent and ONLY this lock button stays interactive
    local btnLock = CreateFrame("Button", nil, header, "BackdropTemplate")
    btnLock:SetSize(20, 20)
    btnLock:SetPoint("RIGHT", btnMgr, "LEFT", -4, 0)
    btnLock:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btnLock.icon = btnLock:CreateTexture(nil, "ARTWORK")
    btnLock.icon:SetSize(13, 13)
    btnLock.icon:SetPoint("CENTER", btnLock, "CENTER", 0, 0)
    btnLock:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
    f.btnLock = btnLock

    btnLock:SetScript("OnClick", function()
        FW.settings.radarLocked = not FW.settings.radarLocked
        FW.ApplyRadarLockState()
        if FW.RefreshManagerUI then FW.RefreshManagerUI() end
        FW.Print(string.format(L.CMD_LOCK_TOGGLED, FW.settings.radarLocked and ("|cffFFD100" .. L.LOCKED .. "|r") or ("|cff4CFF6B" .. L.UNLOCKED .. "|r")))
    end)
    btnLock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if FW.settings.radarLocked then
            GameTooltip:SetText(L.RADAR_UNLOCK_TT_TITLE, 1, 0.82, 0)
            GameTooltip:AddLine(L.RADAR_UNLOCK_TT_DESC, 0.85, 0.85, 0.85, true)
        else
            GameTooltip:SetText(L.RADAR_LOCK_TT_TITLE, 1, 0.82, 0)
            GameTooltip:AddLine(L.RADAR_LOCK_TT_DESC, 0.85, 0.85, 0.85, true)
        end
        GameTooltip:Show()
    end)
    btnLock:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Empty state text
    local emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOP", header, "BOTTOM", 0, -9)
    emptyText:SetText(L.RADAR_EMPTY)
    f.emptyText = emptyText

    -- Overflow footer text when > MAX_RADAR_ROWS enemies are nearby
    local moreText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moreText:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
    moreText:Hide()
    f.moreText = moreText

    -- Pre-create row buttons
    for i = 1, MAX_RADAR_ROWS do
        local row = CreateFrame("Button", nil, f, "BackdropTemplate")
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 2, -4 - (i - 1) * 23)
        row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -2, -4 - (i - 1) * 23)
        row:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" })
        row:SetBackdropColor(0.12, 0.12, 0.15, 0.72)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.45)

        local icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.icon = icon

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        nameText:SetWidth(128)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        statusText:SetJustifyH("RIGHT")
        row.statusText = statusText

        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(FW.ColorizeName(FW.GetDisplayName(e.key), e.class))
            if e.rec then
                GameTooltip:AddLine(string.format(L.RADAR_TT_STATUS, FW.GetDangerLabel(e.rec)), 1, 1, 1)
                GameTooltip:AddLine(string.format(L.RADAR_TT_STATS, e.rec.attacks or 0, e.rec.kills or 0), 0.9, 0.9, 0.9)
                if (e.rec.killedMe or 0) > 0 then
                    GameTooltip:AddLine(string.format(L.RADAR_TT_KILLED_ME, e.rec.killedMe), 0.95, 0.35, 1)
                end
                if e.rec.lastEvent and e.rec.lastEvent ~= "" then
                    GameTooltip:AddLine(string.format(L.RADAR_TT_RECENT, e.rec.lastEvent), 1, 0.82, 0)
                end
                if e.rec.note and e.rec.note ~= "" then
                    GameTooltip:AddLine(string.format(L.RADAR_TT_NOTE, e.rec.note), 0.85, 0.85, 0.85, true)
                end
            else
                GameTooltip:AddLine(L.RADAR_TT_NORMAL, 0.8, 0.8, 0.8)
            end
            local tagRec = FW.FindTagRecord(e.key, e.snap and e.snap.guid)
            if tagRec then
                local cInfo = FW.GetTagColorInfo(tagRec.color)
                local tagStr = FW.FormatTagsInline(tagRec)
                if tagStr ~= "" then
                    GameTooltip:AddLine(string.format(L.TT_TAGS_FMT, FW.GetTagIconMarkup(14), cInfo.hex, "[" .. tagStr .. "]"), 1, 1, 1, true)
                end
                if tagRec.note and tagRec.note ~= "" then
                    GameTooltip:AddLine(string.format(L.TT_NOTE_FMT, tagRec.note), 0.9, 0.9, 0.9, true)
                end
            end
            GameTooltip:AddLine(L.RADAR_TT_RCLICK, 0.55, 0.55, 0.55)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" and self.entry then
                OpenRadarRowMenu(self, self.entry)
            end
        end)

        row:Hide()
        radarRows[i] = row
    end

    return f
end

function FW.ApplyRadarLockState()
    if not radarFrame then return end
    local locked = FW.settings and FW.settings.radarLocked == true

    local lockedAlpha = FW.settings and FW.settings.radarLockedAlpha or 0.55
    if lockedAlpha < 0.2 then lockedAlpha = 0.2 elseif lockedAlpha > 1.0 then lockedAlpha = 1.0 end

    radarFrame:SetMovable(not locked)
    radarFrame:EnableMouse(not locked)
    radarFrame:SetAlpha(locked and lockedAlpha or 1.0)

    for i = 1, MAX_RADAR_ROWS do
        if radarRows[i] then
            radarRows[i]:EnableMouse(not locked)
        end
    end

    -- When locked, ONLY the lock button remains interactive; hide/disable Gear & Collapse
    if radarFrame.btnMgr then
        radarFrame.btnMgr:EnableMouse(not locked)
        radarFrame.btnMgr:SetShown(not locked)
    end
    if radarFrame.btnMin then
        radarFrame.btnMin:EnableMouse(not locked)
        radarFrame.btnMin:SetShown(not locked)
    end

    if radarFrame.btnLock and radarFrame.btnLock.icon then
        local btn = radarFrame.btnLock
        local ico = btn.icon
        btn:ClearAllPoints()
        if locked then
            btn:SetPoint("RIGHT", radarFrame.header, "RIGHT", -6, 0)
            btn:SetBackdropColor(0.42, 0.14, 0.08, 0.95)
            btn:SetBackdropBorderColor(1.0, 0.78, 0.18, 1.0)
            ico:SetAtlas("QuestSharing-Padlock", false)
            ico:SetDesaturated(false)
            ico:SetVertexColor(1.0, 0.88, 0.30, 1.0)
        else
            btn:SetPoint("RIGHT", radarFrame.btnMgr, "LEFT", -4, 0)
            btn:SetBackdropColor(0.14, 0.14, 0.18, 0.90)
            btn:SetBackdropBorderColor(0.58, 0.58, 0.65, 0.90)
            ico:SetAtlas("friends-icon-pinned-dis", false)
            ico:SetDesaturated(false)
            ico:SetVertexColor(0.85, 0.88, 0.92, 0.95)
        end
    end
end

function FW.ScheduleRadarRefresh()
    if not radarFrame or not FW.settings or not FW.settings.enableRadar then return end
    local now = GetTime()
    if (now - lastRadarRefresh) >= 0.25 then
        FW.RefreshRadar()
        return
    end
    if not radarRefreshPending then
        radarRefreshPending = true
        C_Timer.After(0.25, function()
            radarRefreshPending = false
            FW.RefreshRadar()
        end)
    end
end

function FW.RefreshRadar()
    if not radarFrame then return end
    lastRadarRefresh = GetTime()
    FW.ApplyRadarLockState()
    if not FW.settings.enableRadar then
        radarFrame:Hide()
        return
    end
    radarFrame:Show()

    local list = {}
    local dangerCount = 0
    local nemesisCount = 0
    for key, snap in pairs(liveEnemies) do
        local rec = FW.FindEnemyRecord(key, snap.guid, snap.realm)
        if rec or FW.settings.radarShowNormalEnemy then
            if rec then
                dangerCount = dangerCount + 1
                if rec.isNemesis then nemesisCount = nemesisCount + 1 end
            end
            local score = 0
            if rec then
                score = (rec.isNemesis and 1000 or 0) + (FW.GetDangerTier(rec).level * 100) + (rec.kills or 0)
            end
            list[#list + 1] = {
                key = key,
                class = snap.class or (rec and rec.class),
                level = snap.level or (rec and rec.level) or 0,
                snap = snap,
                rec = rec,
                score = score,
            }
        end
    end

    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.snap.lastSeen or 0) > (b.snap.lastSeen or 0)
    end)

    if nemesisCount > 0 then
        radarFrame.headerTitle:SetText(string.format(L.RADAR_TITLE_NEMESIS, dangerCount, nemesisCount))
        radarFrame:SetBackdropBorderColor(0.90, 0.25, 0.95, 1)
    elseif dangerCount > 0 then
        radarFrame.headerTitle:SetText(string.format(L.RADAR_TITLE_DANGER, dangerCount))
        radarFrame:SetBackdropBorderColor(0.95, 0.25, 0.20, 1)
    else
        radarFrame.headerTitle:SetText(string.format(L.RADAR_TITLE_SAFE, #list))
        radarFrame:SetBackdropBorderColor(0.75, 0.62, 0.30, 0.95)
    end

    if FW.settings.radarCollapsed then
        radarFrame.emptyText:Hide()
        radarFrame.moreText:Hide()
        for i = 1, MAX_RADAR_ROWS do
            radarRows[i]:Hide()
        end
        radarFrame:SetHeight(35)
        return
    end

    local shown = math.min(#list, MAX_RADAR_ROWS)
    if shown == 0 then
        radarFrame.emptyText:Show()
        radarFrame.moreText:Hide()
        for i = 1, MAX_RADAR_ROWS do
            radarRows[i]:Hide()
        end
        radarFrame:SetHeight(60)
        return
    end

    radarFrame.emptyText:Hide()
    for i = 1, MAX_RADAR_ROWS do
        local row = radarRows[i]
        local e = list[i]
        if e then
            row.entry = e
            local lvlStr = (e.level and e.level > 0) and ("|cffAAAAAA" .. e.level .. "|r ") or ""
            row.nameText:SetText(lvlStr .. FW.ColorizeName(FW.GetDisplayName(e.key), e.class))
            if e.rec then
                if e.rec.isNemesis then
                    FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
                    row.icon:SetVertexColor(1, 0.65, 1, 1)
                    row:SetBackdropColor(0.28, 0.08, 0.30, 0.85)
                    row.statusText:SetText("|cffE040FB" .. L.NEMESIS .. "|r")
                else
                    local tier = FW.GetDangerTier(e.rec)
                    FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
                    row.icon:SetVertexColor(1, 0.85, 0.70, 1)
                    row:SetBackdropColor(0.28, 0.11, 0.08, 0.85)
                    row.statusText:SetText(string.format("|cff%sLv.%d|r", tier.hex, tier.level))
                end
            else
                FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
                row.icon:SetVertexColor(0.75, 0.75, 0.75, 0.85)
                row:SetBackdropColor(0.12, 0.12, 0.15, 0.72)
                row.statusText:SetText(L.RADAR_HOSTILE)
            end
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end

    local extra = #list - shown
    if extra > 0 then
        radarFrame.moreText:SetText(string.format(L.RADAR_MORE, extra))
        radarFrame.moreText:Show()
        radarFrame:SetHeight(38 + shown * 23 + 22)
    else
        radarFrame.moreText:Hide()
        radarFrame:SetHeight(38 + shown * 23 + 6)
    end
end

-- ============================================================
-- Event Registration & Init
-- ============================================================

function FW.InitDangerMonitor()
    for i = 1, MAX_ALERT_SLOTS do
        alertBanners[i] = CreateAlertBannerSlot(i)
    end
    alertOverflowBar = CreateAlertOverflowBar()
    radarFrame = CreateRadarFrame()
    FW.RefreshRadar()

    local evFrame = CreateFrame("Frame")
    evFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    evFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    evFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    evFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    evFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    evFrame:RegisterEvent("UNIT_TARGET")
    evFrame:RegisterEvent("UNIT_HEALTH")
    evFrame:RegisterEvent("UNIT_FLAGS")
    evFrame:RegisterEvent("UNIT_COMBAT")
    evFrame:RegisterEvent("UNIT_SPELLCAST_START")
    evFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    evFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    evFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    evFrame:RegisterEvent("PLAYER_DEAD")
    evFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

    evFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
        if not FW.settings or not FW.settings.enableMonitor then return end

        if event == "NAME_PLATE_UNIT_ADDED" then
            ScanUnitAndTarget(arg1)
            FW.ScheduleRadarRefresh()

        elseif event == "PLAYER_TARGET_CHANGED" then
            ScanUnitAndTarget("target")

        elseif event == "PLAYER_FOCUS_CHANGED" then
            ScanUnitAndTarget("focus")

        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            ScanUnitAndTarget("mouseover")

        elseif event == "UNIT_TARGET" or event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
            if arg1 then
                ScanUnitAndTarget(arg1)
            end

        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
            if arg1 and IsEnemyPlayerUnit(arg1) then
                local snap = InspectEnemyUnit(arg1)
                if snap then
                    local tUnit = arg1 .. "target"
                    if IsFriendlyPlayerUnit(tUnit) and not IsUnitDeadSafe(tUnit) then
                        local tInfo = FW.GetUnitIdentity(tUnit)
                        if tInfo then
                            NoteRecentAttacker(tInfo.key, tInfo.name, snap, "spellcast")
                        end
                    end
                end
            end

        elseif event == "UNIT_COMBAT" then
            -- arg1 = unit, arg2 = action ("WOUND", "HEAL", "DODGE", etc.)
            if arg1 and FW.CanAccess(arg2) and arg2 == "WOUND" and IsFriendlyPlayerUnit(arg1) then
                local fInfo = InspectFriendlyUnit(arg1)
                if fInfo then
                    local now = GetTime()
                    for _, snap in pairs(liveEnemies) do
                        if (now - snap.lastSeen) <= 4 and snap.inCombat and snap.targetKey == fInfo.key then
                            NoteRecentAttacker(fInfo.key, fInfo.name, snap, "wound")
                        end
                    end
                end
            end

        elseif event == "PLAYER_REGEN_DISABLED" then
            ScanAllNearbyUnits()
            if FW.myKey then
                local now = GetTime()
                for _, snap in pairs(liveEnemies) do
                    if (now - snap.lastSeen) <= 3 and snap.inCombat and snap.targetKey == FW.myKey then
                        NoteRecentAttacker(FW.myKey, FW.myShortName, snap, "engage_me")
                    end
                end
            end

        elseif event == "PLAYER_DEAD" then
            HandlePlayerDeath(false)

        elseif event == "ZONE_CHANGED_NEW_AREA" then
            wipe(liveEnemies)
            wipe(friendlyState)
            wipe(recentAttackers)
            FW.RefreshRadar()
        end
    end)

    -- Lightweight continuous scanner (every 0.4s)
    C_Timer.NewTicker(0.4, ScanAllNearbyUnits)
end
