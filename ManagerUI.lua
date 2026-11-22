local _, FW = ...
local L = FW.L

local managerFrame
local detailDialog
local tagDetailDialog
local currentTab = "enemies"
local enemyFilterNemesisOnly = false
local statsViewMode = "enemies"   -- "enemies" | "history"
local statsEnemySort = "total"    -- "total" | "kills" | "deaths" | "kd" | "recent"
local statsHistoryFilter = "all"  -- "all" | "kill" | "death"
local searchText = ""

local TAB_INDEX = {
    enemies = 1,
    tags = 2,
    stats = 3,
    settings = 4,
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

local function FormatLevelBadge(level)
    local txt = FW.FormatLevelText(level)
    if level == -1 then
        return "|cffFF5544" .. txt .. "|r"
    elseif level and level > 0 then
        return "|cffFFD100" .. txt .. "|r"
    end
    return "|cff888888" .. txt .. "|r"
end

local function CreateClickableRowCard(parent, width, height)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width, height)
    row:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 11,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropColor(0.09, 0.09, 0.12, 0.90)
    row:SetBackdropBorderColor(0.42, 0.38, 0.28, 0.82)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -4)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 4)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetVertexColor(0.75, 0.62, 0.28, 0.95)
    row.accent = accent

    local hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hl:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0)
    row.hoverGlow = hl

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
            row = CreateClickableRowCard(content, 606, rowHeight - 4)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)

            row.icon = row:CreateTexture(nil, "OVERLAY")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", row, "LEFT", 11, 0)

            row.btnDel = CreateWowButton(row, L.MGR_ROW_DEL, 48, 22, function(self)
                if self.key then FW.DeleteEnemyRecord(self.key) end
            end)
            row.btnDel:SetPoint("RIGHT", row, "RIGHT", -8, 0)

            row.btnPlus = CreateWowButton(row, L.MGR_ROW_PLUS, 50, 22, function(self)
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

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.line1:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 5)
            row.line1:SetPoint("RIGHT", row.btnNem, "LEFT", -10, 0)
            row.line1:SetJustifyH("LEFT")
            row.line1:SetWordWrap(false)

            row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.line2:SetPoint("TOPLEFT", row.line1, "BOTTOMLEFT", 0, -4)
            row.line2:SetPoint("RIGHT", row.btnNem, "LEFT", -10, 0)
            row.line2:SetJustifyH("LEFT")
            row.line2:SetWordWrap(false)

            row:SetScript("OnEnter", function(self)
                self.hoverGlow:SetAlpha(0.32)
                local it = self.itemData
                if not it then return end
                local r = it.rec
                local pvpR = FW.FindPvPEnemyStats(it.key, r.guid, r.realm)
                local mk = math.max(r.myKills or 0, pvpR and pvpR.kills or 0)
                local km = math.max(r.killedMe or 0, pvpR and pvpR.deaths or 0)
                local lvl = (r.level and r.level ~= 0) and r.level or (pvpR and pvpR.level) or 0
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(FW.ColorizeName(FW.GetDisplayName(it.key), r.class))
                GameTooltip:AddLine(string.format(L.STATS_ROW_TT_LVL_CLS,
                    FW.FormatLevelText(lvl), FW.ColorizeName(FW.GetLocalizedClassName(r.class), r.class)), 1, 1, 1)
                GameTooltip:AddLine(string.format(L.RADAR_TT_STATUS, FW.GetDangerLabel(r)), 1, 1, 1)
                GameTooltip:AddLine(string.format(L.RADAR_TT_STATS, r.attacks or 0, r.kills or 0), 0.92, 0.92, 0.92)
                if mk > 0 or km > 0 then
                    local tot = mk + km
                    local wr = tot > 0 and math.floor((mk / tot) * 100 + 0.5) or 0
                    GameTooltip:AddLine(string.format(L.STATS_ROW_TT_SCORE, mk, km, FW.FormatKDRatio(mk, km, 2), wr), 1, 1, 1)
                end
                GameTooltip:AddLine(string.format(L.STATS_ROW_TT_ZONE, r.lastZone or L.UNKNOWN, FW.FormatRelativeTime(r.lastSeen)), 0.85, 0.85, 0.85)
                if r.lastEvent and r.lastEvent ~= "" then
                    GameTooltip:AddLine(string.format(L.RADAR_TT_RECENT, r.lastEvent), 1, 0.82, 0)
                end
                if r.note and r.note ~= "" then
                    GameTooltip:AddLine(string.format(L.RADAR_TT_NOTE, r.note), 0.88, 0.88, 0.92, true)
                end
                GameTooltip:AddLine(L.MGR_ENEMY_TT_CLICK, 0.55, 0.85, 1.0)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self.hoverGlow:SetAlpha(0)
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(self, button)
                local it = self.itemData
                if not it then return end
                if FW.OpenPvPDetailDialog then
                    FW.OpenPvPDetailDialog(it.key)
                end
            end)

            panel.rows[i] = row
        end

        local rec = item.rec
        row.itemData = item
        row.btnDel.key = item.key
        row.btnPlus.key = item.key
        row.btnNem.key = item.key

        if rec.isNemesis then
            FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
            row.icon:SetVertexColor(1, 0.55, 1, 1)
            row.accent:SetVertexColor(0.88, 0.25, 0.98, 1)
            row:SetBackdropBorderColor(0.88, 0.25, 0.98, 0.92)
            row.btnNem:SetText(L.MGR_ROW_UNMARK_NEM)
            SizeButtonToText(row.btnNem, 72, 22)
        else
            local r, g, b = FW.GetDangerColor(rec)
            FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
            row.icon:SetVertexColor(1, 0.85, 0.70, 1)
            row.accent:SetVertexColor(r, g, b, 1)
            row:SetBackdropBorderColor(r, g, b, 0.85)
            row.btnNem:SetText(L.MGR_ROW_MARK_NEM)
            SizeButtonToText(row.btnNem, 72, 22)
        end

        local pvpRec = FW.FindPvPEnemyStats(item.key, rec.guid, rec.realm)
        local lvl = (rec.level and rec.level ~= 0) and rec.level or (pvpRec and pvpRec.level) or 0
        local lvlStr = (lvl ~= 0) and (" |cff666666[|r" .. FormatLevelBadge(lvl) .. "|cff666666]|r") or ""
        row.line1:SetText(string.format("%s%s  %s",
            FW.ColorizeName(FW.GetDisplayName(item.key), rec.class),
            lvlStr,
            FW.GetDangerLabel(rec)))

        local myKills = math.max(rec.myKills or 0, pvpRec and pvpRec.kills or 0)
        local sub = string.format(L.MGR_ROW_ENEMY_SUB,
            rec.attacks or 0, rec.kills or 0, myKills, rec.killedMe or 0,
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
            row = CreateClickableRowCard(content, 606, rowHeight - 4)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)

            row.icon = row:CreateTexture(nil, "OVERLAY")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", row, "LEFT", 11, 0)

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

            row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.line1:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 5)
            row.line1:SetPoint("RIGHT", row.btnEdit, "LEFT", -10, 0)
            row.line1:SetJustifyH("LEFT")
            row.line1:SetWordWrap(false)

            row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.line2:SetPoint("TOPLEFT", row.line1, "BOTTOMLEFT", 0, -4)
            row.line2:SetPoint("RIGHT", row.btnEdit, "LEFT", -10, 0)
            row.line2:SetJustifyH("LEFT")
            row.line2:SetWordWrap(false)

            row:SetScript("OnEnter", function(self)
                self.hoverGlow:SetAlpha(0.32)
                local it = self.itemData
                if not it then return end
                local r = it.rec
                local ci = FW.GetTagColorInfo(r.color)
                local tStr = FW.FormatTagsInline(r)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(FW.ColorizeName(FW.GetDisplayName(it.key), r.class))
                if tStr ~= "" then
                    GameTooltip:AddLine(string.format(L.TT_TAGS_FMT, FW.GetTagIconMarkup(14), ci.hex, "[" .. tStr .. "]"), 1, 1, 1, true)
                end
                if r.note and r.note ~= "" then
                    GameTooltip:AddLine(string.format(L.MGR_ROW_TAG_NOTE, r.note), 0.92, 0.92, 0.95, true)
                end
                GameTooltip:AddLine(string.format(L.MGR_ROW_TAG_UPDATED, FW.FormatRelativeTime(r.updatedAt)), 0.72, 0.72, 0.72)
                GameTooltip:AddLine(L.MGR_TAG_TT_CLICK, 0.55, 0.85, 1.0)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                self.hoverGlow:SetAlpha(0)
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(self)
                local it = self.itemData
                if it and FW.OpenTagDetailDialog then
                    FW.OpenTagDetailDialog(it.key)
                end
            end)

            panel.rows[i] = row
        end

        local rec = item.rec
        local cInfo = FW.GetTagColorInfo(rec.color)
        row.itemData = item
        row.btnDel.key = item.key
        row.btnEdit.key = item.key

        FW.ApplyIconToTexture(row.icon, FW.GetTagIconDef())
        if cInfo.id == "GOLD" then
            row.icon:SetVertexColor(1, 1, 1, 1)
        else
            row.icon:SetVertexColor(cInfo.r, cInfo.g, cInfo.b, 1)
        end
        row.accent:SetVertexColor(cInfo.r, cInfo.g, cInfo.b, 1)
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
-- Tab 3: PvP Kill & Death Statistics + Opponent Detail Dialog
-- ============================================================

local function StyleTogglePill(btn, active)
    if active then
        btn:SetBackdropColor(0.36, 0.25, 0.04, 0.96)
        btn:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        btn.label:SetTextColor(1, 0.92, 0.35)
    else
        btn:SetBackdropColor(0.12, 0.12, 0.15, 0.88)
        btn:SetBackdropBorderColor(0.45, 0.40, 0.32, 0.85)
        btn.label:SetTextColor(0.86, 0.84, 0.80)
    end
