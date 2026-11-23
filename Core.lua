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

local function QuestieZoneMap(areaID)
    local lib = _G.LibQuestieDB
    local support = lib and lib.Support and ns.Try(lib.Support.Get, "ZoneDB")
    local map = support and support.private and support.private.areaIdToUiMapId
    return type(map) == "table" and map[areaID] or nil
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
