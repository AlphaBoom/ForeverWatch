local _, FW = ...
local L = FW.L

local nameplateBadges = {} -- [nameplateFrame] = badgeFrame

-- ============================================================
-- 1. Tooltip Hooks (World Units + Friends List + Recent Allies)
-- ============================================================

local function DecorateTooltipTitle(tooltip, iconMarkup)
    if not tooltip or not tooltip.GetName or not iconMarkup or iconMarkup == "" then return end
    local ttName = tooltip:GetName()
    if not ttName then return end
    local line1 = _G[ttName .. "TextLeft1"]
    if not line1 or not line1.GetText then return end
    local ok, text = pcall(line1.GetText, line1)
    if not ok or not FW.CanAccess(text) or type(text) ~= "string" or text == "" then
        return
    end
    if not text:find(iconMarkup, 1, true) then
        line1:SetText(iconMarkup .. " " .. text)
    end
end

local function AppendTagLinesToTooltip(tooltip, tagRec, addBlankLine)
    if not tooltip or not tagRec then return end
    local tagIcon = FW.GetTagIconMarkup(14)
    DecorateTooltipTitle(tooltip, tagIcon)

    local cInfo = FW.GetTagColorInfo(tagRec.color)
    local tagLine = ""
    if tagRec.tags and #tagRec.tags > 0 then
        local chips = {}
        for _, t in ipairs(tagRec.tags) do
            chips[#chips + 1] = "[" .. t .. "]"
        end
        tagLine = table.concat(chips, " ")
    end

    if addBlankLine ~= false then
        tooltip:AddLine(" ")
    end
    if tagLine ~= "" then
        tooltip:AddLine(
            string.format(L.TT_TAGS_FMT, tagIcon, cInfo.hex, tagLine),
            1, 1, 1, true
        )
    else
        tooltip:AddLine(tagIcon .. L.TT_TAGGED_FALLBACK, 1, 1, 1)
    end
    if tagRec.note and tagRec.note ~= "" then
        tooltip:AddLine(string.format(L.TT_NOTE_FMT, tagRec.note), 0.92, 0.92, 0.95, true)
    end
end

local function ResolveTooltipUnit(tooltip, data)
    local unit = nil
    if tooltip and tooltip.GetUnit then
        local ok, _, u = pcall(tooltip.GetUnit, tooltip)
        if ok and FW.CanAccess(u) and type(u) == "string" and u ~= "" then
            unit = u
        end
    end

    local guid = nil
    if type(data) == "table" and not FW.IsSecret(data) and FW.CanAccess(data.guid) then
        guid = data.guid
    end

    if unit and FW.SafeBool(FW.SafeUnitCall(UnitExists, unit)) then
        if not FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, unit)) then
            return nil
        end
        local info = FW.GetUnitIdentity(unit)
        if not info then return nil end
        info.isEnemy = FW.SafeBool(FW.SafeUnitCall(UnitIsEnemy, "player", unit))
        info.isFriend = FW.SafeBool(FW.SafeUnitCall(UnitIsFriend, "player", unit))
            or FW.SafeBool(FW.SafeUnitCall(UnitIsUnit, unit, "player"))
        return info
    end

    if guid and type(guid) == "string" and guid:match("^Player%-") then
        local ok, _, engClass, _, _, _, pName, pRealm = pcall(GetPlayerInfoByGUID, guid)
        if ok and FW.CanAccess(pName) and type(pName) == "string" and pName ~= "" then
            local key, short, realm = FW.NormalizePlayerKey(pName, pRealm)
            if key then
                return {
                    key = key,
                    name = short,
                    realm = realm,
                    guid = guid,
                    class = FW.CanAccess(engClass) and engClass or nil,
                    isEnemy = false,
                    isFriend = false,
                }
            end
        end
    end

    return nil
end

local function OnUnitTooltip(tooltip, data)
    if not FW.settings or not FW.settings.enableTooltipTags then return end
    if not tooltip or tooltip ~= GameTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local info = ResolveTooltipUnit(tooltip, data)
    if not info then return end

    local addedAnything = false

    -- 1. Dangerous Enemy / Nemesis Record (for hostile players)
    local enemyRec = FW.FindEnemyRecord(info.key, info.guid, info.realm)
    if enemyRec and (info.isEnemy or not info.isFriend) then
        local iconMarkup = FW.GetEnemyIconMarkup(enemyRec.isNemesis, 14)
        DecorateTooltipTitle(tooltip, iconMarkup)

        tooltip:AddLine(" ")
        tooltip:AddLine(iconMarkup .. " " .. FW.GetDangerLabel(enemyRec), 1, 1, 1)

        local stats = string.format(L.TT_ENEMY_STATS,
            enemyRec.attacks or 0, enemyRec.kills or 0)
        if (enemyRec.killedMe or 0) > 0 then
            stats = stats .. string.format(L.TT_ENEMY_KILLED_ME, enemyRec.killedMe)
        end
        tooltip:AddLine(stats, 0.92, 0.92, 0.92)

        if enemyRec.lastEvent and enemyRec.lastEvent ~= "" then
            tooltip:AddLine(string.format(L.TT_ENEMY_RECENT, enemyRec.lastEvent, FW.FormatRelativeTime(enemyRec.lastSeen)), 0.85, 0.85, 0.85)
        end
        if enemyRec.note and enemyRec.note ~= "" then
            tooltip:AddLine(string.format(L.TT_NOTE_FMT, enemyRec.note), 0.92, 0.92, 0.95, true)
        end
        addedAnything = true
    end

    -- 2. Custom Player Tags (works for BOTH friendly AND hostile players!)
    local tagRec = FW.FindTagRecord(info.key, info.guid, info.realm)
    if tagRec then
        if info.guid and not tagRec.guid then
            tagRec.guid = info.guid
            FW.db.guidToKey[info.guid] = tagRec.key
        end
        if info.class and not tagRec.class then
            tagRec.class = info.class
        end
        AppendTagLinesToTooltip(tooltip, tagRec, not addedAnything)
        addedAnything = true
    end

    if addedAnything then
        tooltip:Show()
    end
