-- Dungeon Quest Guide: the window (the dungeon list, and the guide's steps),
-- the minimap button, /dqg, and a Guide button on the Dungeon Journal's quest
-- list for when the journal is open anyway.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 360, 470
local HEADER_LEFT, HEADER_RIGHT = 62, 14
local ROW_WIDTH = WIDTH - 20 - 16 - 22
local ROW_HEIGHT, HEADING_HEIGHT = 36, 22

local GOLD, WHITE, GREY, GREEN, RED = "|cffffd100", "|cffffffff", "|cff9d9d9d", "|cff40ff40", "|cffff6060"

local window

------------------------------------------------------------------ the dungeon list

-- Dungeons with quests for this character, by the level they start at.
local function DungeonNames()
    local FDJ = ns.FDJ() or {}
    local list = {}
    for name, data in pairs(FDJ.DB or {}) do
        if type(data) == "table" and not data.questChainPage and #ns.DungeonQuests(name) > 0 then
            list[#list + 1] = { name = name, low = tonumber(tostring(data.level or ""):match("^(%d+)")) or 99 }
        end
    end
    table.sort(list, function(a, b)
        if a.low ~= b.low then return a.low < b.low end
        return a.name < b.name
    end)
    return list
end
UI.DungeonNames = DungeonNames

-- How a dungeon's levels sit with the character's: above (orange), right
-- now (green), behind (grey).
local function LevelColor(low, high)
    local level = ns.PlayerLevel()
    if low and level < low then return "|cffff8040" end
    if high and level > high + 3 then return GREY end
    return GREEN
end

local function Range(a, b)
    if not a then return "?" end
    if not b or a == b then return tostring(a) end
    return a .. "-" .. b
end
UI.Range = Range

local function DungeonTooltip(row, info)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(info.name, 1, 0.82, 0)
    if info.location then GameTooltip:AddLine(info.location, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine("Levels " .. (info.level or "?"), 1, 1, 1)
    if #info.bosses > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Bosses", 1, 0.82, 0)
        for _, boss in ipairs(info.bosses) do
            GameTooltip:AddDoubleLine(boss.name, boss.level and ("level " .. boss.level) or "level unknown",
                1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(info.quests .. (info.quests == 1 and " quest" or " quests") .. " you can take there", 0.6, 0.8, 1)
    if ns.Guide.Active() == info.name then
        GameTooltip:AddLine("Click: back to its guide", 0.5, 1, 0.5)
    else
        GameTooltip:AddLine("Click: guide me to its quests", 0.5, 1, 0.5)
    end
    GameTooltip:Show()
end

------------------------------------------------------------------ rows

local function RowTooltip(row)
    local item = row.item
    if not item then return end
    if item.dungeonInfo then return DungeonTooltip(row, item.dungeonInfo) end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if item.itemID and GameTooltip.SetItemByID then
        pcall(GameTooltip.SetItemByID, GameTooltip, item.itemID)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(item.title or item.name or "", 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(item.title or item.name or "", 1, 0.82, 0, true)
    end
    if item.detail then GameTooltip:AddLine(item.detail, 1, 1, 1, true) end
    if item.why then GameTooltip:AddLine(item.why, 1, 0.4, 0.4, true) end
    if item.note then GameTooltip:AddLine(item.note, 0.8, 0.8, 0.8, true) end
    if item.forQuests and item.questName and (item.forQuests[1] ~= item.questName or #item.forQuests > 1) then
        GameTooltip:AddLine("For: " .. table.concat(item.forQuests, ", "), 0.6, 0.8, 1, true)
    end
    local spot = item.spot
    if spot then
        local where = spot.label or ""
        GameTooltip:AddLine(("%s (%.1f, %.1f)%s"):format(where, spot.x * 100, spot.y * 100,
            spot.fromQuestie and " - from Questie's data" or ""), 0.7, 0.7, 0.7, true)
        if spot.guess then
            GameTooltip:AddLine("The journal doesn't say where this is handed in; this is where the next step starts.", 1, 0.6, 0.2, true)
        end
    elseif item.key then
        GameTooltip:AddLine("No map spot known for this step.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(" ")
    if item.key then GameTooltip:AddLine("Click: point the arrows here", 0.5, 1, 0.5) end
    local questID = item.mainQuestID or (item.quest and item.quest.id)
    if questID then GameTooltip:AddLine("Right-click: leave this quest out (or back in)", 0.5, 1, 0.5) end
    GameTooltip:Show()
end

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetAllPoints()
    row.lit:SetColorTexture(1, 0.82, 0, 0.12)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 4, 0)
    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 2)
    row.title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local item = self.item
        if not item then return end
        if item.dungeonInfo then
            if button == "LeftButton" then
                if ns.Guide.Active() == item.dungeonInfo.name then UI.ShowWindow("guide")
                else ns.Guide.Start(item.dungeonInfo.name) end
            end
        elseif button == "RightButton" then
            ns.Guide.ToggleSkip(item.mainQuestID or (item.quest and item.quest.id))
        elseif item.key then
            ns.Guide.Focus(item)
        end
    end)
    return row
end

local function NewHeading(parent)
    local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h:SetJustifyH("LEFT")
    h:SetWidth(ROW_WIDTH)
    return h
end

------------------------------------------------------------------ the window

local function Build()
    if window then return window end
    local name = "DungeonQuestGuideFrame"
    local ok, frame = pcall(CreateFrame, "Frame", name, UIParent, "PortraitFrameTemplate")
    if not ok or not frame then frame = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset") end
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.DB().window = { point, relPoint, x, y }
    end)
    -- Closing the window keeps the guide (and its arrows) going.
    frame:SetScript("OnHide", function() if not frame.byCode then ns.CharDB().windowShown = nil end end)
    -- The journal's arrow can go (right-clicked, arrived) without the guide
    -- hearing of it: look once a second whether the note about it changed.
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.noteWait = (self.noteWait or 1) - (elapsed or 0)
        if self.noteWait > 0 then return end
        self.noteWait = 1
        if UI.view == "guide" and ns.Guide.ArrowStatus() ~= self.arrowNote then UI.Update() end
    end)
    frame:Hide()

    -- The dungeon (or "Dungeons"), and a button to the other view.
    frame.switch = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.switch:SetSize(100, 22)
    frame.switch:SetPoint("TOPRIGHT", -HEADER_RIGHT, -30)
    frame.switch:SetScript("OnClick", function()
        UI.ShowWindow(UI.view == "list" and "guide" or "list")
    end)
    frame.heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.heading:SetPoint("TOPLEFT", HEADER_LEFT + 6, -34)
    frame.heading:SetPoint("RIGHT", frame.switch, "LEFT", -6, 0)
    frame.heading:SetJustifyH("LEFT")
    frame.heading:SetWordWrap(false)

    frame.summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", HEADER_LEFT + 6, -60)
    frame.summary:SetPoint("RIGHT", frame, "RIGHT", -HEADER_RIGHT, 0)
    frame.summary:SetJustifyH("LEFT")

    local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 10, -80)
    inset:SetPoint("BOTTOMRIGHT", -10, 34)
    local scroll = CreateFrame("ScrollFrame", nil, inset, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, 10)
    scroll:SetScrollChild(content)
    frame.content, frame.rows, frame.headings = content, {}, {}

    -- Bottom: the two arrows on or off, and Stop.
    local function Check(label, x, key, tip, available)
        local c = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        c:SetSize(22, 22)
        c:SetPoint("BOTTOMLEFT", x, 7)
        c.label = c:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        c.label:SetPoint("LEFT", c, "RIGHT", 1, 0)
        c.label:SetText(label)
        c:SetScript("OnClick", function(self)
            ns.DB()[key] = self:GetChecked() and true or false
            ns.Guide.Repoint()
        end)
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            if available and not available() then GameTooltip:AddLine("Not installed or not loaded.", 1, 0.4, 0.4, true) end
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        c.key, c.available = key, available
        return c
    end
    frame.journalCheck = Check("Journal arrow", 12, "journalArrow",
        "The Dungeon Journal's arrow leads to the step you're on, with its flight, boat and hearthstone advice.")
    frame.tomtomCheck = Check("TomTom", 122, "tomtom",
        "A TomTom waypoint on the map and minimap for the step you're on. It moves on with you. TomTom's own arrow is used only when the journal arrow is off.", ns.HasTomTom)

    local stop = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stop:SetSize(90, 22)
    stop:SetPoint("BOTTOMRIGHT", -12, 7)
    stop:SetText("Turn off")
    stop:SetScript("OnClick", function() ns.Guide.Stop() end)
    frame.stop = stop

    window = frame
    return frame
end

local function Place(frame)
    frame:ClearAllPoints()
    local journal = _G.ForeverDungeonJournalFrame
    if journal and journal:IsShown() and journal:GetRight() then
        -- Beside the journal when it is open.
        local room = (UIParent:GetRight() or 0) - journal:GetRight()
        if room >= WIDTH + 4 then
            frame:SetPoint("TOPLEFT", journal, "TOPRIGHT", 4, 0)
        else
            frame:SetPoint("TOPRIGHT", journal, "TOPLEFT", -4, 0)
        end
        return
    end
    local pos = ns.DB().window
    if type(pos) == "table" and pos[1] then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    end
end

-- view: "list" (the dungeons) or "guide" (the steps); by default the guide
-- when one is running, else the list.
UI.view = "list"
function UI.ShowWindow(view)
    UI.view = view or (ns.Guide.Active() and "guide" or "list")
    if UI.view == "guide" and not ns.Guide.Active() then UI.view = "list" end
    local frame = Build()
    if not frame:IsShown() then Place(frame) end
    frame.byCode = true
    frame:Show()
    frame.byCode = nil
    ns.CharDB().windowShown = true
    UI.Update()
end

function UI.HideWindow()
    if not window then return end
    window.byCode = true
    window:Hide()
    window.byCode = nil
end

function UI.ToggleWindow()
    if window and window:IsShown() then
        window:Hide()
    else
        UI.ShowWindow()
    end
end

------------------------------------------------------------------ filling it

function UI.Update()
    UI.UpdateJournalButton()
    UI.UpdateMinimapIcon()
    if not (window and window:IsShown()) then return end
    local guide = ns.Guide
    local plan = guide.plan
    local dungeon = guide.Active()
    local FDJ = ns.FDJ() or {}
    local data = dungeon and FDJ.DB and FDJ.DB[dungeon]

    if UI.view == "guide" and not (dungeon and plan) then UI.view = "list" end
    local listing = UI.view == "list"

    if window.SetTitle then window:SetTitle("Dungeon Quest Guide") end
    local icon = (not listing and data and data.icon) or "Interface\\Icons\\INV_Misc_Map_01"
    if window.SetPortraitToAsset then
        pcall(window.SetPortraitToAsset, window, icon)
    elseif window.GetPortrait then
        local portrait = window:GetPortrait()
        if portrait then portrait:SetTexture(icon) end
    end
    window.heading:SetText(listing and "Dungeons" or dungeon)
    window.switch:SetText(listing and "Back to guide" or "All dungeons")
    window.switch:SetShown((not listing or dungeon) and true or false)
    window.stop:SetShown(dungeon and true or false)
    window.journalCheck:SetChecked(ns.DB().journalArrow and true or false)
    window.tomtomCheck:SetChecked(ns.DB().tomtom and true or false)
    window.tomtomCheck:SetEnabled(ns.HasTomTom())

    for _, row in ipairs(window.rows) do row:Hide() row.item = nil end
    for _, h in ipairs(window.headings) do h:Hide() end

    local y, nRow, nHead = 0, 0, 0
    -- wrap: may run over several lines (a note, not a section heading)
    local function Heading(text, wrap)
        nHead = nHead + 1
        local h = window.headings[nHead] or NewHeading(window.content)
        window.headings[nHead] = h
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", window.content, "TOPLEFT", 2, -y - 6)
        h:SetWordWrap(wrap and true or false)
        h:SetText(text)
        h:Show()
        local tall = wrap and (tonumber(h:GetStringHeight()) or 0) + 12 or 0
        y = y + math.max(HEADING_HEIGHT, tall)
    end
    local function Row(item, title, detail, iconPath, current)
        nRow = nRow + 1
        local row = window.rows[nRow] or NewRow(window.content)
        window.rows[nRow] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
        row.item = item
        local tex = iconPath
        if item.itemID and C_Item and C_Item.GetItemIconByID then tex = ns.Try(C_Item.GetItemIconByID, item.itemID) or tex end
        row.icon:SetTexture(tex or ns.ICONS.pickup)
        row.title:SetText(title)
        row.detail:SetText(detail or "")
        row.lit:SetShown(current and true or false)
        row:Show()
        y = y + ROW_HEIGHT
    end

    if listing then
        local list = DungeonNames()
        window.summary:SetText(GREY .. "Every dungeon with quests for you, by level. Click one to be guided to its quests.|r")
        for _, entry in ipairs(list) do
            local info = ns.DungeonInfo(entry.name)
            if info then
                local guiding = dungeon == info.name
                local detail = LevelColor(info.low, info.high) .. "Levels " .. (info.level or "?") .. "|r"
                    .. GREY .. "  ·  Bosses " .. (info.bossLow and Range(info.bossLow, info.bossHigh) or "?")
                    .. "  ·  " .. info.quests .. (info.quests == 1 and " quest" or " quests") .. "|r"
                    .. (guiding and (GREEN .. "  ·  guiding|r") or "")
                Row({ dungeonInfo = info }, (guiding and WHITE or GOLD) .. info.name .. "|r", detail, info.icon, guiding)
            end
        end
        if #list == 0 then Heading(GREY .. "No dungeon has quests for you.|r") end
        window.content:SetHeight(math.max(10, y + 4))
        return
    end

    local togo = plan.total - plan.doneCount - #plan.skipped
    window.summary:SetText(("%s%d|r of %d quests picked up or done%s"):format(togo == 0 and GREEN or GOLD,
        plan.doneCount, plan.total, (#plan.later > 0) and (" · " .. #plan.later .. " for later") or ""))

    -- No arrow on the step: say why, at the top.
    local note = ns.Guide.ArrowStatus()
    window.arrowNote = note
    if note then Heading("|cffff9933" .. note .. "|r", true) end

    local inside = ns.InInstance()
    if #plan.tasks > 0 then
        local TIER_HEADINGS = { "Quest chains first", "Then the dungeon quests out in the world", "Then the dungeon" }
        local lastTier
        if inside then Heading("When you're out again") end
        for i, task in ipairs(plan.tasks) do
            if not inside and task.tier ~= lastTier then
                lastTier = task.tier
                Heading(TIER_HEADINGS[task.tier] or "Steps")
            end
            local current = task == guide.current and not inside
            local title = (current and GREEN .. "> |r" or (GREY .. i .. ". |r")) .. (current and WHITE or GOLD) .. task.title .. "|r"
            local detail = task.detail or ""
            if task.forQuests[1] and task.forQuests[1] ~= task.questName then
                detail = "for " .. task.forQuests[1] .. (detail ~= "" and (" · " .. detail) or "")
            end
            if not task.spot and task.kind ~= "objective" and task.kind ~= "useitem" then
                detail = RED .. "(no map spot)|r " .. detail
            end
            Row(task, title, GREY .. detail .. "|r", task.icon, current)
        end
    end
    if #plan.inside > 0 then
        Heading("Inside the dungeon")
        for _, entry in ipairs(plan.inside) do
            Row(entry, GOLD .. entry.title .. "|r", GREY .. (entry.detail or "") .. "|r", entry.icon)
        end
    end
    if #plan.have > 0 then
        Heading("In your quest log")
        for _, entry in ipairs(plan.have) do
            Row(entry, WHITE .. entry.name .. "|r", GREY .. (entry.detail or "") .. "|r", ns.ICONS.objective)
        end
    end
    if #plan.later > 0 then
        Heading("Not yet")
        for _, entry in ipairs(plan.later) do
            Row(entry, GREY .. entry.name .. "|r", RED .. entry.why .. "|r", ns.ICONS.pickup)
        end
    end
    if #plan.skipped > 0 then
        Heading("Left out (right-click to put back)")
        for _, entry in ipairs(plan.skipped) do
            Row(entry, GREY .. entry.name .. "|r", GREY .. (entry.quest.pickup or "") .. "|r", ns.ICONS.pickup)
        end
    end
    if y == 0 then
        Heading(GREEN .. "Nothing left to do for this dungeon.|r")
    end
    window.content:SetHeight(math.max(10, y + 4))
end

------------------------------------------------------------------ the journal's button

-- The journal's quest list has a Track button under its "Quests" title, with
-- room left of it for a button the journal calls questRouteButton (its own
-- Route is not in the release). Guide sits there; Track moves right of it.
local journalButton

local function MakeJournalButton(journal)
    local parent = journal.questLeftPanel
    if not parent then return nil end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    local FDJ = ns.FDJ()
    if FDJ and FDJ.OwnFonts then ns.Try(FDJ.OwnFonts, b) end
    b:SetSize(80, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -30)
    b:SetText("Guide")
    b:SetScript("OnClick", function(self)
        if not self.dungeon then return end
        if ns.Guide.Active() == self.dungeon then
            if window and window:IsShown() then ns.Guide.Stop() else UI.ShowWindow() end
        else
            ns.Guide.Start(self.dungeon)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if ns.Guide.Active() == self.dungeon then
            GameTooltip:AddLine("Dungeon Quest Guide: on")
            GameTooltip:AddLine("Click to stop guiding (or to show the guide if you closed it).", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Dungeon Quest Guide")
            GameTooltip:AddLine("Step by step to every quest for this dungeon you can take: each quest chain first, "
                .. "in the quickest order from where you stand, then the entrance. The journal's arrow and TomTom lead the way.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    journal.questRouteButton = b
    return b
end

function UI.PlaceJournalButton(dungeon)
    local journal = _G.ForeverDungeonJournalFrame
    if not journal then return end
    journalButton = journalButton or MakeJournalButton(journal)
    if not journalButton then return end
    local show = dungeon and #ns.DungeonQuests(dungeon) > 0
    journalButton.dungeon = show and dungeon or nil
    journalButton:SetShown(show and true or false)
    UI.UpdateJournalButton()
end

function UI.UpdateJournalButton()
    local b = journalButton
    if not (b and b.dungeon) then return end
    local on = ns.Guide.Active() == b.dungeon
    b:SetText(on and "Guiding" or "Guide")
    if on then b:LockHighlight() else b:UnlockHighlight() end
end

local hooked
local function HookJournal()
    local FDJ = ns.FDJ()
    if hooked or not (FDJ and type(FDJ.UpdateQuestTrackButton) == "function") then return end
    hooked = true
    local original = FDJ.UpdateQuestTrackButton
    -- Ours first, so the journal lines Track up right of it.
    FDJ.UpdateQuestTrackButton = function(name, ...)
        pcall(UI.PlaceJournalButton, name)
        return original(name, ...)
    end
end

------------------------------------------------------------------ /dqg

local function FindDungeon(text)
    text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local FDJ = ns.FDJ() or {}
    local hit
    for name in pairs(FDJ.DB or {}) do
        local lower = name:lower()
        if lower == text then return name end
        if lower:find(text, 1, true) then hit = hit or name end
    end
    -- the journal's own short names: "dm", "sfk", "rfc"...
    for name, aliases in pairs(FDJ.DUNGEON_SEARCH_ALIASES or {}) do
        for _, alias in ipairs(type(aliases) == "table" and aliases or {}) do
            if type(alias) == "string" and alias:lower() == text and FDJ.DB and FDJ.DB[name] then return name end
        end
    end
    return hit
end

local function Slash(msg)
    msg = msg or ""
    local cmd = msg:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if cmd == "stop" then
        ns.Guide.Stop()
        ns.Print("stopped.")
    elseif cmd == "tomtom" or cmd == "arrow" then
        local key = cmd == "tomtom" and "tomtom" or "journalArrow"
        ns.DB()[key] = not ns.DB()[key]
        ns.Guide.Repoint()
        ns.Print((key == "tomtom" and "TomTom waypoints " or "Journal arrow ") .. (ns.DB()[key] and "on." or "off."))
        UI.Update()
    elseif cmd == "list" then
        UI.ShowWindow("list")
    elseif cmd == "" then
        UI.ToggleWindow()
    else
        local name = FindDungeon(msg)
        if name then
            ns.Guide.Start(name)
        else
            ns.Print("no dungeon called \"" .. msg .. "\". /dqg shows the list.")
        end
    end
end

------------------------------------------------------------------ the minimap button

local MINIMAP_ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function MinimapTooltip(tip)
    tip:AddLine("Dungeon Quest Guide")
    local dungeon = ns.Guide.Active()
    local last = ns.CharDB().lastActive
    if dungeon then
        tip:AddLine("Guiding: " .. dungeon, 1, 1, 1)
        local current = ns.Guide.current
        if current and current.title then tip:AddLine("Next: " .. current.title, 1, 1, 1, true) end
    else
        tip:AddLine("Off", 0.6, 0.6, 0.6)
    end
    tip:AddLine("Click: show or hide the dungeon list and the guide.", 0.8, 0.8, 0.8, true)
    if dungeon then
        tip:AddLine("Right-click: turn it off (the arrow and the window go away).", 0.8, 0.8, 0.8, true)
    elseif last then
        tip:AddLine("Right-click: turn it back on (" .. last .. ").", 0.8, 0.8, 0.8, true)
    end
end

-- Left: the window. Right: the guide off (arrows, pin and window away), or
-- back on with the dungeon it was on.
function UI.MinimapClick(button)
    if button == "RightButton" then
        local dungeon = ns.Guide.Active()
        if dungeon then
            ns.Guide.Stop()
            ns.Print("off.")
        else
            local last = ns.CharDB().lastActive
            if last then ns.Guide.Start(last) else UI.ShowWindow("list") end
        end
    else
        UI.ToggleWindow()
    end
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

-- The icon goes grey while the guide is off.
local minimapIcon
function UI.UpdateMinimapIcon()
    local tex = minimapIcon
    if not tex then
        local dbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        local button = dbIcon and dbIcon.GetMinimapButton and ns.Try(dbIcon.GetMinimapButton, dbIcon, "DungeonQuestGuide")
        tex = button and button.icon
    end
    if tex and tex.SetDesaturated then tex:SetDesaturated(not ns.Guide.Active()) end
end

local minimapButton
function UI.MakeMinimapButton()
    if minimapButton then return minimapButton end
    local db = ns.DB()
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    db.minimap.hide = false
    local broker = LibStub and LibStub("LibDataBroker-1.1", true)
    local dbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if broker and dbIcon then
        local ok = pcall(function()
            local object = broker:NewDataObject("DungeonQuestGuide", {
                type = "launcher", text = "Dungeon Quest Guide", icon = MINIMAP_ICON,
                OnClick = function(_, button) UI.MinimapClick(button) end,
                OnTooltipShow = MinimapTooltip,
            })
            dbIcon:Register("DungeonQuestGuide", object, db.minimap)
        end)
        if ok then
            minimapButton = "LibDBIcon"
            UI.UpdateMinimapIcon()
            return minimapButton
        end
    end
    if not Minimap then return nil end
    -- A plain round button on the minimap's edge.
    local b = CreateFrame("Button", "DungeonQuestGuideMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture(MINIMAP_ICON)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
    b:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]])
    local radius = ((Minimap.GetWidth and Minimap:GetWidth()) or 140) / 2 + 5
    local a = math.rad(200)
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button) UI.MinimapClick(button) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MinimapTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton, minimapIcon = b, icon
    UI.UpdateMinimapIcon()
    return b
end

function UI.Init()
    UI.MakeMinimapButton()
    HookJournal()
    if ns.Guide.Active() and ns.CharDB().windowShown then
        if C_Timer and C_Timer.After then C_Timer.After(3.5, UI.ShowWindow) else UI.ShowWindow() end
    end
end

SLASH_DUNGEONQUESTGUIDE1 = "/dqg"
SLASH_DUNGEONQUESTGUIDE2 = "/questguide"
SlashCmdList.DUNGEONQUESTGUIDE = Slash

HookJournal() -- the journal is loaded before us