end

local function CreateRatioBar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(width, height)
    bar:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bar:SetBackdropColor(0.06, 0.06, 0.09, 0.94)
    bar:SetBackdropBorderColor(0.55, 0.46, 0.26, 0.88)

    local innerW = math.max(1, width - 6)
    bar.innerWidth = innerW

    local deathFill = bar:CreateTexture(nil, "ARTWORK")
    deathFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, -3)
    deathFill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -3, 3)
    deathFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    deathFill:SetVertexColor(0.72, 0.16, 0.20, 0.82)
    deathFill:Hide()
    bar.deathFill = deathFill

    local killFill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    killFill:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, -3)
    killFill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 3, 3)
    killFill:SetWidth(1)
    killFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    killFill:SetVertexColor(0.18, 0.68, 0.30, 0.88)
    killFill:Hide()
    bar.killFill = killFill

    local gloss = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    gloss:SetHeight(math.max(4, math.floor(height * 0.45)))
    gloss:SetPoint("TOPLEFT", bar, "TOPLEFT", 3, -3)
    gloss:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -3, -3)
    gloss:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    gloss:SetBlendMode("ADD")
    gloss:SetAlpha(0.18)

    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER", bar, "CENTER", 0, 0)
    txt:SetWordWrap(false)
    bar.text = txt

    function bar:SetRatio(kills, deaths, labelText)
        kills = kills or 0
        deaths = deaths or 0
        local total = kills + deaths
        if total <= 0 then
            self.deathFill:Hide()
            self.killFill:Hide()
        else
            self.deathFill:SetShown(deaths > 0)
            if kills > 0 then
                local w = math.max(2, math.floor(self.innerWidth * (kills / total) + 0.5))
                if w > self.innerWidth then w = self.innerWidth end
                self.killFill:SetWidth(w)
                self.killFill:Show()
            else
                self.killFill:Hide()
            end
        end
        self.text:SetText(labelText or "")
    end

    return bar
end

local function CreateStatKpiCard(parent, width, height, titleText, r, g, b, iconDef)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width, height)
    card:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.08, 0.08, 0.11, 0.92)
    card:SetBackdropBorderColor(r, g, b, 0.88)

    local topGlow = card:CreateTexture(nil, "ARTWORK")
    topGlow:SetHeight(18)
    topGlow:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -4)
    topGlow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -4)
    topGlow:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    topGlow:SetBlendMode("ADD")
    topGlow:SetVertexColor(r, g, b, 0.25)

    local titleMarkup = iconDef and (FW.GetIconMarkup(iconDef, 13) .. " ") or ""
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", card, "TOP", 0, -8)
    title:SetText(titleMarkup .. titleText)
    card.title = title

    local val = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    val:SetPoint("CENTER", card, "CENTER", 0, -1)
    val:SetText("0")
    card.value = val

    local sub = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("BOTTOM", card, "BOTTOM", 0, 7)
    sub:SetText("")
    card.sub = sub

    return card
end

local function CreateMiniStatCard(parent, width, height, titleText, r, g, b)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width, height)
    card:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    card:SetBackdropColor(0.08, 0.08, 0.11, 0.92)
    card:SetBackdropBorderColor(r, g, b, 0.88)

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    title:SetPoint("TOP", card, "TOP", 0, -7)
    title:SetText(titleText)
    card.title = title

    local val = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    val:SetPoint("CENTER", card, "CENTER", 0, -7)
    val:SetText("0")
    card.value = val

    return card
end

