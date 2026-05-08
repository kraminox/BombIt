--!strict
-- LeaderboardService.lua
-- Manages global OrderedDataStore leaderboards and populates physical SurfaceGui boards

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")

local LeaderboardService = {}

-- Board configuration: maps model names to datastore keys and formatting
local BOARDS = {
	WinsLeaderboard = { store = "Leaderboard_Wins", stat = "wins", prefix = "" },
	KillsLeaderboard = { store = "Leaderboard_Kills", stat = "totalKills", prefix = "" },
	DonateLeaderboard = { store = "Leaderboard_RobuxSpent", stat = "robuxSpent", prefix = "R$" },
}

local REFRESH_INTERVAL = 180 -- 3 minutes
local MAX_ENTRIES = 10

-- Cached OrderedDataStores
local orderedStores = {} :: {[string]: OrderedDataStore}

-- Track last refresh time for countdown
local lastRefreshTime = 0

-- Format large numbers: 1000 -> "1K", 1500 -> "1.5K", 1000000 -> "1M"
local function FormatNumber(value: number, prefix: string): string
	if value >= 1000000 then
		local m = value / 1000000
		if m == math.floor(m) then
			return prefix .. string.format("%dM", m)
		else
			return prefix .. string.format("%.1fM", m)
		end
	elseif value >= 1000 then
		local k = value / 1000
		if k == math.floor(k) then
			return prefix .. string.format("%dK", k)
		else
			return prefix .. string.format("%.1fK", k)
		end
	else
		return prefix .. tostring(value)
	end
end

-- Get or create an OrderedDataStore for a given key
local function GetStore(storeKey: string): OrderedDataStore
	if not orderedStores[storeKey] then
		orderedStores[storeKey] = DataStoreService:GetOrderedDataStore(storeKey)
	end
	return orderedStores[storeKey]
end

-- Update a player's score in a specific ordered datastore
function LeaderboardService.UpdatePlayerStats(player: Player, statName: string, value: number)
	-- Find the board config that uses this stat
	for _, config in pairs(BOARDS) do
		if config.stat == statName then
			task.spawn(function()
				local store = GetStore(config.store)
				local success, err = pcall(function()
					store:SetAsync(tostring(player.UserId), value)
				end)
				if not success then
					warn("[LeaderboardService] Failed to update " .. statName .. " for " .. player.Name .. ": " .. tostring(err))
				end
			end)
			break
		end
	end
end

-- Update a player's score by userId (for use after save when player object may be gone)
function LeaderboardService.UpdateStatByUserId(userId: number, statName: string, value: number)
	for _, config in pairs(BOARDS) do
		if config.stat == statName then
			task.spawn(function()
				local store = GetStore(config.store)
				local success, err = pcall(function()
					store:SetAsync(tostring(userId), value)
				end)
				if not success then
					warn("[LeaderboardService] Failed to update " .. statName .. " for userId " .. tostring(userId) .. ": " .. tostring(err))
				end
			end)
			break
		end
	end
end

-- Fetch top N players from an ordered datastore
local function FetchTopPlayers(storeKey: string, count: number): {{userId: number, value: number}}
	local store = GetStore(storeKey)
	local entries = {}

	local success, result = pcall(function()
		return store:GetSortedAsync(false, count)
	end)

	if success and result then
		local page = result:GetCurrentPage()
		for _, entry in ipairs(page) do
			local userId = tonumber(entry.key)
			if userId then
				table.insert(entries, {
					userId = userId,
					value = entry.value,
				})
			end
		end
	else
		warn("[LeaderboardService] Failed to fetch from " .. storeKey .. ": " .. tostring(result))
	end

	return entries
end

-- Get player thumbnail with pcall safety
local function GetThumbnail(userId: number): string
	local success, thumb = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size48x48
		)
	end)
	if success and thumb then
		return thumb
	end
	return ""
end

-- Get player name by userId (check online players first, then API)
local function GetPlayerName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if success and name then
		return name
	end
	return "Player"
end

-- Find the SurfaceGui inside a board model (may be on any child Part)
local function FindBoardGui(boardModel: Model): SurfaceGui?
	for _, child in ipairs(boardModel:GetDescendants()) do
		if child:IsA("SurfaceGui") then
			return child :: SurfaceGui
		end
	end
	return nil
end

