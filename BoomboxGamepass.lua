-- Roblox Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local BoomboxMusic = require(ReplicatedStorage.Scripts.BoomboxMusic)

-- Defines
local HasBoomboxGamepass = {} -- Set<Player>
local EquipBoomboxRequest = {} -- Set<Player>
local BoomboxTool = {} -- [Player] = Tool
local BoomboxSounds = {} -- [Player] = Sound -> On Character

-- Networking
local RE_EquipBoombox = ReplicatedStorage.Events.RemoteEvents.EquipBoombox
local RE_SetBoomboxMusic = ReplicatedStorage.Events.RemoteEvents.SetBoomboxMusic

-- Helper Functions
local function WeldInPlace(Src: BasePart, Dest: BasePart): Weld
	local Weld = Instance.new("Weld")
	Weld.C0 = Src.CFrame:ToObjectSpace(Dest.CFrame)
	Weld.Part0 = Src
	Weld.Part1 = Dest
	Weld.Name = Dest.Name
	Weld.Parent = Src
	return Weld
end

local function UpdateMusic(Player: Player, SoundID: string?, MusicID: string?, Volume: number?)
	if not HasBoomboxGamepass[Player] then return end
	if not Player.Character then return end
	if not Player.Character.PrimaryPart then return end

	-- Create / Modify
	if SoundID and MusicID and EquipBoomboxRequest[Player] then
		Player:SetAttribute("BoomboxMusicID", MusicID)
		
		-- Modify
		if BoomboxSounds[Player] then
			BoomboxSounds[Player]:Stop()
			BoomboxSounds[Player].SoundId = SoundID
			BoomboxSounds[Player].TimePosition = 0
			BoomboxSounds[Player]:Play()
		else
			BoomboxSounds[Player] = Instance.new("Sound")
			BoomboxSounds[Player].Name = "Boombox"
			BoomboxSounds[Player].SoundId = SoundID
			BoomboxSounds[Player].Volume = Volume
			BoomboxSounds[Player].Looped = true
			BoomboxSounds[Player].RollOffMode = Enum.RollOffMode.InverseTapered
			BoomboxSounds[Player].RollOffMinDistance = 20
			BoomboxSounds[Player].RollOffMaxDistance = 400
			BoomboxSounds[Player].Parent = Player.Character.PrimaryPart
			BoomboxSounds[Player].AncestryChanged:Connect(function(_, NewParent)
				if NewParent == nil then
					if BoomboxSounds[Player] then
						Player:SetAttribute("BoomboxMusicID", nil)
						
						BoomboxSounds[Player]:Destroy()
						BoomboxSounds[Player] = nil
					end
				end
			end)
			BoomboxSounds[Player]:Play()
		end
		
	-- Delete
	elseif BoomboxSounds[Player] then
		Player:SetAttribute("BoomboxMusicID", nil)
		
		BoomboxSounds[Player]:Destroy()
		BoomboxSounds[Player] = nil
	end
end

local function UpdateBoombox(Player: Player)
	-- Equip it
	if HasBoomboxGamepass[Player] and EquipBoomboxRequest[Player] then
		if BoomboxTool[Player] == nil
			and Player.Character
			and Player.Character.PrimaryPart
		then
			local RightHand = Player.Character:FindFirstChild("RightHand")
			if not RightHand then return end
			
			BoomboxTool[Player] = ReplicatedStorage.BoomboxTool:Clone()
			BoomboxTool[Player]:PivotTo(RightHand.CFrame)
			WeldInPlace(BoomboxTool[Player].PrimaryPart, RightHand)
			BoomboxTool[Player].AncestryChanged:Connect(function(_, NewParent)
				if NewParent == nil then
					if BoomboxTool[Player] then
						BoomboxTool[Player]:Destroy()
						BoomboxTool[Player] = nil
					end
					UpdateMusic(Player, nil)
					EquipBoomboxRequest[Player] = false
					Player:SetAttribute("EquippedBoombox", nil)
				end
			end)
			BoomboxTool[Player].Parent = Player.Character
		end
		
	-- Remove it
	elseif not HasBoomboxGamepass[Player] or not EquipBoomboxRequest[Player] then
		if BoomboxTool[Player] then
			BoomboxTool[Player]:Destroy()
			BoomboxTool[Player] = nil
		end
		UpdateMusic(Player, nil)
		EquipBoomboxRequest[Player] = false
		Player:SetAttribute("EquippedBoombox", nil)
	end
end

local function EquipBoombox(Player: Player, State: boolean)
	EquipBoomboxRequest[Player] = State
	Player:SetAttribute("EquippedBoombox", State and true or nil)
	UpdateBoombox(Player)
end

local function TrackPlayer(Player: Player)
	if Player:GetAttribute("HasBoomboxMusicPlayer") then
		HasBoomboxGamepass[Player] = true
	end
	Player:GetAttributeChangedSignal("HasBoomboxMusicPlayer"):Connect(function()
		HasBoomboxGamepass[Player] = Player:GetAttribute("HasBoomboxMusicPlayer")
		UpdateBoombox(Player)
	end)
	Player.CharacterAdded:Connect(function()
		if BoomboxTool[Player] then
			BoomboxTool[Player]:Destroy()
			BoomboxTool[Player] = nil
		end
		UpdateMusic(Player, nil)
		EquipBoomboxRequest[Player] = false
		Player:SetAttribute("EquippedBoombox", nil)
		UpdateBoombox(Player)
	end)
end

-- Events
Players.PlayerAdded:Connect(function(Player)
	TrackPlayer(Player)
end)
for _, Player in Players:GetPlayers() do
	TrackPlayer(Player)
end

Players.PlayerRemoving:Connect(function(Player)
	HasBoomboxGamepass[Player] = nil
	EquipBoomboxRequest[Player] = nil
	if BoomboxTool[Player] then
		BoomboxTool[Player]:Destroy()
		BoomboxTool[Player] = nil
	end
end)

-- Networking
RE_EquipBoombox.OnServerEvent:Connect(function(Player: Player, State: boolean)
	if not HasBoomboxGamepass[Player] then return end
	if typeof(State) ~= "boolean" then return end
	
	EquipBoombox(Player, State)
end)

RE_SetBoomboxMusic.OnServerEvent:Connect(function(Player: Player, MusicID: string)
	if not HasBoomboxGamepass[Player] then return end
	if not EquipBoomboxRequest[Player] then return end
	
	if MusicID == nil then
		UpdateMusic(Player, nil)
		
	elseif BoomboxMusic[MusicID] then
		local Volume = BoomboxMusic[MusicID].Volume
		local SoundID = BoomboxMusic[MusicID].ID
		
		UpdateMusic(Player, SoundID, MusicID, Volume)
	end
end)