local function RefreshPvPDetailDialog()
    if not detailDialog or not detailDialog:IsShown() or not detailDialog.targetKey then return end

    local key = detailDialog.targetKey
    local stats = (FW.db and FW.db.pvpStats) or {}
    local pRec = type(stats.byEnemy) == "table" and stats.byEnemy[key] or nil
    local enemyRec = FW.FindEnemyRecord(key, pRec and pRec.guid, pRec and pRec.realm)
    local tagRec = FW.FindTagRecord(key, pRec and pRec.guid, pRec and pRec.realm)

    -- Gather per-opponent history entries
    local oppHist = {}
    if type(stats.history) == "table" then
        for _, entry in ipairs(stats.history) do
            if entry.key == key then
                oppHist[#oppHist + 1] = entry
            end
        end
    end

    -- Resolve identity metadata from best available source
    local classFile = (pRec and pRec.class) or (enemyRec and enemyRec.class) or (tagRec and tagRec.class)
        or (oppHist[1] and oppHist[1].class)
    local level = (pRec and pRec.level and pRec.level ~= 0) and pRec.level
        or (enemyRec and enemyRec.level and enemyRec.level ~= 0 and enemyRec.level)
        or (oppHist[1] and oppHist[1].level) or 0
    local _, realm = FW.SplitNameRealm(key)
    realm = (pRec and pRec.realm and pRec.realm ~= "") and pRec.realm or realm or FW.GetMyRealm()
    local guid = (pRec and pRec.guid) or (enemyRec and enemyRec.guid) or (tagRec and tagRec.guid)

    detailDialog.targetClass = classFile
    detailDialog.targetGuid = guid
    detailDialog.targetRealm = realm
    detailDialog.targetLevel = level

    local k = pRec and (pRec.kills or 0) or 0
    local d = pRec and (pRec.deaths or 0) or 0
    local total = k + d
    local winRate = total > 0 and math.floor((k / total) * 100 + 0.5) or 0
    local diff = k - d
    local isNem = enemyRec and enemyRec.isNemesis

    -- Header banner
    if isNem then
        FW.ApplyIconToTexture(detailDialog.headIcon, FW.ICONS.NEMESIS)
        detailDialog.headIcon:SetVertexColor(1.0, 0.55, 1.0, 1)
        detailDialog.headerBox:SetBackdropBorderColor(0.88, 0.25, 0.98, 0.95)
    elseif k > d then
        FW.ApplyIconToTexture(detailDialog.headIcon, FW.ICONS.DANGER_SWORD)
        detailDialog.headIcon:SetVertexColor(0.35, 1.0, 0.45, 1)
        detailDialog.headerBox:SetBackdropBorderColor(0.30, 0.85, 0.42, 0.90)
    elseif d > k then
        FW.ApplyIconToTexture(detailDialog.headIcon, FW.ICONS.NEMESIS)
        detailDialog.headIcon:SetVertexColor(1.0, 0.35, 0.35, 1)
        detailDialog.headerBox:SetBackdropBorderColor(0.90, 0.28, 0.28, 0.90)
    else
        FW.ApplyIconToTexture(detailDialog.headIcon, FW.ICONS.DANGER_SWORD)
        detailDialog.headIcon:SetVertexColor(1.0, 0.82, 0.25, 1)
        detailDialog.headerBox:SetBackdropBorderColor(0.78, 0.64, 0.28, 0.90)
    end

    local dangerBadge = enemyRec and ("  " .. FW.GetDangerLabel(enemyRec)) or ""
    detailDialog.headName:SetText(string.format("%s  [%s]%s",
        FW.ColorizeName(FW.GetDisplayName(key), classFile),
        FormatLevelBadge(level),
        dangerBadge))

    local classColored = FW.ColorizeName(FW.GetLocalizedClassName(classFile), classFile)
    detailDialog.headSub:SetText(string.format(L.DETAIL_IDENTITY_SUB,
        FormatLevelBadge(level), classColored, FW.ColorizeName(FW.GetFullName(key), classFile)))

    -- 4 Mini H2H KPI cards
    detailDialog.miniKills.value:SetText(tostring(k))
    detailDialog.miniKills.value:SetTextColor(0.30, 1.00, 0.42)

    detailDialog.miniDeaths.value:SetText(tostring(d))
    detailDialog.miniDeaths.value:SetTextColor(1.00, 0.35, 0.35)

    detailDialog.miniKD.value:SetText(FW.FormatKDRatio(k, d, 2))
    if k > 0 and k >= d then
        detailDialog.miniKD.value:SetTextColor(0.30, 1.00, 0.42)
    elseif d > k then
        detailDialog.miniKD.value:SetTextColor(1.00, 0.40, 0.35)
    else
        detailDialog.miniKD.value:SetTextColor(1.00, 0.82, 0.00)
    end

    if diff > 0 then
        detailDialog.miniNet.value:SetText("+" .. tostring(diff))
        detailDialog.miniNet.value:SetTextColor(0.30, 1.00, 0.42)
    elseif diff < 0 then
        detailDialog.miniNet.value:SetText(tostring(diff))
        detailDialog.miniNet.value:SetTextColor(1.00, 0.35, 0.35)
    else
        detailDialog.miniNet.value:SetText("0")
        detailDialog.miniNet.value:SetTextColor(0.75, 0.75, 0.75)
    end

    -- Ratio bar
    if total > 0 then
        detailDialog.ratioBar:SetRatio(k, d, string.format(L.DETAIL_RATIO_FMT, winRate, k, d))
    else
        detailDialog.ratioBar:SetRatio(0, 0, L.STATS_RATIO_BAR_EMPTY)
    end

    -- Meta info box
    local lastZone = (pRec and pRec.lastZone) or (enemyRec and enemyRec.lastZone) or (oppHist[1] and oppHist[1].zone) or L.UNKNOWN
    local lastTs = (pRec and pRec.lastSeen) or (enemyRec and enemyRec.lastSeen) or (oppHist[1] and oppHist[1].time)
    local clockStr = (lastTs and date) and date("%m-%d %H:%M", lastTs) or ""
    local relStr = FW.FormatRelativeTime(lastTs)
    local timeFull = clockStr ~= "" and (relStr .. " · " .. clockStr) or relStr
    detailDialog.metaLine1:SetText(string.format(L.DETAIL_META_ZONE, lastZone, timeFull))

    if enemyRec then
        detailDialog.metaLine2:SetText(string.format(L.DETAIL_META_THREAT,
            FW.GetDangerLabel(enemyRec), enemyRec.attacks or 0, enemyRec.kills or 0))
    else
        detailDialog.metaLine2:SetText("")
    end

    if enemyRec and enemyRec.lastEvent and enemyRec.lastEvent ~= "" then
        detailDialog.metaLine3:SetText(string.format(L.DETAIL_META_RECENT, enemyRec.lastEvent))
    elseif tagRec then
        local cInfo = FW.GetTagColorInfo(tagRec.color)
        local tStr = FW.FormatTagsInline(tagRec)
        detailDialog.metaLine3:SetText(string.format(L.DETAIL_META_TAG, cInfo.hex, tStr ~= "" and tStr or L.CHAT_NOTED))
    else
        detailDialog.metaLine3:SetText("")
    end

    local line4Parts = {}
    if enemyRec and enemyRec.lastEvent and enemyRec.lastEvent ~= "" and tagRec then
        local cInfo = FW.GetTagColorInfo(tagRec.color)
        local tStr = FW.FormatTagsInline(tagRec)
        line4Parts[#line4Parts + 1] = string.format(L.DETAIL_META_TAG, cInfo.hex, tStr ~= "" and tStr or L.CHAT_NOTED)
    end
    local combinedNote = (enemyRec and enemyRec.note and enemyRec.note ~= "") and enemyRec.note
        or (tagRec and tagRec.note and tagRec.note ~= "" and tagRec.note) or nil
    if combinedNote then
        line4Parts[#line4Parts + 1] = string.format(L.MGR_ROW_TAG_NOTE, combinedNote)
    end
    detailDialog.metaLine4:SetText(table.concat(line4Parts, "  ·  "))

    -- Footer button labels
    detailDialog.btnNem:SetText(isNem and L.MGR_ROW_UNMARK_NEM or L.MGR_ROW_MARK_NEM)
    SizeButtonToText(detailDialog.btnNem, 92, 22)
    detailDialog.btnDel:SetEnabled(pRec ~= nil)

    -- Per-opponent encounter timeline
    detailDialog.histHeader:SetText(string.format(L.DETAIL_HISTORY_HDR, #oppHist))
    detailDialog.histRows = detailDialog.histRows or {}
    local content = detailDialog.scrollChild
    local rowHeight = 32

    for i, entry in ipairs(oppHist) do
        local row = detailDialog.histRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(398, rowHeight - 3)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)
            row:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            row:SetBackdropColor(0.08, 0.08, 0.11, 0.88)

            row.accent = row:CreateTexture(nil, "ARTWORK")
            row.accent:SetWidth(3)
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 3)
            row.accent:SetTexture("Interface\\Buttons\\WHITE8X8")

            row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.left:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.left:SetWidth(195)
            row.left:SetJustifyH("LEFT")
            row.left:SetWordWrap(false)

            row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.right:SetWidth(185)
            row.right:SetJustifyH("RIGHT")
            row.right:SetWordWrap(false)

            detailDialog.histRows[i] = row
        end

        local isKill = entry.type == "kill"
        local badge
        if isKill then
            if entry.wasNemesis then
                row.accent:SetVertexColor(0.88, 0.25, 0.98, 1)
                row:SetBackdropBorderColor(0.75, 0.24, 0.85, 0.82)
                badge = L.STATS_BADGE_REVENGE
            else
                row.accent:SetVertexColor(0.30, 0.92, 0.42, 1)
                row:SetBackdropBorderColor(0.28, 0.72, 0.36, 0.78)
                badge = L.STATS_BADGE_KILL
            end
        else
            row.accent:SetVertexColor(0.95, 0.30, 0.30, 1)
            row:SetBackdropBorderColor(0.85, 0.28, 0.28, 0.82)
            badge = L.STATS_BADGE_DEATH
        end

        local oppLvl = (entry.level and entry.level ~= 0) and entry.level or level
        local lvlInfo
        if entry.myLevel and entry.myLevel > 0 then
            lvlInfo = string.format(L.DETAIL_HIST_LVL_VS, FormatLevelBadge(oppLvl), "|cffCCCCCCLv." .. entry.myLevel .. "|r")
        else
            lvlInfo = string.format(L.DETAIL_HIST_LVL_ONLY, FormatLevelBadge(oppLvl))
        end
        row.left:SetText(badge .. "  " .. lvlInfo)

        local cStr = (entry.time and date) and date("%m-%d %H:%M", entry.time) or ""
        local rStr = FW.FormatRelativeTime(entry.time)
        local tStr = cStr ~= "" and cStr or rStr
        row.right:SetText(string.format("%s · %s", entry.zone or L.UNKNOWN, tStr))
        row:Show()
    end

    for i = #oppHist + 1, #detailDialog.histRows do
        detailDialog.histRows[i]:Hide()
    end

    content:SetHeight(math.max(1, #oppHist * rowHeight))
    detailDialog.histEmpty:SetShown(#oppHist == 0)
end

local function CreatePvPDetailDialog()
    local f = CreateFrame("Frame", "ForeverWatchPvPDetailDialog", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(468, 490)
    f:SetPoint("CENTER", UIParent, "CENTER", 40, 20)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "ForeverWatchPvPDetailDialog")

    if f.TitleText then
        f.TitleText:SetText(FW.GetEnemyIconMarkup(false, 14) .. " " .. L.DETAIL_TITLE)
    end

    local inset = f.Inset or f
    local rockBg = inset:CreateTexture(nil, "BACKGROUND")
    rockBg:SetPoint("TOPLEFT", inset, "TOPLEFT", 3, -3)
    rockBg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -3, 3)
    rockBg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    rockBg:SetHorizTile(true)
    rockBg:SetVertTile(true)
    rockBg:SetVertexColor(0.58, 0.58, 0.64, 0.96)

    -- 1. Identity Header Card
    local headerBox = CreateFrame("Frame", nil, inset, "BackdropTemplate")
    headerBox:SetSize(432, 52)
    headerBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    headerBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    headerBox:SetBackdropColor(0.08, 0.08, 0.11, 0.94)
    headerBox:SetBackdropBorderColor(0.75, 0.62, 0.28, 0.90)
    f.headerBox = headerBox

    local headIcon = headerBox:CreateTexture(nil, "OVERLAY")
    headIcon:SetSize(28, 28)
    headIcon:SetPoint("LEFT", headerBox, "LEFT", 12, 0)
    f.headIcon = headIcon

    local headName = headerBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headName:SetPoint("TOPLEFT", headIcon, "TOPRIGHT", 10, 2)
    headName:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    headName:SetJustifyH("LEFT")
    headName:SetWordWrap(false)
    f.headName = headName

    local headSub = headerBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headSub:SetPoint("TOPLEFT", headName, "BOTTOMLEFT", 0, -4)
    headSub:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    headSub:SetJustifyH("LEFT")
    headSub:SetWordWrap(false)
    f.headSub = headSub

    -- 2. Four H2H Mini KPI Cards (4 * 102 + 3 * 8 = 432)
    local miniKills = CreateMiniStatCard(inset, 102, 54, L.DETAIL_CARD_KILLS, 0.30, 0.85, 0.42)
    miniKills:SetPoint("TOPLEFT", headerBox, "BOTTOMLEFT", 0, -8)
    f.miniKills = miniKills

    local miniDeaths = CreateMiniStatCard(inset, 102, 54, L.DETAIL_CARD_DEATHS, 0.90, 0.30, 0.32)
    miniDeaths:SetPoint("LEFT", miniKills, "RIGHT", 8, 0)
    f.miniDeaths = miniDeaths

    local miniKD = CreateMiniStatCard(inset, 102, 54, L.DETAIL_CARD_KD, 0.95, 0.78, 0.25)
    miniKD:SetPoint("LEFT", miniDeaths, "RIGHT", 8, 0)
    f.miniKD = miniKD

    local miniNet = CreateMiniStatCard(inset, 102, 54, L.DETAIL_CARD_NET, 0.75, 0.62, 0.30)
    miniNet:SetPoint("LEFT", miniKD, "RIGHT", 8, 0)
    f.miniNet = miniNet

    -- 3. Head-to-Head Win/Loss Bar
    local ratioBar = CreateRatioBar(inset, 432, 18)
    ratioBar:SetPoint("TOPLEFT", miniKills, "BOTTOMLEFT", 0, -6)
    f.ratioBar = ratioBar

    -- 4. Meta Info Box
    local metaBox = CreateFrame("Frame", nil, inset, "BackdropTemplate")
    metaBox:SetSize(432, 76)
    metaBox:SetPoint("TOPLEFT", ratioBar, "BOTTOMLEFT", 0, -6)
    metaBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    metaBox:SetBackdropColor(0.07, 0.07, 0.10, 0.88)
    metaBox:SetBackdropBorderColor(0.42, 0.38, 0.28, 0.80)

    local metaLine1 = metaBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metaLine1:SetPoint("TOPLEFT", metaBox, "TOPLEFT", 10, -7)
    metaLine1:SetPoint("RIGHT", metaBox, "RIGHT", -10, 0)
    metaLine1:SetJustifyH("LEFT")
    metaLine1:SetWordWrap(false)
    f.metaLine1 = metaLine1

    local metaLine2 = metaBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metaLine2:SetPoint("TOPLEFT", metaLine1, "BOTTOMLEFT", 0, -4)
    metaLine2:SetPoint("RIGHT", metaBox, "RIGHT", -10, 0)
    metaLine2:SetJustifyH("LEFT")
    metaLine2:SetWordWrap(false)
    f.metaLine2 = metaLine2

    local metaLine3 = metaBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metaLine3:SetPoint("TOPLEFT", metaLine2, "BOTTOMLEFT", 0, -4)
    metaLine3:SetPoint("RIGHT", metaBox, "RIGHT", -10, 0)
    metaLine3:SetJustifyH("LEFT")
    metaLine3:SetWordWrap(false)
    f.metaLine3 = metaLine3

    local metaLine4 = metaBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLine4:SetPoint("TOPLEFT", metaLine3, "BOTTOMLEFT", 0, -4)
    metaLine4:SetPoint("RIGHT", metaBox, "RIGHT", -10, 0)
    metaLine4:SetJustifyH("LEFT")
    metaLine4:SetWordWrap(true)
    f.metaLine4 = metaLine4

    -- 5. Per-Opponent Encounter Log
    local histHeader = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histHeader:SetPoint("TOPLEFT", metaBox, "BOTTOMLEFT", 2, -8)
    f.histHeader = histHeader

    local sf = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", histHeader, "BOTTOMLEFT", -2, -5)
    sf:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -30, 42)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(402)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    f.scrollChild = child

    local histEmpty = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    histEmpty:SetPoint("CENTER", sf, "CENTER", 0, 0)
    histEmpty:SetText(L.DETAIL_HISTORY_EMPTY)
    f.histEmpty = histEmpty

    -- 6. Bottom Action Buttons
    local btnNem = CreateWowButton(f, L.MGR_ROW_MARK_NEM, 92, 24, function()
        if not f.targetKey then return end
        local enemyRec = FW.FindEnemyRecord(f.targetKey, f.targetGuid, f.targetRealm)
        if enemyRec then
            FW.SetEnemyNemesis(enemyRec.key, not enemyRec.isNemesis)
        elseif FW.RecordEnemyAction then
            FW.RecordEnemyAction({
                key = f.targetKey,
                name = FW.GetShortName(f.targetKey),
                realm = f.targetRealm,
                guid = f.targetGuid,
                class = f.targetClass,
                level = f.targetLevel or 0,
            }, "manual_nemesis")
        end
        RefreshPvPDetailDialog()
    end)
    btnNem:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
    f.btnNem = btnNem

    local btnTag = CreateWowButton(f, L.DETAIL_BTN_TAG, 82, 24, function()
        if f.targetKey and FW.OpenTagDialog then
            FW.OpenTagDialog(f.targetKey, f.targetGuid, f.targetClass)
        end
    end)
    btnTag:SetPoint("LEFT", btnNem, "RIGHT", 8, 0)
    f.btnTag = btnTag

    local btnDel = CreateWowButton(f, L.DETAIL_BTN_DEL, 88, 24, function()
        if f.targetKey and FW.DeletePvPEnemyStats then
            FW.DeletePvPEnemyStats(f.targetKey)
            f:Hide()
        end
    end)
    btnDel:SetPoint("LEFT", btnTag, "RIGHT", 8, 0)
    f.btnDel = btnDel

    local btnClose = CreateWowButton(f, L.DETAIL_BTN_CLOSE, 76, 24, function()
        f:Hide()
    end)
    btnClose:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)

    f:Hide()
    return f
end

function FW.OpenPvPDetailDialog(playerKey)
    if not playerKey or playerKey == "" then return end
    if not detailDialog then
        detailDialog = CreatePvPDetailDialog()
    end
    detailDialog.targetKey = playerKey
    detailDialog:Show()
    detailDialog:Raise()
    RefreshPvPDetailDialog()
end

-- ============================================================
-- Tagged Player Detail Dialog (for Tab 2: Player Tags)
-- ============================================================

local function RefreshTagDetailDialog()
    if not tagDetailDialog or not tagDetailDialog:IsShown() or not tagDetailDialog.targetKey then return end
    local key = tagDetailDialog.targetKey
    local rec = FW.db and FW.db.tags and FW.db.tags[key] or FW.FindTagRecord(key)
    if not rec then
        tagDetailDialog:Hide()
        return
    end
    key = rec.key or key
    tagDetailDialog.targetKey = key
    tagDetailDialog.targetGuid = rec.guid
    tagDetailDialog.targetClass = rec.class

    local cInfo = FW.GetTagColorInfo(rec.color)
    local _, realm = FW.SplitNameRealm(key)
    realm = realm or FW.GetMyRealm()

    FW.ApplyIconToTexture(tagDetailDialog.headIcon, FW.GetTagIconDef())
    if cInfo.id == "GOLD" then
        tagDetailDialog.headIcon:SetVertexColor(1, 1, 1, 1)
    else
        tagDetailDialog.headIcon:SetVertexColor(cInfo.r, cInfo.g, cInfo.b, 1)
    end
    tagDetailDialog.headerBox:SetBackdropBorderColor(cInfo.r, cInfo.g, cInfo.b, 0.90)

    tagDetailDialog.headName:SetText(FW.ColorizeName(FW.GetDisplayName(key), rec.class))
    local clsStr = FW.ColorizeName(FW.GetLocalizedClassName(rec.class), rec.class)
    local enemyRec = FW.FindEnemyRecord(key, rec.guid, realm)
    local pvpRec = FW.FindPvPEnemyStats(key, rec.guid, realm)
    local lvl = (enemyRec and enemyRec.level and enemyRec.level ~= 0) and enemyRec.level
        or (pvpRec and pvpRec.level) or 0
    tagDetailDialog.headSub:SetText(string.format(L.DETAIL_IDENTITY_SUB,
        FormatLevelBadge(lvl), clsStr, FW.ColorizeName(FW.GetFullName(key), rec.class)))

    if rec.tags and #rec.tags > 0 then
        local chips = {}
        for _, t in ipairs(rec.tags) do
            chips[#chips + 1] = string.format("|cff%s[%s]|r", cInfo.hex, t)
        end
        tagDetailDialog.tagsBody:SetText(table.concat(chips, "   "))
    else
        tagDetailDialog.tagsBody:SetText("|cff888888" .. L.TAG_DETAIL_NO_TAGS .. "|r")
    end

    if rec.note and rec.note ~= "" then
        tagDetailDialog.noteBody:SetText(rec.note)
        tagDetailDialog.noteBody:SetTextColor(0.95, 0.95, 0.98)
    else
        tagDetailDialog.noteBody:SetText(L.TAG_DETAIL_NO_NOTE)
        tagDetailDialog.noteBody:SetTextColor(0.55, 0.55, 0.58)
    end

    local createdStr = (rec.createdAt and date) and date("%Y-%m-%d %H:%M", rec.createdAt) or FW.FormatRelativeTime(rec.createdAt)
    local updatedStr = FW.FormatRelativeTime(rec.updatedAt)
    tagDetailDialog.metaTime:SetText(string.format(L.TAG_DETAIL_META_TIME, createdStr, updatedStr))

    local hasPvP = (enemyRec ~= nil) or (pvpRec ~= nil)
    tagDetailDialog.btnPvP:SetShown(hasPvP)
end

local function CreateTagDetailDialog()
    local f = CreateFrame("Frame", "ForeverWatchTagDetailDialog", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(436, 336)
    f:SetPoint("CENTER", UIParent, "CENTER", 40, 20)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, "ForeverWatchTagDetailDialog")

    if f.TitleText then
        f.TitleText:SetText(FW.GetTagIconMarkup(14) .. " " .. L.TAG_DETAIL_TITLE)
    end

    local inset = f.Inset or f
    local rockBg = inset:CreateTexture(nil, "BACKGROUND")
    rockBg:SetPoint("TOPLEFT", inset, "TOPLEFT", 3, -3)
    rockBg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -3, 3)
    rockBg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    rockBg:SetHorizTile(true)
    rockBg:SetVertTile(true)
    rockBg:SetVertexColor(0.58, 0.58, 0.64, 0.96)

    -- Header box
    local headerBox = CreateFrame("Frame", nil, inset, "BackdropTemplate")
    headerBox:SetSize(400, 50)
    headerBox:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -10)
    headerBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    headerBox:SetBackdropColor(0.08, 0.08, 0.11, 0.94)
    f.headerBox = headerBox

    local headIcon = headerBox:CreateTexture(nil, "OVERLAY")
    headIcon:SetSize(26, 26)
    headIcon:SetPoint("LEFT", headerBox, "LEFT", 12, 0)
    f.headIcon = headIcon

    local headName = headerBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headName:SetPoint("TOPLEFT", headIcon, "TOPRIGHT", 10, 2)
    headName:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    headName:SetJustifyH("LEFT")
    headName:SetWordWrap(false)
    f.headName = headName

    local headSub = headerBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headSub:SetPoint("TOPLEFT", headName, "BOTTOMLEFT", 0, -4)
    headSub:SetPoint("RIGHT", headerBox, "RIGHT", -10, 0)
    headSub:SetJustifyH("LEFT")
    headSub:SetWordWrap(false)
    f.headSub = headSub

    -- Full Tags box
    local tagsHdr = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagsHdr:SetPoint("TOPLEFT", headerBox, "BOTTOMLEFT", 2, -10)
    tagsHdr:SetText(L.TAG_DETAIL_TAGS_HDR)

    local tagsBox = CreateFrame("Frame", nil, inset, "BackdropTemplate")
    tagsBox:SetSize(400, 52)
    tagsBox:SetPoint("TOPLEFT", tagsHdr, "BOTTOMLEFT", -2, -4)
    tagsBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    tagsBox:SetBackdropColor(0.07, 0.07, 0.10, 0.90)
    tagsBox:SetBackdropBorderColor(0.45, 0.40, 0.28, 0.82)

    local tagsBody = tagsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagsBody:SetPoint("TOPLEFT", tagsBox, "TOPLEFT", 10, -8)
    tagsBody:SetPoint("BOTTOMRIGHT", tagsBox, "BOTTOMRIGHT", -10, 8)
    tagsBody:SetJustifyH("LEFT")
    tagsBody:SetJustifyV("TOP")
    tagsBody:SetWordWrap(true)
    f.tagsBody = tagsBody

    -- Full Note box
    local noteHdr = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteHdr:SetPoint("TOPLEFT", tagsBox, "BOTTOMLEFT", 2, -10)
    noteHdr:SetText(L.TAG_DETAIL_NOTE_HDR)

    local noteBox = CreateFrame("Frame", nil, inset, "BackdropTemplate")
    noteBox:SetSize(400, 72)
    noteBox:SetPoint("TOPLEFT", noteHdr, "BOTTOMLEFT", -2, -4)
    noteBox:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    noteBox:SetBackdropColor(0.07, 0.07, 0.10, 0.90)
    noteBox:SetBackdropBorderColor(0.45, 0.40, 0.28, 0.82)

    local noteBody = noteBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    noteBody:SetPoint("TOPLEFT", noteBox, "TOPLEFT", 10, -8)
    noteBody:SetPoint("BOTTOMRIGHT", noteBox, "BOTTOMRIGHT", -10, 8)
    noteBody:SetJustifyH("LEFT")
    noteBody:SetJustifyV("TOP")
    noteBody:SetWordWrap(true)
    f.noteBody = noteBody

    local metaTime = inset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaTime:SetPoint("TOPLEFT", noteBox, "BOTTOMLEFT", 2, -8)
    metaTime:SetPoint("RIGHT", noteBox, "RIGHT", -2, 0)
    metaTime:SetJustifyH("LEFT")
    f.metaTime = metaTime

    -- Footer Buttons
    local btnEdit = CreateWowButton(f, L.MGR_ROW_EDIT, 80, 24, function()
        if f.targetKey and FW.OpenTagDialog then
            FW.OpenTagDialog(f.targetKey, f.targetGuid, f.targetClass)
        end
    end)
    btnEdit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)

    local btnDel = CreateWowButton(f, L.TAG_BTN_CLEAR, 84, 24, function()
        if f.targetKey and FW.DeletePlayerTag then
            FW.DeletePlayerTag(f.targetKey)
            f:Hide()
        end
    end)
    btnDel:SetPoint("LEFT", btnEdit, "RIGHT", 8, 0)

    local btnPvP = CreateWowButton(f, L.TAG_DETAIL_BTN_PVP, 96, 24, function()
        if f.targetKey and FW.OpenPvPDetailDialog then
            FW.OpenPvPDetailDialog(f.targetKey)
        end
    end)
    btnPvP:SetPoint("LEFT", btnDel, "RIGHT", 8, 0)
    btnPvP:Hide()
    f.btnPvP = btnPvP

    local btnClose = CreateWowButton(f, L.DETAIL_BTN_CLOSE, 76, 24, function()
        f:Hide()
    end)
    btnClose:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)

    f:Hide()
    return f