-- Update a single board's UI with fetched entries
local function UpdateBoardUI(boardModel: Model, entries: {{userId: number, value: number}}, config: {store: string, stat: string, prefix: string})
	local gui = FindBoardGui(boardModel)
	if not gui then return end

	local mainFrame = gui:FindFirstChild("MainFrame")
	if not mainFrame then return end

	local entriesContainer = mainFrame:FindFirstChild("EntriesContainer")
	if not entriesContainer then return end

	local entriesScroll = entriesContainer:FindFirstChild("EntriesScroll")
	if not entriesScroll then return end

	-- Find the template
	local template = entriesScroll:FindFirstChild("EntryTemplate")
	if not template then return end

	-- Remove old clones (anything that isn't the template or UIListLayout)
	for _, child in ipairs(entriesScroll:GetChildren()) do
		if child.Name ~= "EntryTemplate" and child.Name ~= "UIListLayout" then
			child:Destroy()
		end
	end

	-- Ensure template is invisible
	template.Visible = false

	-- Clone and populate for each entry
	for i, entry in ipairs(entries) do
		local clone = template:Clone()
		clone.Name = "Entry_" .. i
		clone.Visible = true

		-- Set rank
		local rankLabel = clone:FindFirstChild("Rank")
		if rankLabel and rankLabel:IsA("TextLabel") then
			rankLabel.Text = "#" .. tostring(i)
		end

		-- Set player name
		local nameLabel = clone:FindFirstChild("PlayerName")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = GetPlayerName(entry.userId)
		end

		-- Set value
		local valueLabel = clone:FindFirstChild("Value")
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = FormatNumber(entry.value, config.prefix)
		end

		-- Set thumbnail
		local icon = clone:FindFirstChild("Icon")
		if icon and icon:IsA("ImageLabel") then
			local thumb = GetThumbnail(entry.userId)
			if thumb ~= "" then
				icon.Image = thumb
			end
		end

		clone.Parent = entriesScroll
	end
end

-- Update the countdown timer text on a board
local function UpdateCountdownText(boardModel: Model, secondsLeft: number)
	local gui = FindBoardGui(boardModel)
	if not gui then return end

	local mainFrame = gui:FindFirstChild("MainFrame")
	if not mainFrame then return end

	local header = mainFrame:FindFirstChild("Header")
	if not header then return end

	local refreshLabel = header:FindFirstChild("Refresh")
	if refreshLabel and refreshLabel:IsA("TextLabel") then
		local minutes = math.floor(secondsLeft / 60)
		local seconds = secondsLeft % 60
		refreshLabel.Text = string.format("refreshes in %d:%02d", minutes, seconds)
	end
end

-- Refresh all 3 boards
function LeaderboardService.RefreshAllBoards()
	lastRefreshTime = tick()

	local leaderboards = Workspace:FindFirstChild("Lobby") and Workspace.Lobby:FindFirstChild("Leaderboards")
	if not leaderboards then return end

	for boardName, config in pairs(BOARDS) do
		local boardModel = leaderboards:FindFirstChild(boardName)
		if boardModel then
			local entries = FetchTopPlayers(config.store, MAX_ENTRIES)
			UpdateBoardUI(boardModel, entries, config)
		end
	end
end

-- Initialize the service: start the refresh + countdown loop
function LeaderboardService.Initialize()
	print("[LeaderboardService] Initializing leaderboards...")

	-- Initial refresh
	task.spawn(function()
		-- Small delay to let workspace load
		task.wait(2)
		LeaderboardService.RefreshAllBoards()
	end)

	-- Refresh + countdown loop
	task.spawn(function()
		while true do
			task.wait(1)

			local elapsed = tick() - lastRefreshTime
			local secondsLeft = math.max(0, math.ceil(REFRESH_INTERVAL - elapsed))

			-- Update countdown text on all boards
			local leaderboards = Workspace:FindFirstChild("Lobby") and Workspace.Lobby:FindFirstChild("Leaderboards")
			if leaderboards then
				for boardName, _ in pairs(BOARDS) do
					local boardModel = leaderboards:FindFirstChild(boardName)
					if boardModel then
						UpdateCountdownText(boardModel, secondsLeft)
					end
				end
			end

			-- Time to refresh
			if secondsLeft <= 0 then
				LeaderboardService.RefreshAllBoards()
			end
		end
	end)

	print("[LeaderboardService] Leaderboard system ready!")
end

return LeaderboardService
