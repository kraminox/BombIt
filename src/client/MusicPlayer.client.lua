--!strict
-- MusicPlayer.client.lua
-- Loops through songs in Assets/Music at low volume

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local VOLUME = 0.05
local FADE_TIME = 1.5

local musicFolder = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Music")

-- Collect all Sound objects from the folder
local function GetSongs(): {Sound}
	local songs = {}
	for _, child in ipairs(musicFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(songs, child)
		end
	end
	return songs
end

-- Shuffle array in place
local function Shuffle(t: {any})
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

-- Play music in a loop, shuffling each cycle
task.spawn(function()
	-- Create a Sound instance in SoundService for playback
	local player = Instance.new("Sound")
	player.Name = "BGMusic"
	player.Volume = 0
	player.Parent = SoundService

	while true do
		local songs = GetSongs()
		if #songs == 0 then
			task.wait(5)
			continue
		end

		Shuffle(songs)

		for _, song in ipairs(songs) do
			player.SoundId = song.SoundId
			player.Volume = 0
			player:Play()

			-- Fade in
			local elapsed = 0
			while elapsed < FADE_TIME do
				elapsed += task.wait()
				player.Volume = math.min(VOLUME, (elapsed / FADE_TIME) * VOLUME)
			end
			player.Volume = VOLUME

			-- Wait for song to end
			player.Ended:Wait()
		end
	end
end)

print("[MusicPlayer] Background music initialized")