end

function FW.OpenTagDetailDialog(playerKey)
    if not playerKey or playerKey == "" then return end
    if not tagDetailDialog then
        tagDetailDialog = CreateTagDetailDialog()
    end
    tagDetailDialog.targetKey = playerKey
    tagDetailDialog:Show()
    tagDetailDialog:Raise()
    RefreshTagDetailDialog()
end

local function OpenStatsRowMenu(anchor, key, classFile, guid, realm, level)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        FW.OpenPvPDetailDialog(key)
        return
    end
    MenuUtil.CreateContextMenu(anchor, function(owner, rootDescription)
        local displayName = FW.GetDisplayName(key)
        rootDescription:CreateTitle(FW.ColorizeName(displayName, classFile) .. "  " .. FormatLevelBadge(level))
        rootDescription:CreateButton(FW.GetEnemyIconMarkup(false, 14) .. " " .. L.STATS_MENU_DETAIL, function()
            FW.OpenPvPDetailDialog(key)
        end)
        local tagRec = FW.FindTagRecord(key, guid, realm)
        rootDescription:CreateButton(FW.GetEditIconMarkup(14) .. " " .. (tagRec and string.format(L.MENU_EDIT_TAG, FW.GetTagColorInfo(tagRec.color).hex, FW.FormatTagsInline(tagRec) ~= "" and FW.FormatTagsInline(tagRec) or L.TAG_NOTE_FALLBACK) or L.MENU_ADD_TAG), function()
            FW.OpenTagDialog(key, guid, classFile)
        end)
        local enemyRec = FW.FindEnemyRecord(key, guid, realm)
        if enemyRec and enemyRec.isNemesis then
            rootDescription:CreateButton(FW.GetEnemyIconMarkup(true, 14) .. " |cffE040FB" .. L.RADAR_MENU_UNMARK_NEMESIS .. "|r", function()
                FW.SetEnemyNemesis(enemyRec.key, false)
            end)
        else
            rootDescription:CreateButton(FW.GetEnemyIconMarkup(true, 14) .. " |cffE040FB" .. L.RADAR_MENU_MARK_NEMESIS .. "|r", function()
                FW.RecordEnemyAction({
                    key = key,
                    name = FW.GetShortName(key),
                    realm = realm or FW.GetMyRealm(),
                    guid = guid,
                    class = classFile,
                    level = level or 0,
                }, "manual_nemesis")
            end)
        end
        if FW.db and FW.db.pvpStats and FW.db.pvpStats.byEnemy and FW.db.pvpStats.byEnemy[key] then
            rootDescription:CreateDivider()
            rootDescription:CreateButton(L.STATS_MENU_DEL_RECORD, function()
                FW.DeletePvPEnemyStats(key)
            end)
        end
    end)
