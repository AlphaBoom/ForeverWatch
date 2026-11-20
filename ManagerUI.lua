local _, FW = ...
local L = FW.L

local managerFrame
local currentTab = "enemies"
local enemyFilterNemesisOnly = false
local searchText = ""

local TAB_INDEX = {
    enemies = 1,
    tags = 2,
    settings = 3,
}

local function SizeButtonToText(btn, minW, pad)
    local fs = btn and btn.GetFontString and btn:GetFontString()
    local w = minW or 60
    if fs then
        w = math.max(w, math.ceil(fs:GetStringWidth() + (pad or 28)))
    end
    btn:SetWidth(w)
    return w
end

local function CreateWowButton(parent, text, minW, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetHeight(h or 22)
    b:SetText(text)
    SizeButtonToText(b, minW or 64, 28)
    if onClick then
        b:SetScript("OnClick", onClick)
    end
    return b
end

local function CreateRowCard(parent, width, height)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetSize(width, height)
    row:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropColor(0.10, 0.10, 0.13, 0.88)
    row:SetBackdropBorderColor(0.50, 0.44, 0.30, 0.85)

    local hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hl:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0)
    row.hoverGlow = hl

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) self.hoverGlow:SetAlpha(0.28) end)
    row:SetScript("OnLeave", function(self) self.hoverGlow:SetAlpha(0) end)
    return row
end

local function CreateBeveledSearchBox(parent, width, height)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetSize(width, height)
    holder:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    holder:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    holder:SetBackdropBorderColor(0.60, 0.50, 0.30, 0.90)

    local eb = CreateFrame("EditBox", nil, holder)
    eb:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -3)
    eb:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -8, 3)
    eb:SetFontObject("ChatFontSmall")
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return holder, eb
end

-- ============================================================
-- Tab 1: Enemy Danger & Nemesis List
-- ============================================================

