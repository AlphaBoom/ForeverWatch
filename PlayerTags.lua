local _, FW = ...
local L = FW.L

local tagDialog

-- ============================================================
-- Tag Parsing & Storage CRUD
-- ============================================================

function FW.ParseTagString(raw)
    local result = {}
    local seen = {}
    if type(raw) ~= "string" then return result end
    local normalized = raw:gsub("，", ","):gsub("、", ","):gsub("；", ","):gsub(";", ","):gsub("/", ","):gsub("|", ",")
    for token in normalized:gmatch("[^,]+") do
        local t = FW.Trim(token)
        if t ~= "" and not seen[t] then
            seen[t] = true
            result[#result + 1] = t
        end
    end
    return result
end

function FW.SavePlayerTag(key, tagsList, note, colorId, guid, classFile)
    if not key or key == "" then return end
    if FW.IsPlayerSelf(nil, key, guid) then
        FW.Print(L.CMD_SELF_TAG_DENIED)
        return
    end
    note = FW.Trim(note or "")

    if (not tagsList or #tagsList == 0) and note == "" then
        FW.DeletePlayerTag(key)
        return
    end

    local existing = FW.db.tags[key]
    local rec = existing or {
        key = key,
        name = FW.GetShortName(key),
        createdAt = time(),
    }

    rec.tags = tagsList or {}
    rec.note = note
    rec.color = colorId or (existing and existing.color) or "GOLD"
    rec.updatedAt = time()
    if guid and FW.CanAccess(guid) and guid ~= "" then
        rec.guid = guid
        FW.db.guidToKey[guid] = key
    end
    if classFile and FW.CanAccess(classFile) and classFile ~= "" then
        rec.class = classFile
    end

    FW.db.tags[key] = rec
    FW.RebuildIndexes()
    FW.RefreshAllUI()

    local colorInfo = FW.GetTagColorInfo(rec.color)
    local tagStr = FW.FormatTagsInline(rec)
    if tagStr == "" then tagStr = L.TAG_NOTE_FALLBACK end
    FW.Print(string.format(L.TAG_SAVED_MSG,
        FW.GetTagIconMarkup(14),
        FW.ColorizeName(FW.GetDisplayName(key), rec.class),
        colorInfo.hex,
        tagStr))
end

function FW.DeletePlayerTag(key)
    if not key or not FW.db.tags[key] then return end
    local classFile = FW.db.tags[key].class
    FW.db.tags[key] = nil
    FW.RebuildIndexes()
    FW.RefreshAllUI()
    FW.Print(string.format(L.TAG_DELETED_MSG, FW.ColorizeName(FW.GetDisplayName(key), classFile)))
end

-- ============================================================
-- Tag Editor Dialog UI (Native Blizzard BasicFrameTemplateWithInset)
-- ============================================================

local function RefreshPresetChipStates()
    if not tagDialog or not tagDialog.chips then return end
    local currentTags = FW.ParseTagString(tagDialog.tagInput:GetText() or "")
    local active = {}
    for _, t in ipairs(currentTags) do active[t] = true end

    for _, chip in ipairs(tagDialog.chips) do
        if chip:IsShown() then
            if active[chip.tagText] then
                chip:SetBackdropColor(0.36, 0.25, 0.04, 0.96)
                chip:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
                chip.label:SetTextColor(1.0, 0.92, 0.35)
            else
                chip:SetBackdropColor(0.14, 0.13, 0.15, 0.90)
                chip:SetBackdropBorderColor(0.45, 0.42, 0.38, 0.85)
                chip.label:SetTextColor(0.88, 0.86, 0.82)
            end
        end
    end
end

local function RefreshColorSwatches()
    if not tagDialog or not tagDialog.swatches then return end
    for _, sw in ipairs(tagDialog.swatches) do
        if sw.colorInfo.id == tagDialog.selectedColor then
            sw.ring:Show()
        else
            sw.ring:Hide()
        end
    end
end

local function RebuildPresetChips()
    if not tagDialog then return end
    tagDialog.chips = tagDialog.chips or {}
    for _, c in ipairs(tagDialog.chips) do
        c:Hide()
    end

    local presets = FW.GetPresetTags()
    local x, y = 0, 0
    local maxWidth = 356
    for i, tagText in ipairs(presets) do
        local chip = tagDialog.chips[i]
        if not chip then
            chip = CreateFrame("Button", nil, tagDialog.chipContainer, "BackdropTemplate")
            chip:SetHeight(24)
            chip:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            local hl = chip:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
            hl:SetBlendMode("ADD")
            hl:SetAlpha(0.35)

            local lbl = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lbl:SetPoint("CENTER", 0, 0)
            chip.label = lbl
            chip:SetScript("OnClick", function(self)
                local list = FW.ParseTagString(tagDialog.tagInput:GetText() or "")
                local foundIdx = nil
                for idx, val in ipairs(list) do
                    if val == self.tagText then
                        foundIdx = idx
                        break
                    end
                end
                if foundIdx then
                    table.remove(list, foundIdx)
                else
                    list[#list + 1] = self.tagText
                end
                tagDialog.tagInput:SetText(table.concat(list, ", "))
                RefreshPresetChipStates()
            end)
            tagDialog.chips[i] = chip
        end

        chip.tagText = tagText
        chip.label:SetText(tagText)
        local w = math.max(58, math.ceil(chip.label:GetStringWidth() + 20))
        if x > 0 and (x + w) > maxWidth then
            x = 0
            y = y - 28
        end
        chip:ClearAllPoints()
        chip:SetSize(w, 24)
        chip:SetPoint("TOPLEFT", tagDialog.chipContainer, "TOPLEFT", x, y)
        chip:Show()
        x = x + w + 6
    end
    RefreshPresetChipStates()
end

local function CreateBeveledEditBox(parent, width, height, maxLetters)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width, height)
    holder:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    holder:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    holder:SetBackdropBorderColor(0.60, 0.52, 0.34, 0.95)

    local eb = CreateFrame("EditBox", nil, holder)
    eb:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -4)
    eb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 4)
    eb:SetFontObject("ChatFontNormal")
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(maxLetters or 80)
    return holder, eb