end

local function GetStatsSortLabel()
    if statsEnemySort == "kills" then return L.STATS_SORT_KILLS end
    if statsEnemySort == "deaths" then return L.STATS_SORT_DEATHS end
    if statsEnemySort == "kd" then return L.STATS_SORT_KD end
    if statsEnemySort == "recent" then return L.STATS_SORT_RECENT end
    return L.STATS_SORT_TOTAL
end

local function GetStatsFilterLabel()
    if statsHistoryFilter == "kill" then return L.STATS_FILTER_KILL end
    if statsHistoryFilter == "death" then return L.STATS_FILTER_DEATH end
    return L.STATS_FILTER_ALL
end

local function RefreshStatsTab()
    local panel = managerFrame.statsPanel
    if not panel then return end
    panel.enemyRows = panel.enemyRows or {}
    panel.historyRows = panel.historyRows or {}

    local stats = (FW.db and FW.db.pvpStats) or {}
    local ses = FW.sessionStats or {}
    local tk = stats.totalKills or 0
    local td = stats.totalDeaths or 0
    local sk = ses.kills or 0
    local sd = ses.deaths or 0
    local curStreak = stats.currentStreak or 0
    local bestStreak = stats.bestStreak or 0
    local sesBest = ses.bestStreak or 0

    -- Update top 4 KPI cards
    panel.cardKills.value:SetText(tostring(tk))
    panel.cardKills.value:SetTextColor(0.30, 1.00, 0.42)
    panel.cardKills.sub:SetText(string.format(L.STATS_SUB_SESSION, sk))

    panel.cardDeaths.value:SetText(tostring(td))
    panel.cardDeaths.value:SetTextColor(1.00, 0.35, 0.35)
    panel.cardDeaths.sub:SetText(string.format(L.STATS_SUB_SESSION, sd))

    local kdText = FW.FormatKDRatio(tk, td, 2)
    panel.cardKD.value:SetText(kdText)
    if tk > 0 and tk >= td then
        panel.cardKD.value:SetTextColor(0.30, 1.00, 0.42)
    elseif td > tk then
        panel.cardKD.value:SetTextColor(1.00, 0.40, 0.35)
    else
        panel.cardKD.value:SetTextColor(1.00, 0.82, 0.00)
    end
    local totalEncounters = tk + td
    local winRate = totalEncounters > 0 and math.floor((tk / totalEncounters) * 100 + 0.5) or 0
    panel.cardKD.sub:SetText(string.format(L.STATS_SUB_WINRATE, winRate, FW.FormatKDRatio(sk, sd, 2)))

    panel.cardStreak.value:SetText(tostring(curStreak))
    panel.cardStreak.value:SetTextColor(1.00, 0.72, 0.20)
    panel.cardStreak.sub:SetText(string.format(L.STATS_SUB_BEST_STREAK, bestStreak, sesBest))

    -- Update overall Kill/Death Ratio visual bar
    if totalEncounters > 0 then
        panel.ratioBar:SetRatio(tk, td, string.format(L.STATS_RATIO_BAR_FMT,
            winRate, tk, td, sk, sd, FW.FormatKDRatio(sk, sd, 2)))
    else
        panel.ratioBar:SetRatio(0, 0, L.STATS_RATIO_BAR_EMPTY)
    end

    -- Update sub-view switcher, column headers & sort/filter button
    local isEnemyView = (statsViewMode == "enemies")
    StyleTogglePill(panel.btnViewEnemies, isEnemyView)
    StyleTogglePill(panel.btnViewHistory, not isEnemyView)
    panel.enemyColHeader:SetShown(isEnemyView)
    panel.historyColHeader:SetShown(not isEnemyView)
    if isEnemyView then
        panel.modeActionBtn:SetText(GetStatsSortLabel())
    else
        panel.modeActionBtn:SetText(GetStatsFilterLabel())
    end
    SizeButtonToText(panel.modeActionBtn, 114, 24)

    local content = panel.scrollChild
    local query = FW.Trim(searchText):lower()

    if isEnemyView then
        for i = 1, #panel.historyRows do
            panel.historyRows[i]:Hide()
        end

        local list = {}
        local sumK, sumD = 0, 0
        if type(stats.byEnemy) == "table" then
            for key, rec in pairs(stats.byEnemy) do
                local k = rec.kills or 0
                local d = rec.deaths or 0
                if k > 0 or d > 0 then
                    local matchSearch = true
                    if query ~= "" then
                        local clsName = FW.GetLocalizedClassName(rec.class)
                        local hay = (key .. " " .. (rec.lastZone or "") .. " " .. (rec.class or "") .. " " .. clsName .. " " .. FW.FormatLevelText(rec.level)):lower()
                        matchSearch = hay:find(query, 1, true) ~= nil
                    end
                    if matchSearch then
                        sumK = sumK + k
                        sumD = sumD + d
                        local kdVal = d > 0 and (k / d) or k
                        list[#list + 1] = { key = key, rec = rec, kills = k, deaths = d, total = k + d, kd = kdVal }
                    end
                end
            end
        end

        table.sort(list, function(a, b)
            if statsEnemySort == "kills" then
                if a.kills ~= b.kills then return a.kills > b.kills end
                if a.total ~= b.total then return a.total > b.total end
            elseif statsEnemySort == "deaths" then
                if a.deaths ~= b.deaths then return a.deaths > b.deaths end
                if a.total ~= b.total then return a.total > b.total end
            elseif statsEnemySort == "kd" then
                if a.kd ~= b.kd then return a.kd > b.kd end
                if a.kills ~= b.kills then return a.kills > b.kills end
            elseif statsEnemySort == "recent" then
                if (a.rec.lastSeen or 0) ~= (b.rec.lastSeen or 0) then
                    return (a.rec.lastSeen or 0) > (b.rec.lastSeen or 0)
                end
            else
                if a.total ~= b.total then return a.total > b.total end
                if a.kills ~= b.kills then return a.kills > b.kills end
            end
            return (a.rec.lastSeen or 0) > (b.rec.lastSeen or 0)
        end)

        panel.countText:SetText(string.format(L.STATS_COUNT_ENEMIES, #list, sumK, sumD))
        panel.emptyText:SetText(L.STATS_EMPTY_ENEMIES)

        local rowHeight = 48
        for i, item in ipairs(list) do
            local row = panel.enemyRows[i]
            if not row then
                row = CreateClickableRowCard(content, 606, rowHeight - 4)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)

                row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.rankText:SetPoint("LEFT", row, "LEFT", 10, 0)
                row.rankText:SetWidth(26)
                row.rankText:SetJustifyH("LEFT")

                row.icon = row:CreateTexture(nil, "OVERLAY")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row, "LEFT", 38, 0)

                row.line1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.line1:SetPoint("TOPLEFT", row, "TOPLEFT", 64, -7)
                row.line1:SetWidth(300)
                row.line1:SetJustifyH("LEFT")
                row.line1:SetWordWrap(false)

                row.line2 = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.line2:SetPoint("TOPLEFT", row.line1, "BOTTOMLEFT", 0, -4)
                row.line2:SetWidth(300)
                row.line2:SetJustifyH("LEFT")
                row.line2:SetWordWrap(false)

                -- Fixed-width aligned numeric columns matching enemyColHeader
                row.colNet = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.colNet:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.colNet:SetWidth(52)
                row.colNet:SetJustifyH("RIGHT")

                row.colKD = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.colKD:SetPoint("RIGHT", row, "RIGHT", -66, 0)
                row.colKD:SetWidth(56)
                row.colKD:SetJustifyH("CENTER")

                row.colDeaths = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.colDeaths:SetPoint("RIGHT", row, "RIGHT", -126, 0)
                row.colDeaths:SetWidth(54)
                row.colDeaths:SetJustifyH("CENTER")

                row.colKills = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.colKills:SetPoint("RIGHT", row, "RIGHT", -184, 0)
                row.colKills:SetWidth(54)
                row.colKills:SetJustifyH("CENTER")

                row:SetScript("OnEnter", function(self)
                    self.hoverGlow:SetAlpha(0.32)
                    local it = self.itemData
                    if not it then return end
                    local r = it.rec
                    local tot = it.kills + it.deaths
                    local wr = tot > 0 and math.floor((it.kills / tot) * 100 + 0.5) or 0
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(FW.ColorizeName(FW.GetDisplayName(it.key), r.class))
                    GameTooltip:AddLine(string.format(L.STATS_ROW_TT_LVL_CLS,
                        FW.FormatLevelText(r.level), FW.ColorizeName(FW.GetLocalizedClassName(r.class), r.class)), 1, 1, 1)
                    GameTooltip:AddLine(string.format(L.STATS_ROW_TT_SCORE,
                        it.kills, it.deaths, FW.FormatKDRatio(it.kills, it.deaths, 2), wr), 1, 1, 1)
                    GameTooltip:AddLine(string.format(L.STATS_ROW_TT_ZONE,
                        r.lastZone or L.UNKNOWN, FW.FormatRelativeTime(r.lastSeen)), 0.85, 0.85, 0.85)
                    GameTooltip:AddLine(L.STATS_ROW_TT_CLICK_HINT, 0.55, 0.85, 1.0)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.hoverGlow:SetAlpha(0)
                    GameTooltip:Hide()
                end)
                row:SetScript("OnClick", function(self, button)
                    local it = self.itemData
                    if not it then return end
                    if button == "RightButton" then
                        OpenStatsRowMenu(self, it.key, it.rec.class, it.rec.guid, it.rec.realm, it.rec.level)
                    else
                        FW.OpenPvPDetailDialog(it.key)
                    end
                end)

                panel.enemyRows[i] = row
            end

            row.itemData = item
            local rec = item.rec
            local k, d = item.kills, item.deaths
            local enemyRec = FW.FindEnemyRecord(item.key, rec.guid, rec.realm)
            local isNem = enemyRec and enemyRec.isNemesis

            if i == 1 then
                row.rankText:SetText("|cffFFD100#1|r")
            elseif i == 2 then
                row.rankText:SetText("|cffDCE4EE#2|r")
            elseif i == 3 then
                row.rankText:SetText("|cffD88B4A#3|r")
            else
                row.rankText:SetText("|cff777777#" .. i .. "|r")
            end

            if isNem then
                FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
                row.icon:SetVertexColor(1, 0.55, 1, 1)
                row.accent:SetVertexColor(0.88, 0.25, 0.98, 1)
                row:SetBackdropBorderColor(0.82, 0.28, 0.92, 0.88)
            elseif k > d then
                FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
                row.icon:SetVertexColor(0.35, 1.00, 0.45, 1)
                row.accent:SetVertexColor(0.30, 0.90, 0.42, 1)
                row:SetBackdropBorderColor(0.28, 0.72, 0.38, 0.82)
            elseif d > k then
                FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
                row.icon:SetVertexColor(1.00, 0.35, 0.35, 1)
                row.accent:SetVertexColor(0.95, 0.30, 0.30, 1)
                row:SetBackdropBorderColor(0.85, 0.28, 0.28, 0.82)
            else
                FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
                row.icon:SetVertexColor(1.00, 0.82, 0.25, 1)
                row.accent:SetVertexColor(0.95, 0.78, 0.25, 1)
                row:SetBackdropBorderColor(0.68, 0.56, 0.26, 0.82)
            end

            local lvlBadge = FormatLevelBadge(rec.level)
            local badge = enemyRec and ("  " .. FW.GetDangerLabel(enemyRec)) or ""
            row.line1:SetText(string.format("%s  |cff666666[|r%s|cff666666]|r%s",
                FW.ColorizeName(FW.GetDisplayName(item.key), rec.class), lvlBadge, badge))

            local lastResStr = (rec.lastResult == "death") and L.STATS_LAST_DEATH or L.STATS_LAST_KILL
            row.line2:SetText(string.format(L.STATS_ENEMY_SUB, lastResStr, rec.lastZone or L.UNKNOWN, FW.FormatRelativeTime(rec.lastSeen)))

            row.colKills:SetText(string.format("|cff4CFF6B%d|r", k))
            row.colDeaths:SetText(string.format("|cffFF5555%d|r", d))

            local kdStr = FW.FormatKDRatio(k, d, 2)
            if k > 0 and k >= d then
                row.colKD:SetText("|cff4CFF6B" .. kdStr .. "|r")
            elseif d > k then
                row.colKD:SetText("|cffFF6655" .. kdStr .. "|r")
            else
                row.colKD:SetText("|cffFFD100" .. kdStr .. "|r")
            end

            local diff = k - d
            if diff > 0 then
                row.colNet:SetText(string.format("|cff4CFF6B+%d|r", diff))
            elseif diff < 0 then
                row.colNet:SetText(string.format("|cffFF5555%d|r", diff))
            else
                row.colNet:SetText("|cff8888880|r")
            end
            row:Show()
        end

        for i = #list + 1, #panel.enemyRows do
            panel.enemyRows[i]:Hide()
        end
        content:SetHeight(math.max(1, #list * rowHeight))
        panel.emptyText:SetShown(#list == 0)
    else
        for i = 1, #panel.enemyRows do
            panel.enemyRows[i]:Hide()
        end

        local list = {}
        if type(stats.history) == "table" then
            for _, entry in ipairs(stats.history) do
                local matchFilter = (statsHistoryFilter == "all")
                    or (statsHistoryFilter == "kill" and entry.type == "kill")
                    or (statsHistoryFilter == "death" and entry.type == "death")
                if matchFilter then
                    local matchSearch = true
                    if query ~= "" then
                        local hay = ((entry.key or "") .. " " .. (entry.name or "") .. " " .. (entry.zone or "") .. " " .. FW.FormatLevelText(entry.level)):lower()
                        matchSearch = hay:find(query, 1, true) ~= nil
                    end
                    if matchSearch then
                        list[#list + 1] = entry
                    end
                end
            end
        end

        panel.countText:SetText(string.format(L.STATS_COUNT_HISTORY, #list))
        panel.emptyText:SetText(L.STATS_EMPTY_HISTORY)

        local rowHeight = 38
        for i, entry in ipairs(list) do
            local row = panel.historyRows[i]
            if not row then
                row = CreateClickableRowCard(content, 606, rowHeight - 4)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * rowHeight)

                row.icon = row:CreateTexture(nil, "OVERLAY")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", row, "LEFT", 12, 0)

                row.leftText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.leftText:SetPoint("LEFT", row, "LEFT", 34, 0)
                row.leftText:SetWidth(258)
                row.leftText:SetJustifyH("LEFT")
                row.leftText:SetWordWrap(false)

                row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.zoneText:SetPoint("LEFT", row, "LEFT", 300, 0)
                row.zoneText:SetWidth(142)
                row.zoneText:SetJustifyH("LEFT")
                row.zoneText:SetWordWrap(false)

                row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.timeText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.timeText:SetWidth(152)
                row.timeText:SetJustifyH("RIGHT")
                row.timeText:SetWordWrap(false)

                row:SetScript("OnEnter", function(self)
                    self.hoverGlow:SetAlpha(0.32)
                    local en = self.entryData
                    if not en or not en.key then return end
                    local pRec = FW.FindPvPEnemyStats(en.key)
                    local lvl = (en.level and en.level ~= 0) and en.level or (pRec and pRec.level) or 0
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(FW.ColorizeName(FW.GetDisplayName(en.key), en.class))
                    GameTooltip:AddLine(string.format(L.STATS_ROW_TT_LVL_CLS,
                        FW.FormatLevelText(lvl), FW.ColorizeName(FW.GetLocalizedClassName(en.class), en.class)), 1, 1, 1)
                    if pRec then
                        local tot = (pRec.kills or 0) + (pRec.deaths or 0)
                        local wr = tot > 0 and math.floor(((pRec.kills or 0) / tot) * 100 + 0.5) or 0
                        GameTooltip:AddLine(string.format(L.STATS_ROW_TT_SCORE,
                            pRec.kills or 0, pRec.deaths or 0, FW.FormatKDRatio(pRec.kills or 0, pRec.deaths or 0, 2), wr), 1, 1, 1)
                    end
                    GameTooltip:AddLine(L.STATS_ROW_TT_CLICK_HINT, 0.55, 0.85, 1.0)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.hoverGlow:SetAlpha(0)
                    GameTooltip:Hide()
                end)
                row:SetScript("OnClick", function(self, button)
                    local en = self.entryData
                    if not en or not en.key then return end
                    if button == "RightButton" then
                        local pRec = FW.FindPvPEnemyStats(en.key)
                        OpenStatsRowMenu(self, en.key, en.class, pRec and pRec.guid, pRec and pRec.realm, en.level or (pRec and pRec.level))
                    else
                        FW.OpenPvPDetailDialog(en.key)
                    end
                end)

                panel.historyRows[i] = row
            end

            row.entryData = entry
            local isKill = entry.type == "kill"
            local badge
            if isKill then
                if entry.wasNemesis then
                    FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
                    row.icon:SetVertexColor(0.95, 0.55, 1.00, 1)
                    row.accent:SetVertexColor(0.88, 0.25, 0.98, 1)
                    row:SetBackdropBorderColor(0.82, 0.28, 0.92, 0.88)
                    badge = L.STATS_BADGE_REVENGE
                else
                    FW.ApplyIconToTexture(row.icon, FW.ICONS.DANGER_SWORD)
                    row.icon:SetVertexColor(0.35, 1.00, 0.45, 1)
                    row.accent:SetVertexColor(0.30, 0.90, 0.42, 1)
                    row:SetBackdropBorderColor(0.28, 0.72, 0.38, 0.80)
                    badge = L.STATS_BADGE_KILL
                end
            else
                FW.ApplyIconToTexture(row.icon, FW.ICONS.NEMESIS)
                row.icon:SetVertexColor(1.00, 0.35, 0.35, 1)
                row.accent:SetVertexColor(0.95, 0.30, 0.30, 1)
                row:SetBackdropBorderColor(0.85, 0.28, 0.28, 0.82)
                badge = L.STATS_BADGE_DEATH
            end

            local pRec = entry.key and FW.FindPvPEnemyStats(entry.key) or nil
            local oppLvl = (entry.level and entry.level ~= 0) and entry.level or (pRec and pRec.level) or 0
            row.leftText:SetText(string.format("%s %s %s",
                badge,
                FW.ColorizeName(FW.GetDisplayName(entry.key or entry.name), entry.class),
                FormatLevelBadge(oppLvl)))

            row.zoneText:SetText("|cffCCCCCC" .. (entry.zone or L.UNKNOWN) .. "|r")

            local clockStr = (entry.time and date) and date("%m-%d %H:%M", entry.time) or ""
            local relStr = FW.FormatRelativeTime(entry.time)
            row.timeText:SetText(clockStr ~= "" and (clockStr .. " · " .. relStr) or relStr)
            row:Show()
        end

        for i = #list + 1, #panel.historyRows do
            panel.historyRows[i]:Hide()
        end
        content:SetHeight(math.max(1, #list * rowHeight))
        panel.emptyText:SetShown(#list == 0)
    end
end

-- ============================================================
-- Tab 4: Settings
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
    if panel.durationSlider then
        local sec = math.floor((tonumber(FW.settings.bannerDuration) or 5) + 0.5)
        if sec < 2 then sec = 2 elseif sec > 15 then sec = 15 end
        panel.durationSlider:SetValue(sec)
        panel.durationValueText:SetText(string.format(L.SEC_FMT, sec))
    end
    if panel.radarTimeoutSlider then
        local sec = math.floor((tonumber(FW.settings.radarTimeout) or 18) + 0.5)
        if sec < 3 then sec = 3 elseif sec > 60 then sec = 60 end
        panel.radarTimeoutSlider:SetValue(sec)
        panel.radarTimeoutValueText:SetText(string.format(L.SEC_FMT, sec))
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
    managerFrame.statsPanel:SetShown(tabName == "stats")
    managerFrame.settingsPanel:SetShown(tabName == "settings")
    managerFrame.searchHolder:SetShown(tabName ~= "settings")

    local idx = TAB_INDEX[tabName] or 1
    if PanelTemplates_SetTab then
        PanelTemplates_SetTab(managerFrame, idx)
    end

    FW.RefreshManagerUI()
end

local function CreateScrollArea(parent, topOffset)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -(topOffset or 8))
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 8)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(608)
    child:SetHeight(1)
    sf:SetScrollChild(child)

    local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", sf, "CENTER", 0, 0)
    return sf, child, empty
end

local function CreateManagerUI()
    local f = CreateFrame("Frame", "ForeverWatchManagerFrame", UIParent, "ButtonFrameTemplate")
    f:SetSize(660, 666)
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

    -- ===== Tab 3: PvP Kill & Death Stats =====
    if StaticPopupDialogs and not StaticPopupDialogs["FOREVERWATCH_RESET_PVP_STATS"] then
        StaticPopupDialogs["FOREVERWATCH_RESET_PVP_STATS"] = {
            text = L.PVP_STATS_RESET_CONFIRM,
            button1 = YES or OKAY,
            button2 = NO or CANCEL,
            OnAccept = function()
                if FW.ResetAllPvPStats then
                    FW.ResetAllPvPStats()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local statsPanel = CreateFrame("Frame", nil, inset)
    statsPanel:SetAllPoints()
    f.statsPanel = statsPanel

    local resetAllBtn = CreateWowButton(statsPanel, L.STATS_BTN_RESET_ALL, 88, 22, function()
        if StaticPopupDialogs and StaticPopupDialogs["FOREVERWATCH_RESET_PVP_STATS"] then
            StaticPopupDialogs["FOREVERWATCH_RESET_PVP_STATS"].text = L.PVP_STATS_RESET_CONFIRM
        end
        if StaticPopup_Show then
            StaticPopup_Show("FOREVERWATCH_RESET_PVP_STATS")
        elseif FW.ResetAllPvPStats then
            FW.ResetAllPvPStats()
        end
    end)
    resetAllBtn:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -4, 6)

    local resetSessionBtn = CreateWowButton(statsPanel, L.STATS_BTN_RESET_SESSION, 96, 22, function()
        if FW.ResetSessionPvPStats then
            FW.ResetSessionPvPStats()
        end
    end)
    resetSessionBtn:SetPoint("RIGHT", resetAllBtn, "LEFT", -8, 0)

    -- Top 4 KPI summary cards (width: 4 * 150 + 3 * 8 = 624 inside ~644 inset)
    local cardKills = CreateStatKpiCard(statsPanel, 150, 78, L.STATS_CARD_KILLS, 0.30, 0.85, 0.42, FW.ICONS.DANGER_SWORD)
    cardKills:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, -8)
    statsPanel.cardKills = cardKills

    local cardDeaths = CreateStatKpiCard(statsPanel, 150, 78, L.STATS_CARD_DEATHS, 0.90, 0.30, 0.32, FW.ICONS.NEMESIS)
    cardDeaths:SetPoint("LEFT", cardKills, "RIGHT", 8, 0)
    statsPanel.cardDeaths = cardDeaths

    local cardKD = CreateStatKpiCard(statsPanel, 150, 78, L.STATS_CARD_KD, 0.95, 0.78, 0.25)
    cardKD:SetPoint("LEFT", cardDeaths, "RIGHT", 8, 0)
    statsPanel.cardKD = cardKD

    local cardStreak = CreateStatKpiCard(statsPanel, 150, 78, L.STATS_CARD_STREAK, 1.00, 0.55, 0.14)
    cardStreak:SetPoint("LEFT", cardKD, "RIGHT", 8, 0)
    statsPanel.cardStreak = cardStreak

    -- Overall Kill vs Death Visual Ratio Bar
    local ratioBar = CreateRatioBar(statsPanel, 624, 18)
    ratioBar:SetPoint("TOPLEFT", cardKills, "BOTTOMLEFT", 0, -6)
    statsPanel.ratioBar = ratioBar

    -- View switcher pills + sort/filter button
    local function CreateStatsViewPill(text, onClick)
        local btn = CreateFrame("Button", nil, statsPanel, "BackdropTemplate")
        btn:SetHeight(24)
        btn:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("CENTER", 0, 0)
        lbl:SetText(text)
        btn.label = lbl
        btn:SetWidth(math.max(108, math.ceil(lbl:GetStringWidth() + 26)))
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local btnViewEnemies = CreateStatsViewPill(L.STATS_VIEW_ENEMIES, function()
        statsViewMode = "enemies"
        RefreshStatsTab()
    end)
    btnViewEnemies:SetPoint("TOPLEFT", ratioBar, "BOTTOMLEFT", 0, -8)
    statsPanel.btnViewEnemies = btnViewEnemies

    local btnViewHistory = CreateStatsViewPill(L.STATS_VIEW_HISTORY, function()
        statsViewMode = "history"
        RefreshStatsTab()
    end)
    btnViewHistory:SetPoint("LEFT", btnViewEnemies, "RIGHT", 8, 0)
    statsPanel.btnViewHistory = btnViewHistory

    local modeActionBtn = CreateWowButton(statsPanel, L.STATS_SORT_TOTAL, 114, 22, function()
        if statsViewMode == "enemies" then
            local order = { total = "kills", kills = "deaths", deaths = "kd", kd = "recent", recent = "total" }
            statsEnemySort = order[statsEnemySort] or "total"
        else
            local order = { all = "kill", kill = "death", death = "all" }
            statsHistoryFilter = order[statsHistoryFilter] or "all"
        end
        RefreshStatsTab()
    end)
    modeActionBtn:SetPoint("TOPRIGHT", ratioBar, "BOTTOMRIGHT", 0, -9)
    statsPanel.modeActionBtn = modeActionBtn

    -- Column Header Strip (Enemy Leaderboard view, width 606 aligned with scroll rows)
    local enemyColHeader = CreateFrame("Frame", nil, statsPanel, "BackdropTemplate")
    enemyColHeader:SetSize(606, 20)
    enemyColHeader:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 8, -148)
    enemyColHeader:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    })
    enemyColHeader:SetBackdropColor(0.14, 0.13, 0.16, 0.85)
    local eColOpp = enemyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eColOpp:SetPoint("LEFT", enemyColHeader, "LEFT", 12, 0)
    eColOpp:SetText(L.STATS_COL_OPPONENT)
    local eColKills = enemyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eColKills:SetPoint("RIGHT", enemyColHeader, "RIGHT", -184, 0)
    eColKills:SetWidth(54)
    eColKills:SetJustifyH("CENTER")
    eColKills:SetText(L.STATS_COL_KILLS)
    local eColDeaths = enemyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eColDeaths:SetPoint("RIGHT", enemyColHeader, "RIGHT", -126, 0)
    eColDeaths:SetWidth(54)
    eColDeaths:SetJustifyH("CENTER")
    eColDeaths:SetText(L.STATS_COL_DEATHS)
    local eColKD = enemyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eColKD:SetPoint("RIGHT", enemyColHeader, "RIGHT", -66, 0)
    eColKD:SetWidth(56)
    eColKD:SetJustifyH("CENTER")
    eColKD:SetText(L.STATS_COL_KD)
    local eColNet = enemyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eColNet:SetPoint("RIGHT", enemyColHeader, "RIGHT", -10, 0)
    eColNet:SetWidth(52)
    eColNet:SetJustifyH("RIGHT")
    eColNet:SetText(L.STATS_COL_NET)
    statsPanel.enemyColHeader = enemyColHeader

    -- Column Header Strip (History Timeline view)
    local historyColHeader = CreateFrame("Frame", nil, statsPanel, "BackdropTemplate")
    historyColHeader:SetSize(606, 20)
    historyColHeader:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 8, -148)
    historyColHeader:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    })
    historyColHeader:SetBackdropColor(0.14, 0.13, 0.16, 0.85)
    local hColRes = historyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hColRes:SetPoint("LEFT", historyColHeader, "LEFT", 12, 0)
    hColRes:SetText(L.STATS_COL_RESULT)
    local hColZone = historyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hColZone:SetPoint("LEFT", historyColHeader, "LEFT", 300, 0)
    hColZone:SetText(L.STATS_COL_ZONE)
    local hColTime = historyColHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hColTime:SetPoint("RIGHT", historyColHeader, "RIGHT", -10, 0)
    hColTime:SetJustifyH("RIGHT")
    hColTime:SetText(L.STATS_COL_TIME)
    historyColHeader:Hide()
    statsPanel.historyColHeader = historyColHeader

    statsPanel.countText = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsPanel.countText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 8)

    local _, sChild, sEmpty = CreateScrollArea(statsPanel, 172)
    statsPanel.scrollChild = sChild
    statsPanel.emptyText = sEmpty
    sEmpty:SetText(L.STATS_EMPTY_ENEMIES)

    -- ===== Tab 4: Settings =====
    local settingsPanel = CreateFrame("Frame", nil, inset)
    settingsPanel:SetAllPoints()
    f.settingsPanel = settingsPanel
    settingsPanel.checkboxes = {}

    local opts = {
        { key = "enableMonitor",        text = L.OPT_MONITOR },
        { key = "monitorNonWorldPvP",   text = L.OPT_MONITOR_NON_WPVP },
        { key = "enableBanner",         text = L.OPT_BANNER },
        { key = "enableSound",          text = L.OPT_SOUND },
        { key = "enableRadar",          text = L.OPT_RADAR },
        { key = "radarLocked",          text = L.OPT_RADAR_LOCK },
        { key = "radarShowNormalEnemy", text = L.OPT_RADAR_NORMAL },
        { key = "showFullName",         text = L.OPT_SHOW_FULL_NAME },
        { key = "enableTooltipTags",    text = L.OPT_TOOLTIP },
        { key = "enableChatTags",       text = L.OPT_CHAT },
        { key = "enableNameplateIcon",  text = L.OPT_NAMEPLATE },
    }

    for i, opt in ipairs(opts) do
        local cb = CreateFrame("CheckButton", nil, settingsPanel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 16, -6 - (i - 1) * 22)
        cb:SetSize(21, 21)
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
    div1:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 14, -252)
    div1:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", -14, -252)
    div1:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    div1:SetVertexColor(0.85, 0.72, 0.35, 0.7)

    -- Tag Icon Style Picker
    local iconLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -260)
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
        btn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", ix, -278)

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
    alphaLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -312)
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

    -- Alert Banner Auto-Dismiss Duration Slider (2s - 15s)
    local durLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -340)
    durLbl:SetText(L.SET_BANNER_DURATION)

    local durSlider = CreateFrame("Slider", "ForeverWatchBannerDurationSlider", settingsPanel, "UISliderTemplate")
    durSlider:SetSize(220, 18)
    durSlider:SetPoint("LEFT", durLbl, "RIGHT", 12, 0)
    durSlider:SetMinMaxValues(2, 15)
    durSlider:SetValueStep(1)
    durSlider:SetObeyStepOnDrag(true)

    local durValueText = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    durValueText:SetPoint("LEFT", durSlider, "RIGHT", 10, 0)
    durValueText:SetText(string.format(L.SEC_FMT, 5))

    durSlider:SetScript("OnValueChanged", function(self, value)
        local sec = math.floor(value + 0.5)
        if sec < 2 then sec = 2 elseif sec > 15 then sec = 15 end
        FW.settings.bannerDuration = sec
        durValueText:SetText(string.format(L.SEC_FMT, sec))
    end)
    settingsPanel.durationSlider = durSlider
    settingsPanel.durationValueText = durValueText

    -- Radar Enemy Auto-Clear Timeout Slider (3s - 60s)
    local rtLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rtLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -368)
    rtLbl:SetText(L.SET_RADAR_TIMEOUT)

    local rtSlider = CreateFrame("Slider", "ForeverWatchRadarTimeoutSlider", settingsPanel, "UISliderTemplate")
    rtSlider:SetSize(220, 18)
    rtSlider:SetPoint("LEFT", rtLbl, "RIGHT", 12, 0)
    rtSlider:SetMinMaxValues(3, 60)
    rtSlider:SetValueStep(1)
    rtSlider:SetObeyStepOnDrag(true)

    local rtValueText = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rtValueText:SetPoint("LEFT", rtSlider, "RIGHT", 10, 0)
    rtValueText:SetText(string.format(L.SEC_FMT, 18))

    rtSlider:SetScript("OnValueChanged", function(self, value)
        local sec = math.floor(value + 0.5)
        if sec < 3 then sec = 3 elseif sec > 60 then sec = 60 end
        FW.settings.radarTimeout = sec
        rtValueText:SetText(string.format(L.SEC_FMT, sec))
        if FW.ScheduleRadarRefresh then
            FW.ScheduleRadarRefresh()
        end
    end)
    settingsPanel.radarTimeoutSlider = rtSlider
    settingsPanel.radarTimeoutValueText = rtValueText

    -- Language Switcher (Auto / zhCN / zhTW / enUS) + Reload button
    local langLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    langLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -398)
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
        btn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", lx, -416)
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
    reloadBtn:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", lx + 4, -417)

    -- Preset tags customization
    local pLbl = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pLbl:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 18, -452)
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
            if FW.RefreshRadar then FW.RefreshRadar() end
        end
        FW.Print(L.SET_POS_RESET_MSG)
    end)
    resetPosBtn:SetPoint("LEFT", testMultiBtn, "RIGHT", 10, 0)

    -- Native Blizzard Bottom Tabs
    local tabDefs = {
        { id = "enemies",  text = L.MGR_TAB_ENEMIES },
        { id = "tags",     text = L.MGR_TAB_TAGS },
        { id = "stats",    text = L.MGR_TAB_STATS },
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
    if detailDialog and detailDialog:IsShown() then
        RefreshPvPDetailDialog()
    end
    if tagDetailDialog and tagDetailDialog:IsShown() then
        RefreshTagDetailDialog()
    end
    if not managerFrame or not managerFrame:IsShown() then return end
    if currentTab == "enemies" then
        RefreshEnemiesTab()
    elseif currentTab == "tags" then
        RefreshTagsTab()
    elseif currentTab == "stats" then
        RefreshStatsTab()
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