end

local function HookSocialTooltips()
    -- Recent Allies modern card tooltip
    if RecentAlliesSocialCardMixin and RecentAlliesSocialCardMixin.BuildTooltip then
        hooksecurefunc(RecentAlliesSocialCardMixin, "BuildTooltip", function(self, tooltip)
            if not FW.settings or not FW.settings.enableTooltipTags then return end
            local cd = self and self.elementData and self.elementData.characterData
            if not cd then return end
            local tagRec = FW.FindTagRecord(cd.fullName or cd.name, cd.guid, cd.realmName)
            if tagRec then
                AppendTagLinesToTooltip(tooltip, tagRec, true)
            end
        end)
    end

    -- Recent Allies classic entry tooltip
    if RecentAlliesEntryMixin and RecentAlliesEntryMixin.ShowTooltip then
        hooksecurefunc(RecentAlliesEntryMixin, "ShowTooltip", function(self)
            if not FW.settings or not FW.settings.enableTooltipTags then return end
            local cd = self and self.elementData and self.elementData.characterData
            if not cd then return end
            local tagRec = FW.FindTagRecord(cd.fullName or cd.name, cd.guid, cd.realmName)
            if tagRec and GameTooltip and GameTooltip:IsShown() then
                AppendTagLinesToTooltip(GameTooltip, tagRec, true)
                GameTooltip:Show()
            end
        end)
    end

    -- Battle.net Friends card tooltip
    if FriendsListSocialCardMixin and FriendsListSocialCardMixin.BuildTooltip then
        hooksecurefunc(FriendsListSocialCardMixin, "BuildTooltip", function(self, tooltip)
            if not FW.settings or not FW.settings.enableTooltipTags then return end
            local acct = self and self.elementData and self.elementData.accountInfo
            if not acct then return end
            local ga = acct.gameAccountInfo
            local tagRec = nil
            if ga and ga.characterName and ga.characterName ~= "" then
                tagRec = FW.FindTagRecord(ga.characterName, ga.playerGuid, ga.realmName)
            end
            if not tagRec and acct.accountName then
                tagRec = FW.FindTagRecord(acct.accountName)
            end
            if tagRec then
                AppendTagLinesToTooltip(tooltip, tagRec, true)
            end
        end)
    end
end

local function InitTooltipHook()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(self)
            OnUnitTooltip(self, nil)
        end)
    end

    HookSocialTooltips()
end

-- ============================================================
-- 2. Chat Frame Sender Name Filter (Forever 16001 Native API)
-- ============================================================

local function OnDecorateSenderName(event, decoratedPlayerName, ...)
    if not FW.settings or not FW.settings.enableChatTags then
        return decoratedPlayerName
    end
    if not FW.CanAccess(decoratedPlayerName) or type(decoratedPlayerName) ~= "string" then
        return decoratedPlayerName
    end

    local senderName = select(2, ...)
    local senderGUID = select(12, ...)

    if not FW.CanAccess(senderName) and not FW.CanAccess(senderGUID) then
        return decoratedPlayerName
    end

    local tagRec = FW.FindTagRecord(
        FW.CanAccess(senderName) and senderName or nil,
        FW.CanAccess(senderGUID) and senderGUID or nil
    )
    if not tagRec then
        return decoratedPlayerName
    end

    local tagStr = FW.FormatTagsInline(tagRec)
    if tagStr == "" then
        if tagRec.note and tagRec.note ~= "" then
            tagStr = L.CHAT_NOTED
        else
            return decoratedPlayerName
        end
    end

    local cInfo = FW.GetTagColorInfo(tagRec.color)
    return decoratedPlayerName .. string.format("|cff%s(%s)|r", cInfo.hex, tagStr)
end

local function InitChatHook()
    if ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter then
        ChatFrameUtil.AddSenderNameFilter(OnDecorateSenderName)
    end
end

-- ============================================================
-- 3. NamePlate Compact Symbol Badge (Blizzard + BBP Compatible)
-- ============================================================