end

local function CreateTagDialog()
    local f = CreateFrame("Frame", "ForeverWatchTagDialog", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(412, 376)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "ForeverWatchTagDialog")

    if f.TitleText then
        f.TitleText:SetText(FW.GetEditIconMarkup(14) .. " " .. L.TAG_DIALOG_TITLE)
    end

    -- Rich WoW dark rock backdrop inside Inset
    local insetParent = f.Inset or f
    local rockBg = insetParent:CreateTexture(nil, "BACKGROUND")
    rockBg:SetPoint("TOPLEFT", insetParent, "TOPLEFT", 3, -3)
    rockBg:SetPoint("BOTTOMRIGHT", insetParent, "BOTTOMRIGHT", -3, 3)
    rockBg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    rockBg:SetHorizTile(true)
    rockBg:SetVertTile(true)
    rockBg:SetVertexColor(0.65, 0.65, 0.70, 0.95)

    -- Target player banner strip
    local targetBar = CreateFrame("Frame", nil, insetParent, "BackdropTemplate")
    targetBar:SetHeight(30)
    targetBar:SetPoint("TOPLEFT", insetParent, "TOPLEFT", 10, -10)
    targetBar:SetPoint("TOPRIGHT", insetParent, "TOPRIGHT", -10, -10)
    targetBar:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    targetBar:SetBackdropBorderColor(0.75, 0.60, 0.25, 0.90)

    local targetIcon = targetBar:CreateTexture(nil, "OVERLAY")
    targetIcon:SetSize(16, 16)
    targetIcon:SetPoint("LEFT", targetBar, "LEFT", 8, 0)
    FW.ApplyIconToTexture(targetIcon, FW.GetTagIconDef())
    f.targetIcon = targetIcon

    local targetLabel = targetBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLabel:SetPoint("LEFT", targetIcon, "RIGHT", 6, 0)
    targetLabel:SetText(string.format(L.TAG_TARGET_LABEL, ""))
    f.targetLabel = targetLabel

    -- Tag Input Label
    local tagLbl = insetParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagLbl:SetPoint("TOPLEFT", targetBar, "BOTTOMLEFT", 2, -10)
    tagLbl:SetText(L.TAG_INPUT_LABEL)

    local tagInputBg, tagInput = CreateBeveledEditBox(insetParent, 368, 30, 80)
    tagInputBg:SetPoint("TOPLEFT", tagLbl, "BOTTOMLEFT", -2, -5)
    tagInput:SetScript("OnTextChanged", function() RefreshPresetChipStates() end)
    tagInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    tagInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        f.saveBtn:Click()
    end)
    f.tagInput = tagInput

    -- Quick preset chips container
    local presetLbl = insetParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    presetLbl:SetPoint("TOPLEFT", tagInputBg, "BOTTOMLEFT", 2, -10)
    presetLbl:SetText(L.TAG_PRESET_LABEL)

    local chipContainer = CreateFrame("Frame", nil, insetParent)
    chipContainer:SetSize(368, 86)
    chipContainer:SetPoint("TOPLEFT", presetLbl, "BOTTOMLEFT", -2, -6)
    f.chipContainer = chipContainer

    -- Color selector
    local colorLbl = insetParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLbl:SetPoint("TOPLEFT", chipContainer, "BOTTOMLEFT", 2, -6)
    colorLbl:SetText(L.TAG_COLOR_LABEL)

    f.swatches = {}
    for i, cInfo in ipairs(FW.TAG_COLORS) do
        local sw = CreateFrame("Button", nil, insetParent, "BackdropTemplate")
        sw:SetSize(24, 20)
        sw:SetPoint("LEFT", colorLbl, "RIGHT", 6 + (i - 1) * 30, 0)
        sw:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        sw:SetBackdropColor(cInfo.r, cInfo.g, cInfo.b, 1)
        sw:SetBackdropBorderColor(0.35, 0.30, 0.20, 0.9)

        local ring = sw:CreateTexture(nil, "OVERLAY")
        ring:SetPoint("TOPLEFT", sw, "TOPLEFT", -3, 3)
        ring:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 3, -3)
        ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(1, 0.9, 0.3, 1)
        ring:Hide()
        sw.ring = ring

        sw.colorInfo = cInfo
        sw:SetScript("OnClick", function()
            f.selectedColor = cInfo.id
            RefreshColorSwatches()
        end)
        f.swatches[i] = sw
    end

    -- Optional Note Input
    local noteLbl = insetParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLbl:SetPoint("TOPLEFT", colorLbl, "BOTTOMLEFT", 0, -14)
    noteLbl:SetText(L.TAG_NOTE_LABEL)

    local noteBg, noteInput = CreateBeveledEditBox(insetParent, 368, 30, 140)
    noteBg:SetPoint("TOPLEFT", noteLbl, "BOTTOMLEFT", -2, -5)
    noteInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    noteInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        f.saveBtn:Click()
    end)
    f.noteInput = noteInput

    -- Action Buttons (native WoW red metal buttons, generous widths)
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(108, 24)
    saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    saveBtn:SetText(L.TAG_BTN_SAVE)
    saveBtn:SetScript("OnClick", function()
        local tagsList = FW.ParseTagString(f.tagInput:GetText() or "")
        local note = f.noteInput:GetText() or ""
        FW.SavePlayerTag(f.targetKey, tagsList, note, f.selectedColor, f.targetGuid, f.targetClass)
        f:Hide()
    end)
    f.saveBtn = saveBtn

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(108, 24)
    clearBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
    clearBtn:SetText(L.TAG_BTN_CLEAR)
    clearBtn:SetScript("OnClick", function()
        if f.targetKey then
            FW.DeletePlayerTag(f.targetKey)
        end
        f:Hide()
    end)
    f.clearBtn = clearBtn

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(92, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    cancelBtn:SetText(L.TAG_BTN_CANCEL)
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f:Hide()
    return f
end

function FW.OpenTagDialog(playerKey, guid, classFile)
    if not playerKey or playerKey == "" then return end
    local key = FW.NormalizePlayerKey(playerKey)
    if not key then return end
    if FW.IsPlayerSelf(nil, key, guid) then
        FW.Print(L.CMD_SELF_TAG_DENIED)
        return
    end

    if not tagDialog then
        tagDialog = CreateTagDialog()
    end

    local existing = FW.FindTagRecord(key, guid)
    if existing then
        key = existing.key
        classFile = classFile or existing.class
        guid = guid or existing.guid
    end

    tagDialog.targetKey = key
    tagDialog.targetGuid = guid
    tagDialog.targetClass = classFile
    tagDialog.selectedColor = (existing and existing.color) or "GOLD"

    FW.ApplyIconToTexture(tagDialog.targetIcon, FW.GetTagIconDef())
    tagDialog.targetLabel:SetText(string.format(L.TAG_TARGET_LABEL, FW.ColorizeName(FW.GetDisplayName(key), classFile)))
    tagDialog.tagInput:SetText(existing and existing.tags and table.concat(existing.tags, ", ") or "")
    tagDialog.noteInput:SetText(existing and existing.note or "")

    RebuildPresetChips()
    RefreshColorSwatches()
    tagDialog:Show()
    tagDialog.tagInput:SetFocus()
end

-- ============================================================
-- Right-Click Context Menu Hook (Forever 16001 Menu.ModifyMenu)
-- ============================================================

local function IsSelfIdentity(unit, guid, key, short, realm)
    if FW.IsPlayerSelf(unit, key, guid) then
        return true
    end
    if short and FW.myShortName and short == FW.myShortName
        and (not realm or realm == "" or realm == FW.myLastNameOrRealm or (not FW.mySpaceName and realm == FW.GetMyRealm())) then
        return true
    end
    return false
end

local function ExtractPlayerFromContextData(contextData, menuTag)
    if type(contextData) ~= "table" then return nil end

    local unit = contextData.unit
    local guid = nil
    local rawName = contextData.name
    local server = contextData.server
    local classFile = nil
    local isEnemy = (menuTag == "MENU_UNIT_ENEMY_PLAYER")

    -- 1. Unit token (target, focus, party, raid, player frame)
    if unit and FW.SafeBool(FW.SafeUnitCall(UnitExists, unit)) then
        if FW.SafeBool(FW.SafeUnitCall(UnitIsUnit, unit, "player")) then
            return nil -- Never show tag option on self
        end
        if not FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, unit)) then
            return nil -- Never show player tag menu on NPCs/mobs
        end
        if FW.SafeBool(FW.SafeUnitCall(UnitIsEnemy, "player", unit)) then
            isEnemy = true
        end
        local uName, uRealm = FW.SafeUnitCall(UnitName, unit)
        if uName then
            rawName = uName
            server = uRealm
        end
        guid = FW.SafeUnitCall(UnitGUID, unit)
        local _, cls = FW.SafeUnitCall(UnitClass, unit)
        classFile = cls
    end

    -- 2. Recent Allies list entry (FriendsFrame -> Recent Allies)
    if contextData.recentAllyData and type(contextData.recentAllyData) == "table" then
        local cd = contextData.recentAllyData.characterData
        if type(cd) == "table" then
            if FW.CanAccess(cd.fullName) and cd.fullName and cd.fullName ~= "" then
                rawName = cd.fullName
                server = nil
            elseif FW.CanAccess(cd.name) and cd.name and cd.name ~= "" then
                rawName = cd.name
                server = FW.CanAccess(cd.realmName) and cd.realmName or server
            end
            if FW.CanAccess(cd.guid) and cd.guid then
                guid = cd.guid
            end
            if not classFile and cd.classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
                local ok, ci = pcall(C_CreatureInfo.GetClassInfo, cd.classID)
                if ok and type(ci) == "table" and FW.CanAccess(ci.classFile) then
                    classFile = ci.classFile
                end
            end
        end
    end

    -- 3. Battle.net Friends list (prefer active WoW character name if playing WoW)
    if menuTag == "MENU_UNIT_BN_FRIEND" or menuTag == "MENU_UNIT_BN_FRIEND_OFFLINE" or contextData.bnetIDAccount then
        local accountInfo = contextData.accountInfo
        if not accountInfo and contextData.bnetIDAccount and C_BattleNet and C_BattleNet.GetAccountInfoByID then
            local ok, info = pcall(C_BattleNet.GetAccountInfoByID, contextData.bnetIDAccount)
            if ok and type(info) == "table" then
                accountInfo = info
            end
        end
        if type(accountInfo) == "table" then
            local ga = accountInfo.gameAccountInfo
            if type(ga) == "table" and FW.CanAccess(ga.characterName) and ga.characterName and ga.characterName ~= "" then
                rawName = ga.characterName
                server = FW.CanAccess(ga.realmName) and ga.realmName or nil
                if FW.CanAccess(ga.playerGuid) and ga.playerGuid then
                    guid = ga.playerGuid
                end
            elseif (not rawName or not FW.CanAccess(rawName) or rawName == "") and FW.CanAccess(accountInfo.accountName) then
                rawName = accountInfo.accountName
            end
        end
    end

    -- 4. GUID fallback via Blizzard helper
    if not guid and UnitPopupSharedUtil and UnitPopupSharedUtil.GetGUID then
        local ok, g = pcall(UnitPopupSharedUtil.GetGUID, contextData)
        if ok and FW.CanAccess(g) then
            guid = g
        end
    end

    if not rawName or not FW.CanAccess(rawName) or rawName == "" then
        return nil
    end

    if not classFile and guid and GetPlayerInfoByGUID then
        local ok, _, engClass = pcall(GetPlayerInfoByGUID, guid)
        if ok and FW.CanAccess(engClass) then
            classFile = engClass
        end
    end

    local key, short, realm = FW.NormalizePlayerKey(rawName, server)
    if not key then return nil end

    -- Never allow tagging self
    if IsSelfIdentity(unit, guid, key, short, realm) then
        return nil
    end

    return {
        key = key,
        name = short,
        realm = realm,
        guid = guid,
        class = classFile,
        isEnemy = isEnemy,
        unit = unit,
    }