local function RefreshEnemiesTab()
    local panel = managerFrame.enemiesPanel
    if not panel then return end
    panel.rows = panel.rows or {}

    local list = {}
    local query = FW.Trim(searchText):lower()
    for key, rec in pairs(FW.db.enemies) do
        local matchFilter = (not enemyFilterNemesisOnly) or rec.isNemesis
        if matchFilter then
            local matchSearch = true
            if query ~= "" then
                local hay = (key .. " " .. (rec.lastZone or "") .. " " .. (rec.note or "") .. " " .. (rec.lastEvent or "")):lower()
                matchSearch = hay:find(query, 1, true) ~= nil
            end
            if matchSearch then
                local score = (rec.isNemesis and 10000 or 0) + FW.GetDangerTier(rec).level * 1000 + (rec.kills or 0) * 10
                list[#list + 1] = { key = key, rec = rec, score = score }
            end
        end
    end

    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.rec.lastSeen or 0) > (b.rec.lastSeen or 0)
    end)

    panel.countText:SetText(string.format(L.MGR_ENEMIES_COUNT, #list))

    local content = panel.scrollChild
    local rowHeight = 52
    for i, item in ipairs(list) do
        local row = panel.rows[i]
        if not row then
            row = CreateRowCard(content, 588, rowHeight - 4)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)

            row.icon = row:CreateTexture(nil, "OVERLAY")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.line1:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 5)
            row.line1:SetWidth(335)
            row.line1:SetJustifyH("LEFT")
            row.line1:SetWordWrap(false)

            row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.line2:SetPoint("TOPLEFT", row.line1, "BOTTOMLEFT", 0, -4)
            row.line2:SetWidth(345)
            row.line2:SetJustifyH("LEFT")
            row.line2:SetWordWrap(false)

            row.btnDel = CreateWowButton(row, L.MGR_ROW_DEL, 48, 22, function(self)
                if self.key then FW.DeleteEnemyRecord(self.key) end
            end)
            row.btnDel:SetPoint("RIGHT", row, "RIGHT", -8, 0)

            row.btnPlus = CreateWowButton(row, L.MGR_ROW_PLUS, 52, 22, function(self)
                local r = self.key and FW.db.enemies[self.key]
                if r then
                    FW.AdjustEnemyManualTier(self.key, math.min(#FW.DANGER_TIERS, FW.GetDangerTier(r).level + 1))
                end
            end)
            row.btnPlus:SetPoint("RIGHT", row.btnDel, "LEFT", -5, 0)

            row.btnNem = CreateWowButton(row, L.MGR_ROW_MARK_NEM, 68, 22, function(self)
                local r = self.key and FW.db.enemies[self.key]
                if r then FW.SetEnemyNemesis(self.key, not r.isNemesis) end
            end)
            row.btnNem:SetPoint("RIGHT", row.btnPlus, "LEFT", -5, 0)

            panel.rows[i] = row
        end

        local rec = item.rec
        row.btnDel.key = item.key
        row.btnPlus.key = item.key
        row.btnNem.key = item.key

        if rec.isNemesis then
            FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
            row.icon:SetVertexColor(1, 0.55, 1, 1)
            row:SetBackdropBorderColor(0.88, 0.25, 0.98, 0.95)
            row.btnNem:SetText(L.MGR_ROW_UNMARK_NEM)
            SizeButtonToText(row.btnNem, 72, 22)
        else
            local r, g, b = FW.GetDangerColor(rec)
            FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
            row.icon:SetVertexColor(1, 0.85, 0.70, 1)
            row:SetBackdropBorderColor(r, g, b, 0.85)
            row.btnNem:SetText(L.MGR_ROW_MARK_NEM)
            SizeButtonToText(row.btnNem, 72, 22)
        end

        row.line1:SetText(string.format("%s  %s",
            FW.ColorizeName(FW.GetDisplayName(item.key), rec.class),
            FW.GetDangerLabel(rec)))

        local sub = string.format(L.MGR_ROW_ENEMY_SUB,
            rec.attacks or 0, rec.kills or 0, rec.killedMe or 0,
            rec.lastZone or L.UNKNOWN, FW.FormatRelativeTime(rec.lastSeen))
        row.line2:SetText(sub)
        row:Show()
    end

    for i = #list + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    content:SetHeight(math.max(1, #list * rowHeight))
    panel.emptyText:SetShown(#list == 0)
end

-- ============================================================
-- Tab 2: Friendly Player Tags List
-- ============================================================

local function RefreshTagsTab()
    local panel = managerFrame.tagsPanel
    if not panel then return end
    panel.rows = panel.rows or {}

    local list = {}
    local query = FW.Trim(searchText):lower()
    for key, rec in pairs(FW.db.tags) do
        local tagInline = FW.FormatTagsInline(rec)
        local matchSearch = true
        if query ~= "" then
            local hay = (key .. " " .. tagInline .. " " .. (rec.note or "")):lower()
            matchSearch = hay:find(query, 1, true) ~= nil
        end
        if matchSearch then
            list[#list + 1] = { key = key, rec = rec }
        end
    end

    table.sort(list, function(a, b)
        return (a.rec.updatedAt or 0) > (b.rec.updatedAt or 0)
    end)

    panel.countText:SetText(string.format(L.MGR_TAGS_COUNT, #list))

    local content = panel.scrollChild
    local rowHeight = 52
    for i, item in ipairs(list) do
        local row = panel.rows[i]
        if not row then
            row = CreateRowCard(content, 588, rowHeight - 4)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)

            row.icon = row:CreateTexture(nil, "OVERLAY")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.line1:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 5)
            row.line1:SetWidth(420)
            row.line1:SetJustifyH("LEFT")
            row.line1:SetWordWrap(false)

            row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.line2:SetPoint("TOPLEFT", row.line1, "BOTTOMLEFT", 0, -4)
            row.line2:SetWidth(420)
            row.line2:SetJustifyH("LEFT")
            row.line2:SetWordWrap(false)

            row.btnDel = CreateWowButton(row, L.MGR_ROW_DEL, 52, 22, function(self)
                if self.key then FW.DeletePlayerTag(self.key) end
            end)
            row.btnDel:SetPoint("RIGHT", row, "RIGHT", -8, 0)

            row.btnEdit = CreateWowButton(row, L.MGR_ROW_EDIT, 56, 22, function(self)
                if self.key then
                    local r = FW.db.tags[self.key]
                    FW.OpenTagDialog(self.key, r and r.guid, r and r.class)
                end
            end)
            row.btnEdit:SetPoint("RIGHT", row.btnDel, "LEFT", -6, 0)

            panel.rows[i] = row
        end

        local rec = item.rec
        local cInfo = FW.GetTagColorInfo(rec.color)
        row.btnDel.key = item.key
        row.btnEdit.key = item.key

        FW.ApplyIconToTexture(row.icon, FW.GetTagIconDef())
        if cInfo.id == "GOLD" then
            row.icon:SetVertexColor(1, 1, 1, 1)
        else
            row.icon:SetVertexColor(cInfo.r, cInfo.g, cInfo.b, 1)
        end
        row:SetBackdropBorderColor(cInfo.r, cInfo.g, cInfo.b, 0.80)

        local tagStr = FW.FormatTagsInline(rec)
        if tagStr == "" then tagStr = L.CHAT_NOTED end
        row.line1:SetText(string.format("%s  |cff%s[%s]|r",
            FW.ColorizeName(FW.GetDisplayName(item.key), rec.class),
            cInfo.hex, tagStr))

        local noteStr = (rec.note and rec.note ~= "")
            and string.format(L.MGR_ROW_TAG_NOTE, rec.note)
            or string.format(L.MGR_ROW_TAG_UPDATED, FW.FormatRelativeTime(rec.updatedAt))
        row.line2:SetText(noteStr)
        row:Show()
    end

    for i = #list + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    content:SetHeight(math.max(1, #list * rowHeight))
    panel.emptyText:SetShown(#list == 0)
end

-- ============================================================
-- Tab 3: Settings
-- ============================================================

local function RefreshSettingsTab()
    local panel = managerFrame.settingsPanel
    if not panel then return end
    for _, cb in ipairs(panel.checkboxes) do
        cb:SetChecked(FW.settings[cb.key] == true)
    end
    if panel.iconButtons then
        local activeStyle = FW.settings.tagIconStyle or "PIN"
        for _, btn in ipairs(panel.iconButtons) do
            if btn.styleId == activeStyle then
                btn:SetBackdropColor(0.36, 0.25, 0.04, 0.96)
                btn:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
                btn.label:SetTextColor(1, 0.92, 0.35)
            else
                btn:SetBackdropColor(0.12, 0.12, 0.15, 0.88)
                btn:SetBackdropBorderColor(0.45, 0.40, 0.32, 0.85)
                btn.label:SetTextColor(0.86, 0.84, 0.80)
            end
        end
    end
    if panel.langButtons then
        local activeLang = FW.settings.language or "AUTO"
        for _, btn in ipairs(panel.langButtons) do
            if btn.langId == activeLang then
                btn:SetBackdropColor(0.36, 0.25, 0.04, 0.96)
                btn:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
                btn.label:SetTextColor(1, 0.92, 0.35)
            else
                btn:SetBackdropColor(0.12, 0.12, 0.15, 0.88)
                btn:SetBackdropBorderColor(0.45, 0.40, 0.32, 0.85)
                btn.label:SetTextColor(0.86, 0.84, 0.80)
            end
        end
    end
    if panel.alphaSlider then
        local pct = math.floor(((FW.settings.radarLockedAlpha or 0.55) * 100) + 0.5)
        panel.alphaSlider:SetValue(pct)
        panel.alphaValueText:SetText(pct .. "%")
    end
    if panel.presetInput then
        panel.presetInput:SetText(table.concat(FW.GetPresetTags(), ", "))
    end
end

-- ============================================================
-- Build Main Manager Window (Native Blizzard ButtonFrameTemplate)
-- ============================================================

local function SwitchTab(tabName)
    currentTab = tabName
    if not managerFrame then return end

    managerFrame.enemiesPanel:SetShown(tabName == "enemies")
    managerFrame.tagsPanel:SetShown(tabName == "tags")
    managerFrame.settingsPanel:SetShown(tabName == "settings")
    managerFrame.searchHolder:SetShown(tabName ~= "settings")

    local idx = TAB_INDEX[tabName] or 1
    if PanelTemplates_SetTab then
        PanelTemplates_SetTab(managerFrame, idx)
    end

    FW.RefreshManagerUI()
end

local function CreateScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 8)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(592)
    child:SetHeight(1)
    sf:SetScrollChild(child)

    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", parent, "CENTER", -10, 0)
    return sf, child, empty
end

local function CreateManagerUI()
    local f = CreateFrame("Frame", "ForeverWatchManagerFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(660, 608)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "ForeverWatchManagerFrame")

    if f.SetTitle then
        f:SetTitle("|cffFFD100Forever|r|cffFF4444Watch|r  " .. L.ADDON_SUBTITLE)
    end
    if f.SetPortraitToAsset then
        f:SetPortraitToAsset("Interface\\Icons\\Ability_Tracking")
    end

    local inset = f.Inset
    if inset then
        local rockBg = inset:CreateTexture(nil, "BACKGROUND")
        rockBg:SetPoint("TOPLEFT", inset, "TOPLEFT", 3, -3)
        rockBg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -3, 3)
        rockBg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
        rockBg:SetHorizTile(true)
        rockBg:SetVertTile(true)
        rockBg:SetVertexColor(0.55, 0.55, 0.60, 0.96)
    end

    -- Top toolbar search box
    local searchHolder, searchBox = CreateBeveledSearchBox(f, 200, 24)
    searchHolder:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -30)
    f.searchHolder = searchHolder

    local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchHint:SetText(L.MGR_SEARCH_HINT)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText() or ""
        searchHint:SetShown(searchText == "")
        FW.RefreshManagerUI()
    end)

    -- ===== Tab 1: Enemies =====
    local enemiesPanel = CreateFrame("Frame", nil, inset)
    enemiesPanel:SetAllPoints()
    f.enemiesPanel = enemiesPanel

    local nemFilterBtn = CreateWowButton(enemiesPanel, L.MGR_FILTER_NEM_OFF, 108, 22, function(self)
        enemyFilterNemesisOnly = not enemyFilterNemesisOnly
        self:SetText(enemyFilterNemesisOnly and L.MGR_FILTER_NEM_ON or L.MGR_FILTER_NEM_OFF)
        SizeButtonToText(self, 108, 26)
        RefreshEnemiesTab()
    end)
    nemFilterBtn:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -4, 6)

    local addEnemyBtn = CreateWowButton(enemiesPanel, L.MGR_BTN_MARK_TARGET_NEM, 132, 22, function()
        local info = FW.GetUnitIdentity("target")
        if info and FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, "target")) and FW.SafeBool(FW.SafeUnitCall(UnitIsEnemy, "player", "target")) then
            FW.RecordEnemyAction(info, "manual_nemesis")
        else
            FW.Print(L.MGR_NEED_ENEMY_TARGET)
        end
    end)
    addEnemyBtn:SetPoint("RIGHT", nemFilterBtn, "LEFT", -8, 0)

    enemiesPanel.countText = enemiesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enemiesPanel.countText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 8)

    local _, eChild, eEmpty = CreateScrollArea(enemiesPanel)
    enemiesPanel.scrollChild = eChild
    enemiesPanel.emptyText = eEmpty
    eEmpty:SetText(L.MGR_ENEMIES_EMPTY)

    -- ===== Tab 2: Tags =====
    local tagsPanel = CreateFrame("Frame", nil, inset)
    tagsPanel:SetAllPoints()
    f.tagsPanel = tagsPanel

    local addTagBtn = CreateWowButton(tagsPanel, L.MGR_BTN_TAG_TARGET, 142, 22, function()
        local info = FW.GetUnitIdentity("target")
        if info
            and FW.SafeBool(FW.SafeUnitCall(UnitIsPlayer, "target"))
            and not FW.SafeBool(FW.SafeUnitCall(UnitIsUnit, "target", "player"))
        then
            FW.OpenTagDialog(info.key, info.guid, info.class)
        else
            FW.Print(L.MGR_NEED_FRIEND_TARGET)
        end
    end)
    addTagBtn:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -4, 6)

    tagsPanel.countText = tagsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagsPanel.countText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 8)

    local _, tChild, tEmpty = CreateScrollArea(tagsPanel)
    tagsPanel.scrollChild = tChild
    tagsPanel.emptyText = tEmpty
    tEmpty:SetText(L.MGR_TAGS_EMPTY)

    -- ===== Tab 3: Settings =====
    local settingsPanel = CreateFrame("Frame", nil, inset)
    settingsPanel:SetAllPoints()
    f.settingsPanel = settingsPanel
    settingsPanel.checkboxes = {}

    local opts = {
        { key = "enableMonitor",        text = L.OPT_MONITOR },
        { key = "enableBanner",         text = L.OPT_BANNER },
        { key = "enableSound",          text = L.OPT_SOUND },
        { key = "enableRadar",          text = L.OPT_RADAR },
        { key = "radarLocked",          text = L.OPT_RADAR_LOCK },
        { key = "radarShowNormalEnemy", text = L.OPT_RADAR_NORMAL },
        { key = "enableTooltipTags",    text = L.OPT_TOOLTIP },
        { key = "enableChatTags",       text = L.OPT_CHAT },
        { key = "enableNameplateIcon",  text = L.OPT_NAMEPLATE },
    }

    for i, opt in ipairs(opts) do
        local cb = CreateFrame("CheckButton", nil, settingsPanel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 16, -8 - (i - 1) * 24)
        cb:SetSize(22, 22)
        cb.key = opt.key
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        lbl:SetText(opt.text)
        cb:SetScript("OnClick", function(self)
            FW.settings[self.key] = self:GetChecked() and true or false
            FW.RefreshAllUI()
        end)
        settingsPanel.checkboxes[i] = cb
    end

    local div1 = settingsPanel:CreateTexture(nil, "ARTWORK")
    div1:SetHeight(2)
    div1:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14, -228)
    div1:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", -14, -228)
    div1:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    div1:SetVertexColor(0.85, 0.72, 0.35, 0.7)

    -- Tag Icon Style Picker
    local iconLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -238)
    iconLbl:SetText(L.SET_ICON_STYLE)

    settingsPanel.iconButtons = {}
    local ix = 18
    for i, style in ipairs(FW.TAG_ICON_STYLES) do
        local btn = CreateFrame("Button", nil, settingsPanel, "BackdropTemplate")
        btn:SetHeight(26)
        btn:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local ico = btn:CreateTexture(nil, "OVERLAY")
        ico:SetSize(15, 15)
        ico:SetPoint("LEFT", btn, "LEFT", 10, 0)
        FW.ApplyIconToTexture(ico, style)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        lbl:SetText(style.name)
        btn.label = lbl
        btn.styleId = style.id

        local w = math.max(88, math.ceil(lbl:GetStringWidth() + 40))
        btn:SetWidth(w)
        btn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", ix, -256)

        btn:SetScript("OnClick", function(self)
            FW.settings.tagIconStyle = self.styleId
            RefreshSettingsTab()
            FW.RefreshAllUI()
        end)
        settingsPanel.iconButtons[i] = btn
        ix = ix + w + 8
    end

    -- Locked Radar Opacity Slider (20% - 100%)
    local alphaLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alphaLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -292)
    alphaLbl:SetText(L.SET_LOCKED_ALPHA)

    local alphaSlider = CreateFrame("Slider", "ForeverWatchLockedAlphaSlider", settingsPanel, "UISliderTemplate")
    alphaSlider:SetSize(220, 18)
    alphaSlider:SetPoint("LEFT", alphaLbl, "RIGHT", 12, 0)
    alphaSlider:SetMinMaxValues(20, 100)
    alphaSlider:SetValueStep(5)
    alphaSlider:SetObeyStepOnDrag(true)

    local alphaValueText = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    alphaValueText:SetPoint("LEFT", alphaSlider, "RIGHT", 10, 0)
    alphaValueText:SetText("55%")

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        local pct = math.floor(value + 0.5)
        FW.settings.radarLockedAlpha = pct / 100
        alphaValueText:SetText(pct .. "%")
        if FW.ApplyRadarLockState then
            FW.ApplyRadarLockState()
        end
    end)
    settingsPanel.alphaSlider = alphaSlider
    settingsPanel.alphaValueText = alphaValueText

    -- Language Switcher (Auto / zhCN / zhTW / enUS) + Reload button
    local langLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    langLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -326)
    langLbl:SetText(L.SET_LANGUAGE)

    settingsPanel.langButtons = {}
    local langDefs = {
        { id = "AUTO", text = L.LANG_AUTO },
        { id = "zhCN", text = L.LANG_ZHCN },
        { id = "zhTW", text = L.LANG_ZHTW },
        { id = "enUS", text = L.LANG_ENUS },
    }
    local lx = 18
    for i, ldef in ipairs(langDefs) do
        local btn = CreateFrame("Button", nil, settingsPanel, "BackdropTemplate")
        btn:SetHeight(26)
        btn:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER", 0, 0)
        lbl:SetText(ldef.text)
        btn.label = lbl
        btn.langId = ldef.id

        local w = math.max(82, math.ceil(lbl:GetStringWidth() + 24))
        btn:SetWidth(w)
        btn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", lx, -344)
        btn:SetScript("OnClick", function(self)
            FW.SetLanguage(self.langId)
            RefreshSettingsTab()
        end)
        settingsPanel.langButtons[i] = btn
        lx = lx + w + 8
    end

    local reloadBtn = CreateWowButton(settingsPanel, L.SET_BTN_RELOAD, 84, 24, function()
        if ReloadUI then ReloadUI() end
    end)
    reloadBtn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", lx + 4, -345)

    -- Preset tags customization
    local pLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -384)
    pLbl:SetText(L.SET_PRESET_LABEL)

    local pBg, pInput = CreateBeveledSearchBox(settingsPanel, 492, 26)
    pBg:SetPoint("TOPLEFT", pLbl, "BOTTOMLEFT", 0, -6)
    settingsPanel.presetInput = pInput

    local pSave = CreateWowButton(settingsPanel, L.SET_BTN_SAVE_PRESET, 90, 26, function()
        local parsed = FW.ParseTagString(pInput:GetText() or "")
        if #parsed > 0 and not FW.IsDefaultPresetList(parsed) then
            FW.settings.presetTags = parsed
            FW.Print(string.format(L.SET_PRESET_SAVED, #parsed))
        else
            FW.settings.presetTags = nil
            pInput:SetText(table.concat(FW.GetPresetTags(), ", "))
            FW.Print(L.SET_PRESET_RESET)
        end
    end)
    pSave:SetPoint("LEFT", pBg, "RIGHT", 8, 0)

    -- Bottom action buttons inside Settings
    local testBtn = CreateWowButton(settingsPanel, L.SET_BTN_TEST_SINGLE, 118, 24, function()
        FW.ShowAlertBanner(L.TEST_SINGLE_NAME, "ROGUE", {
            key = "TestEnemySingle-Test",
            isNemesis = true,
            kills = 5,
            killedMe = 1,
            attacks = 6,
        }, L.TEST_SINGLE_REASON, 5)
    end)
    testBtn:SetPoint("BOTTOMLEFT", settingsPanel, "BOTTOMLEFT", 18, 16)

    local testMultiBtn = CreateWowButton(settingsPanel, L.SET_BTN_TEST_MULTI, 142, 24, function()
        if FW.TriggerMultiAlertTest then
            FW.TriggerMultiAlertTest()
        end
    end)
    testMultiBtn:SetPoint("LEFT", testBtn, "RIGHT", 10, 0)

    local resetPosBtn = CreateWowButton(settingsPanel, L.SET_BTN_RESET_POS, 142, 24, function()
        FW.settings.radarPoint = nil
        if ForeverWatchRadarFrame then
            ForeverWatchRadarFrame:ClearAllPoints()
            ForeverWatchRadarFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -220)
        end
        FW.Print(L.SET_POS_RESET_MSG)
    end)
    resetPosBtn:SetPoint("LEFT", testMultiBtn, "RIGHT", 10, 0)

    -- Native Blizzard Bottom Tabs
    local tabDefs = {
        { id = "enemies",  text = L.MGR_TAB_ENEMIES },
        { id = "tags",     text = L.MGR_TAB_TAGS },
        { id = "settings", text = L.MGR_TAB_SETTINGS },
    }
    for i, def in ipairs(tabDefs) do
        local tab = CreateFrame("Button", "ForeverWatchManagerFrameTab" .. i, f, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(def.text)
        tab:SetScript("OnClick", function() SwitchTab(def.id) end)
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 14, 2)
        else
            tab:SetPoint("LEFT", _G["ForeverWatchManagerFrameTab" .. (i - 1)], "RIGHT", 4, 0)
        end
        if PanelTemplates_TabResize then
            PanelTemplates_TabResize(tab, 12)
        end
    end
    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(f, #tabDefs)
        PanelTemplates_SetTab(f, 1)
    end

    f:Hide()
    return f
end

function FW.RefreshManagerUI()
    if not managerFrame or not managerFrame:IsShown() then return end
    if currentTab == "enemies" then
        RefreshEnemiesTab()
    elseif currentTab == "tags" then
        RefreshTagsTab()
    elseif currentTab == "settings" then
        RefreshSettingsTab()
    end
end

function FW.ShowManagerUI(tabName)
    if not managerFrame then
        managerFrame = CreateManagerUI()
    end
    managerFrame:Show()
    SwitchTab(tabName or currentTab or "enemies")
end

function FW.ToggleManagerUI()
    if not managerFrame then
        managerFrame = CreateManagerUI()
    end
    if managerFrame:IsShown() then
        managerFrame:Hide()
    else
        managerFrame:Show()
        SwitchTab(currentTab or "enemies")
    end
end

function FW.InitManagerUI()
    -- Lazily created on first open
end