local function GetOrCreateNameplateBadge(plate)
    local badge = nameplateBadges[plate]
    if badge then return badge end

    local holder = CreateFrame("Frame", nil, plate)
    holder:SetSize(16, 16)
    holder:SetFrameLevel((plate:GetFrameLevel() or 1) + 20)
    holder:EnableMouse(false)

    local tex = holder:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(holder)
    holder.tex = tex

    holder:Hide()
    nameplateBadges[plate] = holder
    return holder
end

local function AnchorBadgeToPlate(badge, plate)
    local uf = plate.UnitFrame
    badge:ClearAllPoints()
    if uf then
        if uf.fakeName and uf.fakeName.IsShown and uf.fakeName:IsShown() then
            badge:SetPoint("RIGHT", uf.fakeName, "LEFT", -3, 0)
            return
        end
        if uf.name and uf.name.IsShown and uf.name:IsShown() then
            badge:SetPoint("RIGHT", uf.name, "LEFT", -3, 0)
            return
        end
        if uf.healthBar and uf.healthBar.IsShown and uf.healthBar:IsShown() then
            badge:SetPoint("BOTTOM", uf.healthBar, "TOP", 0, 2)
            return
        end
    end
    badge:SetPoint("BOTTOM", plate, "TOP", 0, 2)
end

function FW.UpdateNameplateBadge(plate, unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local badge = nameplateBadges[plate]

    if not FW.settings or not FW.settings.enableNameplateIcon then
        if badge then badge:Hide() end
        return
    end

    if not unit then
        unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    end
    if not unit or not FW.SafeBool(FW.SafeUnitCall(UnitExists, unit)) or not FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, unit)) then
        if badge then badge:Hide() end
        return
    end

    local info = FW.GetUnitIdentity(unit)
    if not info then
        if badge then badge:Hide() end
        return
    end

    local isEnemy = FW.SafeBool(FW.SafeUnitCall(UnitIsEnemy, "player", unit))

    if isEnemy then
        local enemyRec = FW.FindEnemyRecord(info.key, info.guid, info.realm)
        if enemyRec then
            badge = GetOrCreateNameplateBadge(plate)
            if enemyRec.isNemesis then
                badge:SetSize(16, 16)
                FW.ApplyIconToTexture(badge.tex, FW.ICONS.NEMESIS)
                badge.tex:SetVertexColor(1, 0.55, 1, 1)
            else
                local r, g, b = FW.GetDangerColor(enemyRec)
                badge:SetSize(15, 15)
                FW.ApplyIconToTexture(badge.tex, FW.ICONS.DANGER_SWORD)
                badge.tex:SetVertexColor(r, g, b, 1)
            end
            AnchorBadgeToPlate(badge, plate)
            badge:Show()
            return
        end
    end

    local tagRec = FW.FindTagRecord(info.key, info.guid, info.realm)
    if tagRec then
        badge = GetOrCreateNameplateBadge(plate)
        local cInfo = FW.GetTagColorInfo(tagRec.color)
        badge:SetSize(15, 15)
        FW.ApplyIconToTexture(badge.tex, FW.GetTagIconDef())
        if cInfo.id == "GOLD" then
            badge.tex:SetVertexColor(1, 1, 1, 1)
        else
            badge.tex:SetVertexColor(cInfo.r, cInfo.g, cInfo.b, 1)
        end
        AnchorBadgeToPlate(badge, plate)
        badge:Show()
        return
    end

    if badge then badge:Hide() end
end

local nameplateRefreshPending = false

local function DoRefreshAllNameplates()
    nameplateRefreshPending = false
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local plates = C_NamePlate.GetNamePlates()
    if not plates then return end
    for i = 1, #plates do
        local plate = plates[i]
        if plate then
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            FW.UpdateNameplateBadge(plate, unit)
        end
    end
end

function FW.RefreshAllNameplates()
    if nameplateRefreshPending then return end
    nameplateRefreshPending = true
    C_Timer.After(0.10, DoRefreshAllNameplates)
end

local function InitNameplateHook()
    local npFrame = CreateFrame("Frame")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    npFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    npFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    npFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" and unit then
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
            if plate then
                FW.UpdateNameplateBadge(plate, unit)
                C_Timer.After(0.05, function()
                    if plate and (not plate.IsForbidden or not plate:IsForbidden()) then
                        FW.UpdateNameplateBadge(plate, unit)
                    end
                end)
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" and unit then
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
            if plate and nameplateBadges[plate] then
                nameplateBadges[plate]:Hide()
            end
        elseif event == "PLAYER_TARGET_CHANGED" then
            FW.RefreshAllNameplates()
        end
    end)

    if CompactUnitFrame_UpdateName then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(unitFrame)
            if not unitFrame or (unitFrame.IsForbidden and unitFrame:IsForbidden()) then return end
            local unit = unitFrame.unit
            if unit and type(unit) == "string" and unit:match("^nameplate") then
                local plate = unitFrame:GetParent()
                if plate then
                    FW.UpdateNameplateBadge(plate, unit)
                end
            end
        end)
    end
end

-- ============================================================
-- Init
-- ============================================================

function FW.InitDisplayHooks()
    InitTooltipHook()
    InitChatHook()
    InitNameplateHook()
    FW.RefreshAllNameplates()
end