end

local MENU_TAGS = {
    "MENU_UNIT_PLAYER",
    "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER",
    "MENU_UNIT_RAID",
    "MENU_UNIT_FRIEND",
    "MENU_UNIT_FRIEND_OFFLINE",
    "MENU_UNIT_BN_FRIEND",
    "MENU_UNIT_BN_FRIEND_OFFLINE",
    "MENU_UNIT_RECENT_ALLY",
    "MENU_UNIT_RECENT_ALLY_OFFLINE",
    "MENU_UNIT_GUILD",
    "MENU_UNIT_GUILD_OFFLINE",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_WORLD_STATE_SCORE",
    "MENU_UNIT_PVP_SCOREBOARD",
    "MENU_UNIT_TARGET",
    "MENU_UNIT_FOCUS",
    "MENU_UNIT_ENEMY_PLAYER",
}

function FW.InitPlayerTags()
    if not Menu or not Menu.ModifyMenu then
        FW.Print("|cffFF4444警告: 当前客户端未检测到 Menu.ModifyMenu，右键菜单功能不可用。|r")
        return
    end

    for _, menuTag in ipairs(MENU_TAGS) do
        Menu.ModifyMenu(menuTag, function(owner, rootDescription, contextData)
            local info = ExtractPlayerFromContextData(contextData, menuTag)
            if not info then return end

            rootDescription:CreateDivider()

            if info.isEnemy then
                -- 1-click Tag button for hostile players too
                local tagRec = FW.FindTagRecord(info.key, info.guid, info.realm)
                local tagBtnText
                if tagRec then
                    local summary = FW.FormatTagsInline(tagRec)
                    if #summary > 20 then summary = summary:sub(1, 20) .. "..." end
                    local cInfo = FW.GetTagColorInfo(tagRec.color)
                    tagBtnText = FW.GetEditIconMarkup(14) .. " " .. string.format(L.MENU_EDIT_TAG, cInfo.hex, summary ~= "" and summary or L.TAG_NOTE_FALLBACK)
                else
                    tagBtnText = FW.GetEditIconMarkup(14) .. " " .. L.MENU_ADD_TAG
                end
                rootDescription:CreateButton(tagBtnText, function()
                    FW.OpenTagDialog(info.key, info.guid, info.class)
                end)

                -- 1-click Mark/Unmark Nemesis button
                local enemyRec = FW.FindEnemyRecord(info.key, info.guid, info.realm)
                if enemyRec and enemyRec.isNemesis then
                    rootDescription:CreateButton(FW.GetEnemyIconMarkup(true, 14) .. " |cffE040FB" .. L.MENU_ENEMY_UNMARK_NEM .. "|r", function()
                        FW.SetEnemyNemesis(enemyRec.key, false)
                    end)
                else
                    rootDescription:CreateButton(FW.GetEnemyIconMarkup(true, 14) .. " |cffE040FB" .. L.MENU_ENEMY_MARK_NEM .. "|r", function()
                        FW.RecordEnemyAction(info, "manual_nemesis")
                    end)
                end

                -- Additional hostile threat actions submenu
                local submenu = rootDescription:CreateButton(FW.GetEnemyIconMarkup(false, 14) .. " " .. L.MENU_ENEMY_SUB)
                submenu:CreateButton(L.MENU_ENEMY_UPGRADE, function()
                    if enemyRec then
                        local cur = FW.GetDangerTier(enemyRec).level
                        FW.AdjustEnemyManualTier(enemyRec.key, math.min(#FW.DANGER_TIERS, cur + 1))
                    else
                        FW.RecordEnemyAction(info, "manual_danger")
                    end
                end)
                if enemyRec then
                    submenu:CreateButton(L.MENU_ENEMY_DELETE, function()
                        FW.DeleteEnemyRecord(enemyRec.key)
                    end)
                end
            else
                local tagRec = FW.FindTagRecord(info.key, info.guid, info.realm)
                local btnText
                if tagRec then
                    local summary = FW.FormatTagsInline(tagRec)
                    if #summary > 22 then summary = summary:sub(1, 22) .. "..." end
                    local cInfo = FW.GetTagColorInfo(tagRec.color)
                    btnText = FW.GetEditIconMarkup(14) .. " " .. string.format(L.MENU_EDIT_TAG, cInfo.hex, summary ~= "" and summary or L.TAG_NOTE_FALLBACK)
                else
                    btnText = FW.GetEditIconMarkup(14) .. " " .. L.MENU_ADD_TAG
                end

                rootDescription:CreateButton(btnText, function()
                    FW.OpenTagDialog(info.key, info.guid, info.class)
                end)
            end
        end)
    end
end
