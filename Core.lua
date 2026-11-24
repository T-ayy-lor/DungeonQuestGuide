-- Dungeon Quest Guide: shared helpers.
-- Everything about the dungeons (their quests, quest chains, where the quest
-- givers stand, the entrances) comes from ForeverDungeonJournal's data. This
-- addon only reads it. Where the journal has no map spot for a quest giver,
-- QuestieDB's NPC spawns fill in.
local ADDON, ns = ...

ns.SOURCE = "DungeonQuestGuide" -- the journal arrow's source key, and TomTom's "from"

function ns.FDJ()
    return _G.ForeverDungeonJournal_NS
end

-- A game or journal call that may be missing or may fail: nil instead.
function ns.Try(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(f, ...)
    if ok then return a, b, c, d end
    return nil
end

function ns.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDungeon Quest Guide:|r " .. tostring(msg))
    end
end

------------------------------------------------------------------ the character

function ns.PlayerFaction()
    local f = ns.Try(UnitFactionGroup, "player")
    if f == "Alliance" or f == "Horde" then return f end
    return nil
end

function ns.PlayerLevel()
    return tonumber(ns.Try(UnitLevel, "player")) or 1
end

function ns.InInstance()
    local inside, kind = ns.Try(IsInInstance)
    return inside == true and (kind == "party" or kind == "raid")
end

function ns.ItemCount(itemID)
    if type(itemID) ~= "number" then return 0 end
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return tonumber(ns.Try(count, itemID)) or 0
end

------------------------------------------------------------------ quest state

function ns.TurnedIn(id)
    if not id then return false end
    local FDJ = ns.FDJ()
    if FDJ and FDJ.QuestTurnedIn then return ns.Try(FDJ.QuestTurnedIn, id) == true end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return ns.Try(C_QuestLog.IsQuestFlaggedCompleted, id) == true
    end
    return ns.Try(IsQuestFlaggedCompleted, id) == true
end

function ns.InLog(id)
    if not id then return false end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local index = ns.Try(C_QuestLog.GetLogIndexForQuestID, id)
        if index and index > 0 then return true end
    end
    if GetQuestLogIndexByID then
        local index = ns.Try(GetQuestLogIndexByID, id)
        if index and index > 0 then return true end
    end
    return false
end

-- In the log with every objective done (ready to hand in).
function ns.Complete(id)
    if not ns.InLog(id) then return false end
    if C_QuestLog and C_QuestLog.IsComplete then
        return ns.Try(C_QuestLog.IsComplete, id) == true
    end
    return ns.Try(IsQuestComplete, id) == true
end

------------------------------------------------------------------ names and places

-- "Rahauro, Elder Rise, Thunder Bluff" -> "rahauro" (as the journal reads it)
function ns.NpcName(text)
    if type(text) ~= "string" then return nil end
    local name = text:match("^([^,(]+)")
    name = name and name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if not name or name == "" then return nil end
    return name
end

local function NpcOf(loc)
    if type(loc) ~= "table" or not loc.mapID then return nil end
    local name = loc.targetName
    if type(name) ~= "string" or name == "" then
        local label = loc.label
        if type(label) ~= "string" then return nil end
        name = label:match("^(.-)%s+\226\128\148") or label:match("^([^,]+)") or label
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name:lower() or nil
end

-- Every NPC the journal has a map spot for, by name (built once).
local npcSpots
function ns.NpcSpot(name)
    if type(name) ~= "string" then return nil end
    if not npcSpots then
        npcSpots = {}
        local FDJ = ns.FDJ() or {}
        local function Add(loc)
            local npc = NpcOf(loc)
            if npc and not npcSpots[npc] then npcSpots[npc] = loc end
        end
        for _, loc in ipairs(FDJ.TURNIN_SPOTS or {}) do Add(loc) end
        for _, loc in pairs(FDJ.QUEST_START_MAPS or {}) do Add(loc) end
        for _, details in pairs(FDJ.QUEST_PREREQ_DETAILS or {}) do
            if type(details) == "table" then Add(details.map); Add(details.turninMap) end
        end
    end
    if npcSpots[name] then return npcSpots[name] end
    -- With or without a title in front ("Hamuul Runetotem" / "Arch Druid
    -- Hamuul Runetotem"), only when exactly one NPC fits.
    local hit, count = nil, 0
    for key, loc in pairs(npcSpots) do
        if (#key > #name and key:sub(-(#name + 1)) == " " .. name)
            or (#name > #key and name:sub(-(#key + 1)) == " " .. key) then
            hit, count = loc, count + 1
        end
    end
    return count == 1 and hit or nil
end

function ns.ValidSpot(spot)
    return type(spot) == "table" and tonumber(spot.mapID) ~= nil
        and tonumber(spot.x) ~= nil and tonumber(spot.y) ~= nil
        and spot.x > 0 and spot.y > 0 and spot.x < 1 and spot.y < 1
end

------------------------------------------------------------------ QuestieDB fallback

-- QuestieDB keeps its area -> map tables as Lua source ("return {...}") until
-- something compiles them; a table if Questie already has.
local zoneTables = {}
local function ZoneTable(private, field)
    local t = zoneTables[field]
    if t ~= nil then return t or nil end
    local value = private[field]
    if type(value) == "string" then
        local compile = _G.loadstring or load
        local chunk = compile and compile(value)
        local ok, result = false, nil
        if chunk then ok, result = pcall(chunk) end
        value = ok and result or nil
    end
    zoneTables[field] = type(value) == "table" and value or false
    return zoneTables[field] or nil
end

local function QuestieZoneMap(areaID)
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and ns.Try(lib.Support.Get, "ZoneDB")
    local private = type(support) == "table" and type(support.private) == "table" and support.private
    if not private then return nil end
    -- the overrides first: 0 there means "no map" (the Deeprun Tram)
    local override = ZoneTable(private, "areaIdToUiMapIdOverride")
    local map = override and override[areaID]
    if map == nil then
        local main = ZoneTable(private, "areaIdToUiMapId")
        map = main and main[areaID]
    end
    map = tonumber(map)
    return map and map > 0 and map or nil
end

-- The first spawn of an NPC or object in QuestieDB, as a journal-style spot.
local function QuestieSpawn(kind, id)
    local lib = _G.LibQuestieDB
    local entity = lib and lib[kind]
    if not (entity and entity.Get) then return nil end
    local spawns = ns.Try(entity.Get, id, "spawns")
    local name = ns.Try(entity.Get, id, "name")
    if type(spawns) ~= "table" then return nil end
    for areaID, list in pairs(spawns) do
        local first = type(list) == "table" and list[1]
        local mapID = QuestieZoneMap(areaID)
        if mapID and type(first) == "table" and tonumber(first[1]) and tonumber(first[2]) then
            local spot = { mapID = mapID, x = first[1] / 100, y = first[2] / 100,
                label = type(name) == "string" and name or nil, targetName = type(name) == "string" and name or nil,
                fromQuestie = true }
            if ns.ValidSpot(spot) then return spot end
        end
    end
    return nil
end

-- field: "startedBy" or "finishedBy" -> { {npcIDs}, {objectIDs}, {itemIDs} }
function ns.QuestieSpot(questID, field)
    local lib = _G.LibQuestieDB
    if not (lib and lib.Quest and lib.Quest.Get and questID) then return nil end
    local by = ns.Try(lib.Quest.Get, questID, field)
    if type(by) ~= "table" then return nil end
    for _, npcID in ipairs(type(by[1]) == "table" and by[1] or {}) do
        local spot = QuestieSpawn("Npc", npcID)
        if spot then return spot end
    end
    for _, objectID in ipairs(type(by[2]) == "table" and by[2] or {}) do
        local spot = QuestieSpawn("Object", objectID)
        if spot then return spot end
    end
    return nil
end

------------------------------------------------------------------ quest areas (QuestieDB)

-- Every spawn of an NPC or object, as {mapID, x, y, name} (0-1 map units).
local function AllSpawns(kind, id, out, cap)
    local lib = _G.LibQuestieDB
    local entity = lib and lib[kind]
    if not (entity and entity.Get) then return end
    local spawns = ns.Try(entity.Get, id, "spawns")
    if type(spawns) ~= "table" then return end
    local name = ns.Try(entity.Get, id, "name")
    for areaID, list in pairs(spawns) do
        local mapID = QuestieZoneMap(areaID)
        if mapID and type(list) == "table" then
            for _, p in ipairs(list) do
                if #out >= cap then return end
                local x, y = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
                if x and y and x > 0 and y > 0 and x < 100 and y < 100 then
                    out[#out + 1] = { mapID, x / 100, y / 100, type(name) == "string" and name or nil }
                end
            end
        end
    end
end

-- A spawn list straight from the quest ({[areaID] = {{x, y}, ...}}).
local function ListSpawns(spawns, name, out, cap)
    if type(spawns) ~= "table" then return end
    for areaID, list in pairs(spawns) do
        local mapID = QuestieZoneMap(areaID)
        if mapID and type(list) == "table" then
            for _, p in ipairs(list) do
                if #out >= cap then return end
                local x, y = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
                if x and y and x > 0 and y > 0 and x < 100 and y < 100 then
                    out[#out + 1] = { mapID, x / 100, y / 100, name }
                end
            end
        end
    end
end

-- Instance and micro maps (a cave's own map) don't take an arrow: the zone's do.
local function OutdoorMap(mapID)
    if not (C_Map and C_Map.GetMapInfo) then return true end
    local info = ns.Try(C_Map.GetMapInfo, mapID)
    if type(info) ~= "table" or not info.mapType then return true end
    return info.mapType ~= 4 -- Enum.UIMapType.Dungeon
end

-- Where a quest's objectives are done (the mobs to kill, the things to use,
-- where its items drop, the place to explore): the thickest cluster of their
-- spawns, as a journal-style spot. nil when QuestieDB has none.
local CAP, RADIUS = 600, 0.06
local areaCache, areaPoints = {}, {}
function ns.QuestieAreaSpot(questID)
    if not questID then return nil end
    if areaCache[questID] ~= nil then return areaCache[questID] or nil end
    local lib = _G.LibQuestieDB
    local Quest = lib and lib.Quest
    if not (Quest and Quest.Get) then return nil end -- not cached: QuestieDB may come later
    local points = {}
    local trigger = ns.Try(Quest.Get, questID, "triggerEnd")
    if type(trigger) == "table" then ListSpawns(trigger[2], type(trigger[1]) == "string" and trigger[1] or nil, points, CAP) end
    local objectives = ns.Try(Quest.Get, questID, "objectives")
    local source = ns.Try(Quest.Get, questID, "sourceItemId")
    if type(objectives) == "table" then
        for _, row in ipairs(type(objectives[1]) == "table" and objectives[1] or {}) do
            if type(row) == "table" and tonumber(row[1]) then AllSpawns("Npc", row[1], points, CAP) end
        end
        for _, row in ipairs(type(objectives[5]) == "table" and objectives[5] or {}) do
            if type(row) == "table" then
                if tonumber(row[2]) then AllSpawns("Npc", row[2], points, CAP) end
                for _, id in ipairs(type(row[1]) == "table" and row[1] or {}) do AllSpawns("Npc", id, points, CAP) end
            end
        end
        for _, row in ipairs(type(objectives[2]) == "table" and objectives[2] or {}) do
            if type(row) == "table" and tonumber(row[1]) then AllSpawns("Object", row[1], points, CAP) end
        end
        local Item = lib.Item
        for _, row in ipairs(type(objectives[3]) == "table" and objectives[3] or {}) do
            local itemID = type(row) == "table" and tonumber(row[1])
            -- the item the quest hands you (a letter to deliver) is no objective
            if itemID and itemID ~= source and Item and Item.Get then
                local npcs = ns.Try(Item.Get, itemID, "npcDrops")
                for i, id in ipairs(type(npcs) == "table" and npcs or {}) do
                    if i > 25 then break end
                    AllSpawns("Npc", id, points, CAP)
                end
                local objects = ns.Try(Item.Get, itemID, "objectDrops")
                for i, id in ipairs(type(objects) == "table" and objects or {}) do
                    if i > 25 then break end
                    AllSpawns("Object", id, points, CAP)
                end
            end
        end
    end
    local extra = ns.Try(Quest.Get, questID, "extraObjectives")
    for _, row in ipairs(type(extra) == "table" and extra or {}) do
        if type(row) == "table" then ListSpawns(row[1], type(row[3]) == "string" and row[3] or nil, points, CAP) end
    end

    -- The map with the most spawns (an outdoor one if there is any), then
    -- the spawn with the most others close by; the area is their middle.
    local byMap, outdoor = {}, {}
    for _, p in ipairs(points) do
        local list = byMap[p[1]]
        if not list then
            list = {}
            byMap[p[1]] = list
            outdoor[p[1]] = OutdoorMap(p[1])
        end
        list[#list + 1] = p
    end
    local best
    for mapID, list in pairs(byMap) do
        local b = best and byMap[best]
        if not best or (outdoor[mapID] and not outdoor[best])
            or (outdoor[mapID] == outdoor[best] and (#list > #b or (#list == #b and mapID < best))) then
            best = mapID
        end
    end
    local list = best and byMap[best]
    if not list then
        areaCache[questID] = false
        return nil
    end
    areaPoints[questID] = list
    local r2 = RADIUS * RADIUS
    local center, near
    for _, p in ipairs(list) do
        local count = 0
        for _, o in ipairs(list) do
            local dx, dy = p[2] - o[2], p[3] - o[3]
            if dx * dx + dy * dy <= r2 then count = count + 1 end
        end
        if not near or count > near then center, near = p, count end
    end
    local sx, sy, n, names, seen = 0, 0, 0, {}, {}
    for _, o in ipairs(list) do
        local dx, dy = center[2] - o[2], center[3] - o[3]
        if dx * dx + dy * dy <= r2 then
            sx, sy, n = sx + o[2], sy + o[3], n + 1
            if o[4] and not seen[o[4]] and #names < 3 then seen[o[4]] = true names[#names + 1] = o[4] end
        end
    end
    local spot = { mapID = best, x = sx / n, y = sy / n, fromQuestie = true, area = true, markerType = "location",
        label = "Quest area" .. (#names > 0 and (": " .. table.concat(names, ", ")) or "") }
    if not ns.ValidSpot(spot) then spot = nil end
    areaCache[questID] = spot or false
    return spot
end

-- Every spawn on the quest area's map ({ mapID, x, y, name }), nil when
-- QuestieDB has none.
function ns.QuestieAreaPoints(questID)
    if not ns.QuestieAreaSpot(questID) then return nil end
    return areaPoints[questID]
end

------------------------------------------------------------------ distance

local function WorldPos(spot)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local continent, pos = ns.Try(C_Map.GetWorldPosFromMapPos, spot.mapID, CreateVector2D(spot.x, spot.y))
    if not continent or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
    return continent, x, y
end

-- Where the character stands, as a spot (nil inside instances and the like).
function ns.PlayerSpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local map = ns.Try(C_Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local pos = ns.Try(C_Map.GetPlayerMapPosition, map, "player")
    if type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
    local spot = { mapID = map, x = x, y = y }
    return ns.ValidSpot(spot) and spot or nil
end

-- Yards in a straight line between two spots on one continent (from = nil:
-- from the character); nil when it can't be told.
function ns.Yards(from, to)
    from = from or ns.PlayerSpot()
    if not (from and to) then return nil end
    local c1, x1, y1 = WorldPos(from)
    local c2, x2, y2 = WorldPos(to)
    if not (c1 and c2 and c1 == c2 and x1 and x2 and y1 and y2) then return nil end
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- Yards from the character to the nearest of these points ({ mapID, x, y }),
-- nil when it can't be told. Their world positions are kept on them.
function ns.NearestYards(points)
    local me = ns.PlayerSpot()
    local c, px, py
    if me then c, px, py = WorldPos(me) end
    if not (c and px and py) then return nil end
    local best
    for _, p in ipairs(points) do
        if p.wc == nil then
            local wc, wx, wy = WorldPos({ mapID = p[1], x = p[2], y = p[3] })
            p.wc, p.wx, p.wy = (wc and wx and wy) and wc or false, wx, wy
        end
        if p.wc == c then
            local dx, dy = p.wx - px, p.wy - py
            local d = math.sqrt(dx * dx + dy * dy)
            if not best or d < best then best = d end
        end
    end
    return best
end

local FAR = 1e7
ns.FAR = FAR
-- Yards from one spot to another (from = nil: from the character). The
-- journal's way finder first (flight paths, boats, the hearthstone), else
-- the straight line, else "far".
function ns.Cost(from, to)
    local FDJ = ns.FDJ()
    if FDJ and FDJ.WayCost then
        local cost = ns.Try(FDJ.WayCost, from, to)
        if type(cost) == "number" then return cost end
    end
    from = from or ns.PlayerSpot()
    if not from then return FAR end
    if from.mapID == to.mapID then
        -- same map: map units are good enough to compare
        local dx, dy = from.x - to.x, from.y - to.y
        return math.sqrt(dx * dx + dy * dy) * 1000
    end
    local c1, x1, y1 = WorldPos(from)
    local c2, x2, y2 = WorldPos(to)
    if c1 and c2 and c1 == c2 and x1 and x2 then
        local dx, dy = x1 - x2, y1 - y2
        return math.sqrt(dx * dx + dy * dy)
    end
    return FAR
end
