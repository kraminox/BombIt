--!strict
-- QuestService.lua
-- Server-side quest assignment, progress tracking, claiming, and daily/weekly resets

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local GameState = require(Shared:WaitForChild("GameState"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local QuestService = {}

-- Quest data per player: { dailyQuests = {}, weeklyQuests = {}, lastDailyReset = "", lastWeeklyReset = "" }
local playerQuests: {[number]: any} = {}

-- Per-player claim mutex (prevents double-claim race conditions)
local claimProcessing: {[number]: boolean} = {}

-- Get today's date string (UTC)
local function GetTodayString(): string
	return os.date("!%Y-%m-%d") :: string
end

-- Get this week's Monday date string (UTC)
local function GetWeekString(): string
	local now = os.time()
	local date = os.date("!*t", now)
	-- Lua wday: 1=Sunday, 2=Monday, ...
	local wday = date.wday :: number
	local daysSinceMonday = (wday - 2) % 7
	local monday = now - daysSinceMonday * 86400
	return os.date("!%Y-%m-%d", monday) :: string
end

-- Pick N random unique items from a pool
local function PickRandom(pool: {{[string]: any}}, count: number): {{[string]: any}}
	local shuffled = {}
	for _, item in ipairs(pool) do
		table.insert(shuffled, item)
	end
	-- Fisher-Yates shuffle
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	local result = {}
	for i = 1, math.min(count, #shuffled) do
		table.insert(result, {
			id = shuffled[i].id,
			description = shuffled[i].description,
			goal = shuffled[i].goal,
			stat = shuffled[i].stat,
			reward = shuffled[i].reward,
			progress = 0,
			claimed = false,
		})
	end
	return result
end

-- Load or assign quests for a player
function QuestService.LoadPlayerQuests(player: Player, savedData: any?)
	local userId = player.UserId
	local today = GetTodayString()
	local thisWeek = GetWeekString()

	local data = savedData or {}
	local needsSync = false

	-- Check if daily quests need reset
	if data.lastDailyReset ~= today or not data.dailyQuests or #data.dailyQuests == 0 then
		-- Always 1 time-based quest + 2 regular quests
		local timeQuest = PickRandom(Economy.DAILY_TIME_QUESTS, 1)
		local regularQuests = PickRandom(Economy.DAILY_QUESTS, 2)
		data.dailyQuests = {}
		for _, q in ipairs(timeQuest) do
			table.insert(data.dailyQuests, q)
		end
		for _, q in ipairs(regularQuests) do
			table.insert(data.dailyQuests, q)
		end
		data.lastDailyReset = today
		needsSync = true
	end

	-- Check if weekly quests need reset
	if data.lastWeeklyReset ~= thisWeek or not data.weeklyQuests or #data.weeklyQuests == 0 then
		data.weeklyQuests = PickRandom(Economy.WEEKLY_QUESTS, Economy.WEEKLY_QUEST_COUNT)
		data.lastWeeklyReset = thisWeek
		needsSync = true
	end

	playerQuests[userId] = data
	return needsSync
end

-- Get quest data for a player (for syncing to client)
function QuestService.GetPlayerQuests(player: Player): any?
	return playerQuests[player.UserId]
end

-- Get quest save data for DataStore persistence
function QuestService.GetSaveData(player: Player): any?
	return playerQuests[player.UserId]
end

-- Clean up quest data when player leaves
function QuestService.RemovePlayer(player: Player)
	playerQuests[player.UserId] = nil
	claimProcessing[player.UserId] = nil
end

-- Increment a stat for a player and check quest progress
function QuestService.IncrementStat(player: Player, statName: string, amount: number?)
	local userId = player.UserId
	local data = playerQuests[userId]
	if not data then return end

	local delta = amount or 1
	local changed = false

	-- Check daily quests
	if data.dailyQuests then
		for _, quest in ipairs(data.dailyQuests) do
			if quest.stat == statName and not quest.claimed then
				quest.progress = math.min((quest.progress or 0) + delta, quest.goal)
				changed = true
			end
		end
	end

	-- Check weekly quests
	if data.weeklyQuests then
		for _, quest in ipairs(data.weeklyQuests) do
			if quest.stat == statName and not quest.claimed then
				quest.progress = math.min((quest.progress or 0) + delta, quest.goal)
				changed = true
			end
		end
	end

	-- Sync to client if changed
	if changed then
		local SyncQuests = Remotes:FindFirstChild("SyncQuests")
		if SyncQuests then
			SyncQuests:FireClient(player, data)
		end
	end
end

-- Set a stat to a specific value (for win_streak which resets)
function QuestService.SetStat(player: Player, statName: string, value: number)
	local userId = player.UserId
	local data = playerQuests[userId]
	if not data then return end

	local changed = false

	local function updateQuests(quests: {{[string]: any}}?)
		if not quests then return end
		for _, quest in ipairs(quests) do
			if quest.stat == statName and not quest.claimed then
				quest.progress = math.min(value, quest.goal)
				changed = true
			end
		end
	end

	updateQuests(data.dailyQuests)
	updateQuests(data.weeklyQuests)

	if changed then
		local SyncQuests = Remotes:FindFirstChild("SyncQuests")
		if SyncQuests then
			SyncQuests:FireClient(player, data)
		end
	end
end

-- Claim a completed quest reward
function QuestService.ClaimQuest(player: Player, questId: string): (boolean, string?)
	local userId = player.UserId
	if claimProcessing[userId] then return false, "Busy" end
	claimProcessing[userId] = true

	local data = playerQuests[userId]
	if not data then claimProcessing[userId] = nil return false, "No quest data" end

	-- Find the quest
	local quest = nil
	local questList = nil
	for _, q in ipairs(data.dailyQuests or {}) do
		if q.id == questId then
			quest = q
			questList = "daily"
			break
		end
	end
	if not quest then
		for _, q in ipairs(data.weeklyQuests or {}) do
			if q.id == questId then
				quest = q
				questList = "weekly"
				break
			end
		end
	end

	if not quest then claimProcessing[userId] = nil return false, "Quest not found" end
	if quest.claimed then claimProcessing[userId] = nil return false, "Already claimed" end
	if (quest.progress or 0) < quest.goal then claimProcessing[userId] = nil return false, "Not completed" end

	-- Mark as claimed
	quest.claimed = true

	-- Grant rewards
	local persistent = GameState.persistentData[userId]
	if persistent and quest.reward then
		if quest.reward.coins then
			persistent.totalCoins = (persistent.totalCoins or 0) + quest.reward.coins

			-- Update PersistentStats IntValue
			local p = Players:GetPlayerByUserId(userId)
			if p then
				local pStats = p:FindFirstChild("PersistentStats")
				if pStats then
					local coinsVal = pStats:FindFirstChild("TotalCoins")
					if coinsVal then
						coinsVal.Value = persistent.totalCoins
					end
				end
			end
		end
	end

	-- Sync to client
	local SyncQuests = Remotes:FindFirstChild("SyncQuests")
	if SyncQuests then
		SyncQuests:FireClient(player, data)
	end

	claimProcessing[userId] = nil
	return true, nil
end

-- Initialize the service
function QuestService.Initialize()
	-- Create remotes
	local function EnsureRemote(name: string, className: string): Instance
		local existing = Remotes:FindFirstChild(name)
		if existing then return existing end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = Remotes
		return remote
	end

	local SyncQuests = EnsureRemote("SyncQuests", "RemoteEvent")
	local ClaimQuest = EnsureRemote("ClaimQuest", "RemoteFunction")

	-- Handle claim requests
	ClaimQuest.OnServerInvoke = function(player: Player, questId: string)
		if type(questId) ~= "string" then return { success = false, reason = "Invalid quest ID" } end
		local success, reason = QuestService.ClaimQuest(player, questId)
		return { success = success, reason = reason }
	end

	-- Play-time tracker: increment play_minutes every 60 seconds for all players
	task.spawn(function()
		while true do
			task.wait(60)
			for _, p in ipairs(Players:GetPlayers()) do
				QuestService.IncrementStat(p, "play_minutes", 1)
			end
		end
	end)

	print("[QuestService] Initialized")
end

return QuestService
