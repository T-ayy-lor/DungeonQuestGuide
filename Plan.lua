-- Dungeon Quest Guide: the plan. For one dungeon, works out every step the
-- character still has to take to pick up all of its quests (each quest
-- chain's steps first: pick up, do, hand in), puts them in the quickest
-- order from where the character stands, then the dungeon's entrance.
-- Quests already finished and ready to hand in are handed in on the way.
-- No UI here, so it can be tested outside the game.
local ADDON, ns = ...

ns.ICONS = {
    pickup = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    objective = "Interface\\GossipFrame\\IncompleteQuestIcon",
    item = "Interface\\Icons\\INV_Misc_Bag_10",
    useitem = "Interface\\Icons\\INV_Misc_Note_01",
    entrance = "Interface\\Icons\\INV_Misc_Map_01",
}

local function Details(id)
    local FDJ = ns.FDJ() or {}
    local d = FDJ.QUEST_PREREQ_DETAILS and FDJ.QUEST_PREREQ_DETAILS[id]
    return type(d) == "table" and d or {}
end

local function Lower(text) return type(text) == "string" and text:lower() or "" end

-- "Ghostly Attendant, inside Hall of Thanes", "inside the dungeon"
local function SaysInside(text)
    local t = Lower(text)
    return t:find("inside", 1, true) ~= nil or t:find("in the dungeon", 1, true) ~= nil
end

-- The item that starts a quest drops inside (said so, or one of the
-- dungeon's own bosses drops it: "Looted from Edwin VanCleef").
local function DropsInside(q, data)
    local item = q.startItem
    local text = (type(item) == "table" and tostring(item[4] or "") or "") .. " " .. tostring(q.pickup or "")
    if SaysInside(text) then return true end
    local lower = text:lower()
    for _, boss in ipairs(type(data.bosses) == "table" and data.bosses or {}) do
        local name = type(boss) == "table" and boss.name
        if type(name) == "string" and #name > 3 and name ~= "Trash Drops" and lower:find(name:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- A quest this character can ever do (faction, class, profession, race, not
-- a hidden follow-up or a repeatable).
function ns.QuestForCharacter(q)
    if type(q) ~= "table" or not q.id then return false end
    if q.repeatable or q.hideFromMainList or q.unavailable then return false end
    local faction = ns.PlayerFaction()
    if faction and (q.faction == "Alliance" or q.faction == "Horde") and q.faction ~= faction then return false end
    local FDJ = ns.FDJ() or {}
    if FDJ.IsQuestLost and ns.Try(FDJ.IsQuestLost, q) == true then return false end
    if FDJ.QuestCountsForCharacter and ns.Try(FDJ.QuestCountsForCharacter, q) == false then return false end
    return true
end

function ns.DungeonQuests(dungeon)
    local FDJ = ns.FDJ() or {}
    local data = FDJ.DB and FDJ.DB[dungeon]
    local out = {}
    for _, q in ipairs(type(data) == "table" and data.quests or {}) do
        if ns.QuestForCharacter(q) then out[#out + 1] = q end
    end
    return out
end

-- For the dungeon list: the level range, every boss with its level (the
-- journal's verified boss levels; nil where it has none), the lowest and
-- highest boss level, and how many quests this character can take there.
function ns.DungeonInfo(name)
    local FDJ = ns.FDJ() or {}
    local data = FDJ.DB and FDJ.DB[name]
    if type(data) ~= "table" then return nil end
    local level = data.level ~= nil and tostring(data.level) or nil
    local low, high = (level or ""):match("^(%d+)%s*%-%s*(%d+)")
    low = tonumber(low) or tonumber((level or ""):match("^(%d+)"))
    local info = { name = name, level = level, low = low, high = tonumber(high) or low,
        icon = data.icon, location = data.location, bosses = {}, quests = #ns.DungeonQuests(name) }
    local levels = FDJ.BOSS_LEVELS or {}
    for _, boss in ipairs(type(data.bosses) == "table" and data.bosses or {}) do
        if type(boss) == "table" and type(boss.name) == "string" and boss.name ~= "Trash Drops" then
            local byDungeon = levels[boss.fdjDungeon or name]
            local text = byDungeon and byDungeon[boss.name]
            text = text ~= nil and tostring(text) or nil
            if text or boss.npcID then
                info.bosses[#info.bosses + 1] = { name = boss.name, level = text }
                for digits in (text or ""):gmatch("%d+") do
                    local n = tonumber(digits)
                    if not info.bossLow or n < info.bossLow then info.bossLow = n end
                    if not info.bossHigh or n > info.bossHigh then info.bossHigh = n end
                end
            end
        end
    end
    return info
end

------------------------------------------------------------------ places

local function StartSpot(q)
    local FDJ = ns.FDJ() or {}
    local loc = q.startMap or (FDJ.QUEST_START_MAPS and FDJ.QUEST_START_MAPS[q.id])
    if ns.ValidSpot(loc) then return loc end
    local name = ns.NpcName(q.pickup)
    local spot = name and ns.NpcSpot(name)
    if ns.ValidSpot(spot) then return spot end
    return ns.QuestieSpot(q.id, "startedBy")
end

local function TurnInSpot(q)
    local FDJ = ns.FDJ() or {}
    if ns.ValidSpot(q.turninMap) then return q.turninMap end
    if FDJ.TurnInSpotFor then
        local spot = ns.Try(FDJ.TurnInSpotFor, q)
        if ns.ValidSpot(spot) then return spot end
    end
    local name = ns.NpcName(q.turnin)
    local spot = name and ns.NpcSpot(name)
    if ns.ValidSpot(spot) then return spot end
    return ns.QuestieSpot(q.id, "finishedBy")
end
ns.StartSpot, ns.TurnInSpot = StartSpot, TurnInSpot

-- An objective that is only "go and talk to someone / bring this there" is
-- done by the hand-in itself: no step of its own.
local DELIVERY = { "speak", "talk", "report", "bring", "take ", "deliver", "return", "go to", "travel", "meet", "seek", "find " }
-- Where the objective is done: the journal's own spot, else QuestieDB's area.
local function ObjectiveSpot(questID, details)
    if ns.ValidSpot(details.objectiveMap) then return details.objectiveMap end
    return ns.QuestieAreaSpot(questID)
end
ns.ObjectiveSpot = ObjectiveSpot

-- QuestieDB knowing where it's done settles it ("Bring 8 Gnoll Paws to..."
-- is collecting first, whatever the verb).
local function NeedsObjectiveStep(details, questID)
    if ObjectiveSpot(questID, details) then return true end
    local t = Lower(details.objective)
    if t == "" then return false end
    for _, verb in ipairs(DELIVERY) do
        if t:sub(1, #verb) == verb then return false end
    end
    return true
end

------------------------------------------------------------------ chain steps

-- The chain steps i..stop (one step, or a choice of several) are done.
local function StepsDone(q, chain, i, stop)
    local FDJ = ns.FDJ() or {}
    if FDJ.ChainStepsDone then return ns.Try(FDJ.ChainStepsDone, q, chain, i, stop) == true end
    for k = i, stop do
        local s = chain[k]
        if type(s) == "table" and s.id then
            if ns.TurnedIn(s.id) then return true end
            if s.acceptOnly and ns.InLog(s.id) then return true end
            if s.itemStep then
                local item = Details(s.id).startItem
                if type(item) == "table" and ns.ItemCount(item[1]) > 0 then return true end
            end
        end
    end
    return false
end

local function ChainOf(q)
    local FDJ = ns.FDJ() or {}
    if FDJ.PrereqChainOf then return ns.Try(FDJ.PrereqChainOf, q.id) end
    return FDJ.QUEST_PREREQ_CHAINS and FDJ.QUEST_PREREQ_CHAINS[q.id]
end

-- The chain steps that come before the quest itself (a chain can go on past it).
local function PrereqEnd(q, chain)
    local FDJ = ns.FDJ() or {}
    if FDJ.ChainPrereqEnd then
        local last = ns.Try(FDJ.ChainPrereqEnd, q, chain)
        if type(last) == "number" then return last end
    end
    for i, s in ipairs(chain) do
        if type(s) == "table" and s.id == q.id then return i - 1 end
    end
    return #chain
end

local function ChoiceEnd(chain, i)
    local FDJ = ns.FDJ() or {}
    if FDJ.ChainInChoice then
        local _, last = ns.Try(FDJ.ChainInChoice, chain, i)
        if type(last) == "number" then return last end
        return i
    end
    local s = chain[i]
    local last = i
    if type(s) == "table" and s.choice ~= nil then
        while type(chain[last + 1]) == "table" and chain[last + 1].choice == s.choice do last = last + 1 end
    end
    return last
end

------------------------------------------------------------------ building

-- What comes first, before distance counts at all: every quest chain step
-- (the prerequisites), then the dungeon's quests picked up out in the world
-- (and finished ones handed in), then the dungeon itself.
ns.TIER_CHAIN, ns.TIER_OUTSIDE, ns.TIER_DUNGEON = 1, 2, 3

local function NewTask(kind, questID, name, fields)
    local t = fields or {}
    t.kind, t.questID, t.questName = kind, questID, name
    t.tier = t.tier or ns.TIER_OUTSIDE
    t.key = kind .. ":" .. tostring(questID)
    t.icon = t.icon or ns.ICONS[kind]
    t.after = {}
    t.forQuests = {}
    return t
end

-- One chain step's tasks. false + why when the chain can't go on before the
-- run (a level too low, a step that starts or is done inside a dungeon).
local function StepTasks(step, others, add, level, nextQ)
    local function addChain(t) t.tier = ns.TIER_CHAIN return add(t) end
    local det = Details(step.id)
    local name = step.name or det.name or ("Quest " .. tostring(step.id))
    local faction = ns.PlayerFaction()
    local pickup = (faction == "Alliance" and det.pickupAlliance) or (faction == "Horde" and det.pickupHorde) or det.pickup
    local inLog = ns.InLog(step.id)
    local orText = (#others > 0) and ("or: " .. table.concat(others, ", ")) or nil

    if (step.startsInDungeon or det.startsInDungeon) and not inLog then
        return false, name .. " starts inside the dungeon"
    end
    if not inLog and tonumber(det.requires) and level < tonumber(det.requires) then
        return false, ("level %d for %s"):format(tonumber(det.requires), name)
    end
    local stepQ = { id = step.id, name = name, pickup = pickup, turnin = det.turnin, turninMap = det.turninMap,
        startMap = det.map, objectiveMap = det.objectiveMap }

    if step.itemStep then
        local item = det.startItem
        addChain(NewTask("item", step.id, name, { spot = ns.ValidSpot(det.map) and det.map or nil,
            itemID = type(item) == "table" and item[1] or nil,
            title = "Get: " .. name, detail = det.objective or pickup }))
        return true
    end

    if not inLog then
        local item = det.startItem
        if type(item) == "table" and item[1] then
            if ns.ItemCount(item[1]) > 0 then
                addChain(NewTask("useitem", step.id, name, { itemID = item[1],
                    title = "Use " .. tostring(item[2] or "the item") .. " in your bags",
                    detail = "Starts " .. name }))
            else
                addChain(NewTask("item", step.id, name, { itemID = item[1], spot = ns.ValidSpot(det.map) and det.map or nil,
                    title = "Get: " .. tostring(item[2] or name), detail = (item[4] or pickup or "") .. " (starts " .. name .. ")" }))
            end
        else
            addChain(NewTask("pickup", step.id, name, { spot = StartSpot(stepQ),
                title = "Pick up: " .. name, detail = pickup, note = orText }))
        end
        if step.acceptOnly then return true end
    end

    if not ns.Complete(step.id) then
        if det.objectiveInDungeon or step.needsDungeon then
            return false, name .. " is done inside a dungeon"
        end
        if NeedsObjectiveStep(det, step.id) then
            addChain(NewTask("objective", step.id, name, { spot = ObjectiveSpot(step.id, det),
                title = "Do: " .. name, detail = det.objective }))
        end
    end
    local spot, detail = TurnInSpot(stepQ), det.turnin
    if not spot and not det.turnin and nextQ then
        -- No hand-in place in the data: in a chain it is nearly always
        -- whoever gives the next step.
        -- whoever gives the next step, else back where this one was taken.
        local nextSpot, from = StartSpot(nextQ), nextQ.pickup
        if not nextSpot then nextSpot, from = StartSpot(stepQ), pickup end
        if nextSpot then
            spot = {}
            for k, v in pairs(nextSpot) do spot[k] = v end
            spot.guess = true
            detail = "Probably " .. (from or nextSpot.label or "where the next step starts")
        end
    end
    addChain(NewTask("turnin", step.id, name, { spot = spot, title = "Hand in: " .. name, detail = detail }))
    return true
end

local function ChainTasks(q, add, level)
    local chain = ChainOf(q)
    if type(chain) ~= "table" then return true end
    local last = PrereqEnd(q, chain)
    local i = 1
    while i <= last do
        local stop = math.min(ChoiceEnd(chain, i), last)
        if type(chain[i]) == "table" and chain[i].id and not StepsDone(q, chain, i, stop) then
            -- a choice: the one in the log, else the first
            local pick = i
            for k = i, stop do
                if type(chain[k]) == "table" and chain[k].id and ns.InLog(chain[k].id) then pick = k break end
            end
            local others = {}
            for k = i, stop do
                if k ~= pick and type(chain[k]) == "table" then others[#others + 1] = chain[k].name or tostring(chain[k].id) end
            end
            -- what comes after: the next chain step, else the quest itself
            local nextQ = q
            local after = chain[stop + 1]
            if stop + 1 <= last and type(after) == "table" and after.id then
                local d = Details(after.id)
                nextQ = { id = after.id, pickup = d.pickup, startMap = d.map }
            end
            local ok, why = StepTasks(chain[pick], others, add, level, nextQ)
            if not ok then return false, why end
        end
        i = stop + 1
    end
    return true
end

------------------------------------------------------------------ ordering

-- By tier first (chains, then quests out in the world, then the dungeon);
-- within a tier, nearest next: from where the character stands, always the
-- closest task whose steps before it are done. A task with no map spot that
-- carries on the one just placed (loot the item, then use it) comes right
-- after it.
ns.costCache = {}
function ns.ClearCostCache() ns.costCache = {} end

local function Order(tasks)
    local placed, out = {}, {}
    local pos, lastKey
    local fromPlayer = {} -- from where the character stands: this time only
    local function Cost(to)
        local toKey = to.mapID .. ":" .. to.x .. ":" .. to.y
        if not pos then
            if fromPlayer[toKey] == nil then fromPlayer[toKey] = ns.Cost(nil, to) or ns.FAR end
            return fromPlayer[toKey]
        end
        -- place to place: kept between plans (cleared on a new zone, new flight paths)
        local key = pos.mapID .. ":" .. pos.x .. ":" .. pos.y .. ">" .. toKey
        if ns.costCache[key] == nil then ns.costCache[key] = ns.Cost(pos, to) or ns.FAR end
        return ns.costCache[key]
    end
    local function Ready(t)
        for _, k in ipairs(t.after) do
            if not placed[k] then return false end
        end
        return true
    end
    for _ = 1, #tasks do
        local best, bestTier, bestCost
        for _, t in ipairs(tasks) do
            if not placed[t.key] and Ready(t) then
                local cost
                if t.spot then
                    cost = Cost(t.spot)
                elseif lastKey and t.after[#t.after] == lastKey then
                    cost = -1
                else
                    cost = ns.FAR * 5
                end
                local tier = t.tier or ns.TIER_OUTSIDE
                if not best or tier < bestTier or (tier == bestTier and cost < bestCost) then
                    best, bestTier, bestCost = t, tier, cost
                end
            end
        end
        if not best then break end
        placed[best.key] = true
        out[#out + 1] = best
        lastKey = best.key
        if best.spot then pos = best.spot end
    end
    for _, t in ipairs(tasks) do -- a loop in the data: never lose a task
        if not placed[t.key] then out[#out + 1] = t end
    end
    return out
end
ns.OrderTasks = Order

------------------------------------------------------------------ the plan

-- Everything a plan depends on, as a string: the guide only plans again
-- when it changes (the quest log updates on every kill).
function ns.PlanSignature(dungeon, skip)
    local parts = { dungeon or "", ns.PlayerLevel(), ns.PlayerFaction() or "", ns.InInstance() and "in" or "out" }
    local function Quest(id)
        if not id then return end
        parts[#parts + 1] = id .. (ns.TurnedIn(id) and "d" or (ns.InLog(id) and (ns.Complete(id) and "c" or "l") or "-"))
    end
    local function Item(item)
        if type(item) == "table" and item[1] then parts[#parts + 1] = "i" .. item[1] .. "=" .. (ns.ItemCount(item[1]) > 0 and 1 or 0) end
    end
    for _, q in ipairs(ns.DungeonQuests(dungeon)) do
        Quest(q.id)
        Item(q.startItem)
        local chain = ChainOf(q)
        for _, step in ipairs(type(chain) == "table" and chain or {}) do
            if type(step) == "table" and step.id then
                Quest(step.id)
                Item(Details(step.id).startItem)
            end
        end
    end
    for id in pairs(skip or {}) do parts[#parts + 1] = "s" .. id end
    return table.concat(parts, ",")
end

-- skip: { [questID] = true } quests the user left out.
function ns.BuildPlan(dungeon, skip)
    local FDJ = ns.FDJ() or {}
    local data = FDJ.DB and FDJ.DB[dungeon]
    local plan = { dungeon = dungeon, tasks = {}, inside = {}, later = {}, have = {}, ready = {}, skipped = {},
        doneCount = 0, total = 0 }
    if type(data) ~= "table" then return plan end
    plan.icon = data.icon
    skip = skip or {}
    local level = ns.PlayerLevel()
    local all, byKey = {}, {}

    for _, q in ipairs(ns.DungeonQuests(dungeon)) do
        local name = q.name or ("Quest " .. q.id)
        plan.total = plan.total + 1
        local prev
        -- each task waits for the one before it in the same quest's chain; a
        -- step two quests share is planned once
        local function add(t)
            local have = byKey[t.key]
            if have then
                have.forQuests[#have.forQuests + 1] = name
                -- one of the dungeon's quests that is also a step in another's chain: a prerequisite
                have.tier = math.min(have.tier or ns.TIER_OUTSIDE, t.tier or ns.TIER_OUTSIDE)
                prev = have.key
                return
            end
            if prev then t.after[#t.after + 1] = prev end
            t.forQuests[1] = name
            t.mainQuestID = q.id
            all[#all + 1] = t
            byKey[t.key] = t
            prev = t.key
        end

        if ns.TurnedIn(q.id) then
            plan.doneCount = plan.doneCount + 1
        elseif skip[q.id] then
            plan.skipped[#plan.skipped + 1] = { quest = q, name = name }
        elseif ns.InLog(q.id) then
            plan.doneCount = plan.doneCount + 1 -- picked up
            if ns.Complete(q.id) then
                if SaysInside(q.turnin) then
                    plan.inside[#plan.inside + 1] = { quest = q, name = name, title = "Hand in: " .. name, detail = q.turnin, icon = ns.ICONS.turnin }
                else
                    add(NewTask("turnin", q.id, name, { spot = TurnInSpot(q), title = "Hand in: " .. name,
                        detail = q.turnin, handIn = true }))
                    plan.ready[#plan.ready + 1] = { quest = q, name = name }
                end
            else
                plan.have[#plan.have + 1] = { quest = q, name = name, detail = q.objective }
            end
        elseif tonumber(q.requires) and level < tonumber(q.requires) then
            plan.later[#plan.later + 1] = { quest = q, name = name, why = "needs level " .. tonumber(q.requires) }
        else
            local ok, why = ChainTasks(q, add, level)
            local startItem = type(q.startItem) == "table" and q.startItem[1] or nil
            if not ok then
                plan.later[#plan.later + 1] = { quest = q, name = name, why = "after the run: " .. why }
            elseif startItem and ns.ItemCount(startItem) > 0 then
                -- the item that starts it is already in the bags (wherever it drops)
                add(NewTask("useitem", q.id, name, { itemID = startItem, main = true,
                    title = "Use " .. tostring(q.startItem[2] or "the item") .. " in your bags", detail = "Starts " .. name }))
            elseif q.startsInDungeon or SaysInside(q.pickup) or (startItem and DropsInside(q, data)) then
                plan.inside[#plan.inside + 1] = { quest = q, name = name, title = "Pick up inside: " .. name,
                    detail = q.pickup, icon = ns.ICONS.pickup, itemID = type(q.startItem) == "table" and q.startItem[1] or nil }
            elseif startItem then
                local item = q.startItem
                add(NewTask("item", q.id, name, { itemID = startItem, main = true,
                    spot = ns.ValidSpot(q.startMap) and q.startMap or nil,
                    title = "Get: " .. tostring(item[2] or name), detail = (item[4] or q.pickup or "") .. " (starts " .. name .. ")" }))
            else
                add(NewTask("pickup", q.id, name, { spot = StartSpot(q), main = true,
                    title = "Pick up: " .. name, detail = q.pickup }))
            end
        end
    end

    -- The entrance, after every pick-up, when there is anything to do inside.
    local needRun = #plan.have > 0 or #plan.inside > 0
    for _, t in ipairs(all) do
        if not t.handIn then needRun = true break end
    end
    if needRun and ns.ValidSpot(data.entrance) then
        local entrance = NewTask("entrance", dungeon, dungeon, { spot = data.entrance, tier = ns.TIER_DUNGEON, icon = data.icon or ns.ICONS.entrance,
            title = "Go to " .. dungeon, detail = data.entrance.detail or data.location })
        for _, t in ipairs(all) do
            if not t.handIn then entrance.after[#entrance.after + 1] = t.key end
        end
        all[#all + 1] = entrance
    end

    plan.tasks = Order(all)
    return plan
end
