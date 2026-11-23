-- Dungeon Quest Guide: the running guide. Keeps the plan up to date as
-- quests are picked up and handed in, and points the way to the step the
-- character is on: the Dungeon Journal's own arrow and a TomTom waypoint
-- (with TomTom's arrow), each of which can be switched off.
local ADDON, ns = ...

local Guide = {}
ns.Guide = Guide

function ns.DB()
    DungeonQuestGuideDB = type(DungeonQuestGuideDB) == "table" and DungeonQuestGuideDB or {}
    local db = DungeonQuestGuideDB
    if db.journalArrow == nil then db.journalArrow = true end
    if db.tomtom == nil then db.tomtom = true end
    return db
end

function ns.CharDB()
    DungeonQuestGuideCharDB = type(DungeonQuestGuideCharDB) == "table" and DungeonQuestGuideCharDB or {}
    local db = DungeonQuestGuideCharDB
    db.skip = type(db.skip) == "table" and db.skip or {}
    return db
end

function ns.HasTomTom()
    return type(_G.TomTom) == "table" and type(_G.TomTom.AddWaypoint) == "function"
end

Guide.plan, Guide.current, Guide.focusKey = nil, nil, nil

function Guide.Active()
    return ns.CharDB().active
end

------------------------------------------------------------------ the arrows

local tomtomUID, pointedKey

-- One arrow on screen: while the journal's arrow leads, the TomTom waypoint is
-- a map and minimap pin only, and TomTom's own arrow stays off it.
local function JournalLeads()
    local FDJ = ns.FDJ()
    return ns.DB().journalArrow and FDJ and FDJ.FollowWaypoint and true or false
end

-- TomTom can still move its arrow onto the pin by itself ("set to next
-- closest waypoint"): take it off again. The user's own waypoints are left
-- alone.
local watchingTomTom
local function WatchTomTomArrow()
    if watchingTomTom or not ns.HasTomTom() then return end
    local TomTom = _G.TomTom
    if type(TomTom.RegisterCallback) ~= "function" then return end
    watchingTomTom = true
    local owner = {}
    ns.Try(TomTom.RegisterCallback, owner, "ArrowTargetChanged", function(_, uid)
        if not (uid and uid == tomtomUID and JournalLeads()) then return end
        local function Off()
            -- still ours (a listener may have moved it on meanwhile)
            if uid == tomtomUID and TomTom.ClearCrazyArrowPoint then
                ns.Try(TomTom.ClearCrazyArrowPoint, TomTom, false)
            end
        end
        -- not from inside TomTom's own arrow change
        if C_Timer and C_Timer.After then C_Timer.After(0, Off) else Off() end
    end)
end
Guide.WatchTomTomArrow = WatchTomTomArrow

local function ClearArrows()
    local FDJ = ns.FDJ()
    if FDJ and FDJ.FollowWaypoint then ns.Try(FDJ.FollowWaypoint, ns.SOURCE, nil) end
    if tomtomUID and ns.HasTomTom() then ns.Try(_G.TomTom.RemoveWaypoint, _G.TomTom, tomtomUID) end
    tomtomUID, pointedKey = nil, nil
end
Guide.ClearArrows = ClearArrows

local function PointAt(task)
    local spot = task and task.spot
    local key
    if spot and not ns.InInstance() then
        key = task.key .. "@" .. spot.mapID .. ":" .. spot.x .. ":" .. spot.y
    end
    if key == pointedKey then return end
    ClearArrows()
    if not key then return end
    pointedKey = key
    local db = ns.DB()
    local label = spot.label or task.detail or task.title
    local FDJ = ns.FDJ()
    if db.journalArrow and FDJ and FDJ.FollowWaypoint then
        local copy = {}
        for k, v in pairs(spot) do copy[k] = v end
        copy.label = label
        ns.Try(FDJ.FollowWaypoint, ns.SOURCE, copy, task.questName, task.kind == "turnin", nil,
            task.kind == "objective" or task.kind == "entrance" or task.kind == "item")
    end
    if db.tomtom and ns.HasTomTom() then
        WatchTomTomArrow()
        tomtomUID = ns.Try(_G.TomTom.AddWaypoint, _G.TomTom, spot.mapID, spot.x, spot.y, {
            title = task.title .. (label and label ~= task.title and ("\n" .. label) or ""),
            persistent = false, minimap = true, world = true, crazy = not JournalLeads(), silent = true,
            from = ns.SOURCE,
        })
    end
end

-- Settings changed: point again.
function Guide.Repoint()
    ClearArrows()
    if Guide.current then PointAt(Guide.current) end
end

------------------------------------------------------------------ refresh

local function Skips(dungeon)
    local skip = ns.CharDB().skip
    skip[dungeon] = type(skip[dungeon]) == "table" and skip[dungeon] or {}
    return skip[dungeon]
end

local announced, lastSignature
local function RefreshNow(force)
    local dungeon = Guide.Active()
    local FDJ = ns.FDJ()
    if not dungeon or not (FDJ and FDJ.DB and FDJ.DB[dungeon]) then
        Guide.plan, Guide.current = nil, nil
        ClearArrows()
        if ns.UI then ns.UI.Update() end
        return
    end
    local signature = ns.PlanSignature(dungeon, Skips(dungeon))
    if not force and Guide.plan and Guide.plan.dungeon == dungeon and signature == lastSignature then
        return -- nothing that matters changed
    end
    lastSignature = signature
    local plan = ns.BuildPlan(dungeon, Skips(dungeon))
    Guide.plan = plan
    local current = plan.tasks[1]
    if Guide.focusKey then
        local found
        for _, t in ipairs(plan.tasks) do
            if t.key == Guide.focusKey then found = t break end
        end
        if found then current = found else Guide.focusKey = nil end
    end
    Guide.current = current
    PointAt(current)
    if #plan.tasks == 0 and #plan.have == 0 and #plan.inside == 0 then
        if announced ~= dungeon then
            announced = dungeon
            ns.Print(("Nothing left to pick up for %s right now%s."):format(dungeon,
                #plan.later > 0 and (" (" .. #plan.later .. " for later)") or ""))
        end
    else
        announced = nil
    end
    if ns.UI then ns.UI.Update() end
end

local pending, pendingForce
-- now: at once. force: plan again even if no quest changed (a new zone: the
-- quickest order from here may be another).
function Guide.Refresh(now, force)
    if now then
        pending, pendingForce = nil, nil
        RefreshNow(true)
        return
    end
    pendingForce = pendingForce or force
    if pending then return end
    pending = true
    local after = C_Timer and C_Timer.After
    if not after then pending = nil RefreshNow(pendingForce) pendingForce = nil return end
    after(0.4, function()
        local f = pendingForce
        pending, pendingForce = nil, nil
        RefreshNow(f)
    end)
end

------------------------------------------------------------------ start / stop

function Guide.Start(dungeon)
    local FDJ = ns.FDJ()
    if not (dungeon and FDJ and FDJ.DB and FDJ.DB[dungeon]) then return end
    local char = ns.CharDB()
    char.active = dungeon
    char.lastActive = dungeon -- for the minimap button's right-click (back on)
    char.windowShown = true
    Guide.focusKey = nil
    announced = nil
    if FDJ.ResetWaypointDone then ns.Try(FDJ.ResetWaypointDone, ns.SOURCE) end -- the journal arrow right-clicked away before
    ClearArrows()
    ns.ClearCostCache()
    Guide.Refresh(true)
    if ns.UI then ns.UI.ShowWindow() ns.UI.UpdateJournalButton() end
end

function Guide.Stop()
    local char = ns.CharDB()
    char.active = nil
    char.windowShown = nil
    Guide.plan, Guide.current, Guide.focusKey = nil, nil, nil
    ClearArrows()
    if ns.UI then ns.UI.HideWindow() ns.UI.UpdateJournalButton() ns.UI.UpdateMinimapIcon() end
end

-- Point at another step until it is done (a click on its row). A click on the
-- step already pointed at brings back an arrow right-clicked away or reached.
function Guide.Focus(task)
    Guide.focusKey = task and task.key or nil
    local FDJ = ns.FDJ()
    if FDJ and FDJ.ResetWaypointDone then ns.Try(FDJ.ResetWaypointDone, ns.SOURCE) end
    ClearArrows()
    Guide.Refresh(true)
end

------------------------------------------------------------------ is there an arrow?

-- The journal's own key for a followed spot (Systems/MapMarkers.lua), to tell
-- "hidden by a right-click or on arrival" from anything else.
local function JournalKey(task)
    local spot = task.spot
    return string.format("%s|%.4f|%.4f", tostring(spot.mapID), tonumber(spot.x) or 0, tonumber(spot.y) or 0)
        .. (task.kind == "turnin" and "|in" or "|up") .. (spot.useItem and "|use" or "")
end

-- Why no arrow points at the step the guide is on; nil when one does (or when
-- that's as it should be). For the window, so nobody is left wondering.
function Guide.ArrowStatus()
    local task = Guide.current
    if not (Guide.Active() and task) then return nil end
    if ns.InInstance() then return nil end -- the window says "When you're out again"
    if not task.spot then return "This step has no map spot, so no arrow: its description says where to go." end
    local db, FDJ = ns.DB(), ns.FDJ()
    local tomtomLeads = db.tomtom and ns.HasTomTom()
    local journalHas = FDJ and type(FDJ.FollowWaypoint) == "function"
    if not (db.journalArrow and journalHas) then
        if tomtomLeads then return nil end -- TomTom's arrow leads
        if not journalHas then
            return "No arrow: your Dungeon Journal has none (an old version?). Update it, or install TomTom."
        end
        return "No arrow: \"Journal arrow\" is unticked below."
    end
    if type(FDJ.WaypointArrowTarget) ~= "function" then return nil end -- can't tell
    local _, source = ns.Try(FDJ.WaypointArrowTarget)
    if source == ns.SOURCE or source == "corpse" then return nil end
    if source == "manual" then
        return "The journal's arrow is on a spot you showed on its map. Right-click that arrow to get the guide's back."
    end
    if source ~= nil then
        return "The journal's arrow is following a quest chain you track in the journal. Right-click that arrow, or untrack the chain, to get the guide's back."
    end
    local char = _G.ForeverDungeonJournalCharacterDB
    local done = type(char) == "table" and type(char.arrowDone) == "table" and char.arrowDone[ns.SOURCE]
    if done == JournalKey(task) then
        return "The arrow was hidden (right-clicked, or you got there). Click the step to bring it back."
    end
    return "The journal's arrow isn't showing. Click the step to try again."
end

function Guide.ToggleSkip(questID)
    local dungeon = Guide.Active()
    if not (dungeon and questID) then return end
    local skip = Skips(dungeon)
    skip[questID] = not skip[questID] or nil
    Guide.Refresh(true)
end

------------------------------------------------------------------ events

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.DB()
        ns.CharDB()
        if ns.UI then ns.UI.Init() end
    end
    if not Guide.Active() then return end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- the journal finishes its own data at login; the arrow after it
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() Guide.Refresh(true) end)
        end
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" then ns.ClearCostCache() end
    Guide.Refresh(false, event == "ZONE_CHANGED_NEW_AREA")
    if event == "QUEST_TURNED_IN" and C_Timer and C_Timer.After then
        -- the game marks a quest done a moment after the hand-in
        C_Timer.After(1.5, function() Guide.Refresh() end)
    end
end)
