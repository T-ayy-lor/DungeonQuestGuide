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

-- The journal's own key for a followed spot (Systems/MapMarkers.lua), to tell
-- "hidden by a right-click or on arrival" from anything else.
local function JournalKey(spot, kind)
    return string.format("%s|%.4f|%.4f", tostring(spot.mapID), tonumber(spot.x) or 0, tonumber(spot.y) or 0)
        .. (kind == "turnin" and "|in" or "|up") .. (spot.useItem and "|use" or "")
end
local followed -- the journal's key for what it was last handed
local aimFrom -- where the character stood when a point ahead on the way was handed over
local function HiddenInJournal()
    local char = _G.ForeverDungeonJournalCharacterDB
    local done = type(char) == "table" and type(char.arrowDone) == "table" and char.arrowDone[ns.SOURCE]
    return done ~= nil and done == followed
end

-- TomTom can still move its arrow onto the pin by itself ("set to next
-- closest waypoint"): take it off again. The user's own waypoints are left
-- alone. Also noted: whether TomTom's arrow is on its corpse waypoint.
Guide.tomtomOnCorpse = false
local watchingTomTom
local function WatchTomTomArrow()
    if watchingTomTom or not ns.HasTomTom() then return end
    local TomTom = _G.TomTom
    if type(TomTom.RegisterCallback) ~= "function" then return end
    watchingTomTom = true
    local owner = {}
    ns.Try(TomTom.RegisterCallback, owner, "ArrowTargetChanged", function(_, uid)
        local onCorpse = type(uid) == "table" and uid.corpse == true
        if onCorpse ~= Guide.tomtomOnCorpse then
            Guide.tomtomOnCorpse = onCorpse
            -- not from inside TomTom's own arrow change
            if C_Timer and C_Timer.After then C_Timer.After(0, function() Guide.CheckArrow() end) end
        end
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

-- Dead, with TomTom's arrow on its corpse waypoint ("Automatically set a
-- waypoint when I die", on unless unticked): the guide's arrow and pin go
-- until alive again. Only once that arrow is really there: dead in a
-- dungeon, TomTom finds no corpse on the map outside and sets none, and
-- Feign Death sets none either; the guide's arrow then stays (the journal
-- turns it into "Your corpse").
-- Left up, the journal's arrow on the guide's step turned into its own
-- "Your corpse" arrow right under TomTom's (the user, 2026-11-23: "the tom
-- tom corpse waypoint should take prio ... just turn dungeon quest off while
-- dead and then back on on revive"). Without TomTom's corpse arrow the
-- guide's stays: the journal's "Your corpse" is then the only way back.
local function TomTomCorpseArrow()
    if not (ns.HasTomTom() and Guide.tomtomOnCorpse) then return false end
    local db = _G.TomTom.db
    local profile = type(db) == "table" and type(db.profile) == "table" and db.profile or {}
    local general, arrow = profile.general, profile.arrow
    if type(general) == "table" and general.corpse_arrow == false then return false end
    if type(arrow) == "table" and arrow.enable == false then return false end -- (no arrow drawn)
    return true -- (TomTom's defaults: both on)
end
local function Dead()
    if type(UnitIsDeadOrGhost) ~= "function" then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    if not ok or (type(issecretvalue) == "function" and issecretvalue(dead)) then return false end
    return dead == true
end
Guide.deadOff = false
local function DeadOff() return Dead() and TomTomCorpseArrow() end
Guide.WatchTomTomArrow = WatchTomTomArrow

local function ClearArrows()
    local FDJ = ns.FDJ()
    if FDJ and FDJ.FollowWaypoint then ns.Try(FDJ.FollowWaypoint, ns.SOURCE, nil) end
    if tomtomUID and ns.HasTomTom() then ns.Try(_G.TomTom.RemoveWaypoint, _G.TomTom, tomtomUID) end
    tomtomUID, pointedKey, followed, aimFrom = nil, nil, nil, nil
end
Guide.ClearArrows = ClearArrows

-- The journal's arrow goes straight to the step, never along its roads (the
-- user, 480 yards from a hand-in with the arrow 751 yards round by the road:
-- "i dont want it to direct to road. direct to quest turn in"). A spot the
-- journal is told is swum to (its "swim" flag, Way.SwimStraight) is the one
-- way to have that: it then walks the straight line whenever the character
-- is in the spot's zone and within 1,000 yards. From farther off in the same
-- zone (up to STRAIGHT_FAR) the journal is handed a point on the straight
-- line STEP yards ahead instead, moved on every MOVE yards walked: under 500
-- yards the journal weighs no flight (the user, 1,170 yards from Menethil
-- Harbor in the Wetlands, sent to fly from Ironforge: "definitely faster to
-- just walk"). Its arrow then says the yards to that point; the step's real
-- distance is in the window. From another zone, or farther, the journal still
-- finds the way (roads, flights, boats).
-- Not in the three Stranglethorn ruins the journal knows wall by wall
-- (FDJ.WALKGRIDS, world yards on continent 0): a straight line there runs
-- into walls, and the journal's own way round them is only taken without the
-- swim flag.
Guide.SWIM_NEAR, Guide.STRAIGHT_FAR, Guide.STEP, Guide.MOVE = 950, 2500, 450, 100
local WALLED = {
    { -11812.5, 500.0, 87, 96 },     -- Ruins of Zul'Kunda
    { -12141.6667, 187.5, 74, 75 },  -- Bal'lal Ruins
    { -12445.8333, 241.6667, 214, 168 }, -- Vile Reef coast
}
local CELL = 4.166667
local function Walled(spot)
    local c, x, y = ns.WorldPos(spot)
    if c ~= 0 or not (x and y) then return false end
    for _, g in ipairs(WALLED) do
        if x >= g[1] and x < g[1] + CELL * g[3] and y >= g[2] and y < g[2] + CELL * g[4] then return true end
    end
    return false
end
ns.Walled = Walled

-- Where to point the journal for this spot: the spot itself (swim: straight
-- there), or a point on the straight line ahead (and where the character
-- stood when it was worked out).
local function JournalAim(spot)
    if Walled(spot) then return spot, false end
    local me = ns.PlayerSpot()
    if not (me and me.mapID == spot.mapID) then return spot, true end
    local yards = ns.Yards(me, spot)
    if not yards or yards <= Guide.SWIM_NEAR or yards > Guide.STRAIGHT_FAR then return spot, true end
    local t = Guide.STEP / yards
    return { x = me.x + (spot.x - me.x) * t, y = me.y + (spot.y - me.y) * t }, true, me
end

-- In the quest area of a "Do:" step (within IN yards of any of its mobs,
-- objects or drop spots), no arrow: the area's spot is only the middle of
-- its thickest cluster, which pointed 600 yards off with the gnolls all
-- round. Out again past OUT yards from all of them, the arrow is back. A
-- click on the step brings it back there too (Guide.Focus). Not while on a
-- flight: flying over the area is no reason to lose the arrow.
Guide.AREA_IN, Guide.AREA_OUT = 200, 300
Guide.inArea = false
local arrowWanted -- the step a click asked an arrow for, quest area or not
local function OnTaxi()
    if type(UnitOnTaxi) ~= "function" then return false end
    local ok, on = pcall(UnitOnTaxi, "player")
    return ok and on == true
end
local function InArea(task)
    if not (task and task.kind == "objective" and task.spot) or ns.InInstance() then return false end
    if arrowWanted == task.key then return false end
    if OnTaxi() then return Guide.inArea end -- (as it was until landed)
    local points = task.spot.area and ns.QuestieAreaPoints(task.questID)
    local yards
    if points then yards = ns.NearestYards(points) else yards = ns.Yards(nil, task.spot) end
    if not yards then return false end
    return yards <= (Guide.inArea and Guide.AREA_OUT or Guide.AREA_IN)
end

-- Hand the journal the step (or the point ahead on the way to it).
local function Follow(task)
    local FDJ = ns.FDJ()
    if not (ns.DB().journalArrow and FDJ and FDJ.FollowWaypoint) then
        followed, aimFrom = nil, nil
        return
    end
    local spot = task.spot
    local aim, swim, from = JournalAim(spot)
    local copy = {}
    for k, v in pairs(spot) do copy[k] = v end
    copy.label = spot.label or task.detail or task.title
    copy.x, copy.y = aim.x, aim.y
    copy.swim = swim or nil -- straight there (see above)
    followed, aimFrom = JournalKey(copy, task.kind), from
    ns.Try(FDJ.FollowWaypoint, ns.SOURCE, copy, task.questName, task.kind == "turnin", nil,
        task.kind == "objective" or task.kind == "entrance" or task.kind == "item")
end

-- Walked on: a point ahead moves on with the character, and the spot itself
-- is handed over once within reach (or a point ahead once out of it). An
-- arrow right-clicked away stays away.
local function FollowOn(task)
    if not followed or HiddenInJournal() then return end
    local aim, _, from = JournalAim(task.spot)
    if aimFrom and from then
        local moved = ns.Yards(aimFrom, from)
        if moved and moved < Guide.MOVE then return end
    elseif not aimFrom and not from then
        return
    end
    Follow(task)
end

local function PointAt(task)
    local spot = task and task.spot
    local key
    Guide.inArea = InArea(task)
    Guide.deadOff = DeadOff()
    if spot and not ns.InInstance() and not Guide.inArea and not Guide.deadOff then
        key = task.key .. "@" .. spot.mapID .. ":" .. spot.x .. ":" .. spot.y
    end
    if key == pointedKey then
        if key then FollowOn(task) end
        return
    end
    ClearArrows()
    if not key then return end
    pointedKey = key
    local db = ns.DB()
    local label = spot.label or task.detail or task.title
    Follow(task)
    if db.tomtom and ns.HasTomTom() then
        WatchTomTomArrow()
        local TomTom = _G.TomTom
        local opts = {
            title = task.title .. (label and label ~= task.title and ("\n" .. label) or ""),
            persistent = false, minimap = true, world = true, crazy = not JournalLeads(), silent = true,
            from = ns.SOURCE,
        }
        -- TomTom's own callbacks, but no tooltip on the minimap pin: a far
        -- pin sits on the minimap's edge, and its tooltip popped up whenever
        -- the mouse crossed it. The world map pin keeps its tooltip.
        local callbacks = TomTom.DefaultCallbacks and ns.Try(TomTom.DefaultCallbacks, TomTom, opts)
        if type(callbacks) == "table" and type(callbacks.minimap) == "table" then
            callbacks.minimap.tooltip_show, callbacks.minimap.tooltip_update = nil, nil
            opts.callbacks = callbacks
        end
        tomtomUID = ns.Try(TomTom.AddWaypoint, TomTom, spot.mapID, spot.x, spot.y, opts)
    end
end

-- Once a second: coming into a quest area (or leaving it) takes the arrow
-- away (or brings it back), and a point ahead on the way moves on. The
-- journal remembers a hidden arrow by its spot, so this never brings one back.
function Guide.CheckArrow()
    local task = Guide.current
    if not (Guide.Active() and task and task.spot) or ns.InInstance() then return end
    if InArea(task) ~= Guide.inArea or DeadOff() ~= Guide.deadOff then
        PointAt(task)
        if ns.UI then ns.UI.Update() end
    elseif pointedKey then
        FollowOn(task)
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
            -- a row of several steps at one person: any of them
            for _, s in ipairs(t.group or { t }) do
                if s.key == Guide.focusKey then found = t break end
            end
            if found then break end
        end
        if found then current = found else Guide.focusKey = nil end
    end
    Guide.current = current
    PointAt(current)
    if #plan.tasks == 0 and #plan.have == 0 and #plan.inside == 0 then
        if announced ~= dungeon then
            announced = dungeon
            local waiting = #plan.later + #(plan.after or {})
            ns.Print(("Nothing left to pick up for %s right now%s."):format(dungeon,
                waiting > 0 and (" (" .. waiting .. " for later)") or ""))
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
    arrowWanted = nil
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
    arrowWanted, Guide.inArea = nil, false
    char.windowShown = nil
    Guide.plan, Guide.current, Guide.focusKey = nil, nil, nil
    ClearArrows()
    if ns.UI then ns.UI.HideWindow() ns.UI.UpdateJournalButton() ns.UI.UpdateMinimapIcon() end
end

-- Point at another step until it is done (a click on its row). A click on the
-- step already pointed at brings back an arrow right-clicked away or reached.
function Guide.Focus(task)
    Guide.focusKey = task and task.key or nil
    arrowWanted = task and task.key or nil
    local FDJ = ns.FDJ()
    if FDJ and FDJ.ResetWaypointDone then ns.Try(FDJ.ResetWaypointDone, ns.SOURCE) end
    ClearArrows()
    Guide.Refresh(true)
end

------------------------------------------------------------------ is there an arrow?

-- Why no arrow points at the step the guide is on; nil when one does (or when
-- that's as it should be). For the window, so nobody is left wondering.
function Guide.ArrowStatus()
    local task = Guide.current
    if not (Guide.Active() and task) then return nil end
    if ns.InInstance() then return nil end -- the window says "When you're out again"
    if not task.spot then return "This step has no map spot, so no arrow: its description says where to go." end
    if Guide.deadOff then return "You're dead: TomTom's arrow leads to your corpse. The guide's arrow is back once you're alive." end
    if Guide.inArea then return "You're in the quest area, so no arrow. Click the step if you want one." end
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
    if source == ns.SOURCE and aimFrom then
        return "The arrow leads straight there by a point a little ahead that moves on as you walk, so its yards count only to that point."
    end
    if source == ns.SOURCE or source == "corpse" then return nil end
    if source == "manual" then
        return "The journal's arrow is on a spot you showed on its map. Right-click that arrow to get the guide's back."
    end
    if source ~= nil then
        return "The journal's arrow is following a quest chain you track in the journal. Right-click that arrow, or untrack the chain, to get the guide's back."
    end
    if HiddenInJournal() then
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
Guide.eventFrame = events
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED",
    "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
    pcall(events.RegisterEvent, events, event)
end
local wait = 1
events:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = 1
    Guide.CheckArrow()
end)
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.DB()
        WatchTomTomArrow() -- (whether TomTom's arrow is on the corpse)
        -- Off at every login and /reload: no arrow, pin or window until it's
        -- turned on (a dungeon picked, or a right-click on the minimap button
        -- to go on with the last one).
        local char = ns.CharDB()
        if char.active then char.lastActive = char.active end
        char.active, char.windowShown = nil, nil
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
    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        Guide.CheckArrow() -- dead: TomTom's corpse arrow leads; alive: the guide's is back
        return
    end
    if event == "ZONE_CHANGED_NEW_AREA" then ns.ClearCostCache() end
    Guide.Refresh(false, event == "ZONE_CHANGED_NEW_AREA")
    if event == "QUEST_TURNED_IN" and C_Timer and C_Timer.After then
        -- the game marks a quest done a moment after the hand-in
        C_Timer.After(1.5, function() Guide.Refresh() end)
    end
end)
