local SocialMedia = {}

-- Roblox Services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies
local Names = require(script.Names)
local MessageTypes = require(script.MessageTypes) -- kept for parity; not used while server feed is on
local Utility = require(ReplicatedStorage.Scripts.Utility)
local UtilityGUI = require(ReplicatedStorage.Scripts.UI.UtilityGUI)
local SoundController = require(ReplicatedStorage.Scripts.Controllers.SoundController)

-- Constants
local MAX_MESSAGE_COUNT = 50
local NEW_MESSAGE_TIMER = NumberRange.new(4, 12)

-- Feature flag: use server-driven random chatter (RemoteEvent) instead of local MessageTypes
local USE_SERVER_FEED = true

-- Defines
local UI = script.Parent
local RNG = Random.new()
local Messages = {} -- Array<Frame>
local Index = 1
local LayoutCounter = 0

-- UI References
local UI_Exit = UI.MainFrame.Exit
local UI_PostTemplate = UI.MainFrame.Container.Container.ScrollingFrame.PostTemplate
UI_PostTemplate.Visible = false

-- Networking
local EventsRoot = ReplicatedStorage:WaitForChild("Events")
local RE = EventsRoot:WaitForChild("RemoteEvents")
local UIUpdateEvent = RE:WaitForChild("UpdateStatsUI")

-- NEW: server social media feed
local RE_SocialMediaAddPost = RE:WaitForChild("SocialMediaAddPost")

-- Module Functions
function SocialMedia.AddMessage(Message: string, FakeName: string)
	-- Create
	local PostFrame = UI_PostTemplate:Clone()
	PostFrame.Visible = true
	PostFrame.LayoutOrder = LayoutCounter
	PostFrame.Message.TextLabel.Text = Message
	PostFrame.FakeName.Text = FakeName
	PostFrame.Parent = UI_PostTemplate.Parent

	-- Tween effect if visible
	if UI.Enabled then
		local YHeight = PostFrame.Size.Y.Offset
		PostFrame.Size = UDim2.new(PostFrame.Size.X.Scale, PostFrame.Size.X.Offset, PostFrame.Size.Y.Scale, 0)
		TweenService:Create(PostFrame, TweenInfo.new(0.35, Enum.EasingStyle.Bounce), {
			Size = UDim2.new(PostFrame.Size.X.Scale, PostFrame.Size.X.Offset, PostFrame.Size.Y.Scale, YHeight)
		}):Play()
	end

	-- Cache
	if Messages[Index] then
		Messages[Index]:Destroy()
	end
	Messages[Index] = PostFrame

	-- Increment Counters
	Index += 1
	if Index > MAX_MESSAGE_COUNT then Index = 1 end
	LayoutCounter -= 1

	-- Return the new frame so caller can stamp attributes (e.g., LangKey)
	return PostFrame
end

-- NOTE: kept for compatibility; not used when USE_SERVER_FEED = true
function SocialMedia.GenerateMessage(CategoryName: string)
	local FirstName = Names[RNG:NextInteger(1, #Names)]
	local LastName = Names[RNG:NextInteger(1, #Names)]

	-- If the server feed is on, fall back to a simple local random filler,
	-- just in case someone calls this directly.
	local message
	if USE_SERVER_FEED then
		local samples = {
			"Was there always a road there? I like it.",
			"I like the new coffee shop downtown.",
			"I like bananas because they have no bones.",
			"Latest news: A new type of deodorant has been invented! It does exactly the same thing as the old ones.",
		}
		message = samples[RNG:NextInteger(1, #samples)]
	else
		message = MessageTypes[CategoryName] and MessageTypes[CategoryName][RNG:NextInteger(1, #MessageTypes[CategoryName])] or "Hello, city!"
	end

	SocialMedia.AddMessage(message, FirstName.." "..LastName)
end

function SocialMedia.OnShow()
	UI.Enabled = true
end

function SocialMedia.OnHide()
	UI.Enabled = false
end

function SocialMedia.Toggle()
	if UI.Enabled then
		SocialMedia.OnHide()
	else
		SocialMedia.OnShow()
	end
end

-- helper to pick "First Last" from Names
local function randomFullName()
	local FirstName = Names[RNG:NextInteger(1, #Names)]
	local LastName = Names[RNG:NextInteger(1, #Names)]
	return FirstName .. " " .. LastName
end

-- NEW: handle server-driven posts; add LangKey to the actual TextLabel
local function onServerPost(payload)
	if not payload or type(payload.text) ~= "string" then return end
	local frame = SocialMedia.AddMessage(payload.text, randomFullName())
	if frame then
		local tl = frame
			and frame:FindFirstChild("Message")
			and frame.Message:FindFirstChild("TextLabel")
		if tl and payload.langKey then
			tl:SetAttribute("LangKey", payload.langKey)
		end
	end
end

function SocialMedia.Init()
	UserInputService.InputBegan:Connect(function(InputObject, GameProcessedEvent)
		if not UI.Enabled then return end
		if GameProcessedEvent then return end

		if InputObject.KeyCode == Enum.KeyCode.ButtonB then
			SoundController.PlaySoundOnce("UI", "SmallClick")
			SocialMedia.OnHide()
		end
	end)

	-- Exit Button
	UI_Exit.MouseButton1Down:Connect(function()
		SoundController.PlaySoundOnce("UI", "SmallClick")
		SocialMedia.OnHide()
	end)

	-- Exit Button VFX
	UtilityGUI.VisualMouseInteraction(
		UI_Exit, UI_Exit.TextLabel,
		TweenInfo.new(0.15),
		{ Size = UDim2.fromScale(1.2, 1.2) },
		{ Size = UDim2.fromScale(0.25, 0.25) }
	)

	-- Update Demands (kept; not used when server feed is on)
	local ResidentialDemand = 0
	local DenseResidentialDemand = 0
	local CommercialDemand = 0
	local DenseCommercialDemand = 0
	local IndustrialDemand = 0
	local DenseIndustrialDemand = 0

	UIUpdateEvent.OnClientEvent:Connect(function(payload)
		if not payload then return end
		if payload.zoneDemand then
			ResidentialDemand = payload.zoneDemand.Residential
			DenseResidentialDemand = payload.zoneDemand.ResDense
			CommercialDemand = payload.zoneDemand.Commercial
			DenseCommercialDemand = payload.zoneDemand.CommDense
			IndustrialDemand = payload.zoneDemand.Industrial
			DenseIndustrialDemand = payload.zoneDemand.IndusDense
		end
	end)

	-- hook server event
	RE_SocialMediaAddPost.OnClientEvent:Connect(onServerPost)

	-- CLIENT GENERATOR LOOP (preserved but disabled while server feed is on)
	if not USE_SERVER_FEED then
		task.spawn(function()
			local CheckOrder = {
				"ResidentialDemand",
				"DenseResidentialDemand",
				"CommercialDemand",
				"DenseCommercialDemand",
				"IndustrialDemand",
				"DenseIndustrialDemand",
				"All",
			}

			while true do
				if UI.Enabled then
					task.wait(RNG:NextInteger(NEW_MESSAGE_TIMER.Min, NEW_MESSAGE_TIMER.Max))
				else
					task.wait(1)
				end

				local FoundAngerMessage = false
				CheckOrder = Utility.ShuffleArray(CheckOrder)
				for _, CheckType in CheckOrder do
					if CheckType == "ResidentialDemand" and ResidentialDemand >= 0.5 then
						SocialMedia.GenerateMessage("Mad_Residential")
						FoundAngerMessage = true
						break

					elseif CheckType == "DenseResidentialDemand" and DenseResidentialDemand >= 0.5 then
						SocialMedia.GenerateMessage("Mad_DenseResidential")
						FoundAngerMessage = true
						break

					elseif CheckType == "CommercialDemand" and CommercialDemand >= 0.5 then
						SocialMedia.GenerateMessage("Mad_Commercial")
						FoundAngerMessage = true
						break

					elseif CheckType == "DenseCommercialDemand" and DenseCommercialDemand >= 0.5 then
						SocialMedia.GenerateMessage("Mad_DenseCommercial")
						FoundAngerMessage = true
						break

					elseif CheckType == "IndustrialDemand" and IndustrialDemand >= 0.5 then
						SocialMedia.GenerateMessage("Mad_Industrial")
						FoundAngerMessage = true
						break

					elseif CheckType == "DenseIndustrialDemand" and DenseIndustrialDemand >= 0.5 then
						SocialMedia.GenerateMessage("Mad_DenseIndustrial")
						FoundAngerMessage = true
						break

					elseif CheckType == "All"
						and ResidentialDemand >= 0.5
						and DenseResidentialDemand >= 0.5
						and CommercialDemand >= 0.5
						and DenseCommercialDemand >= 0.5
						and IndustrialDemand >= 0.5
						and DenseIndustrialDemand >= 0.5
					then
						SocialMedia.GenerateMessage("Mad_All")
						FoundAngerMessage = true
						break
					end
				end

				if not FoundAngerMessage then
					SocialMedia.GenerateMessage("Happy")
				end
			end
		end)
	end

	--game.UserInputService.InputBegan:Connect(function(io)
	--	if io.KeyCode == Enum.KeyCode.One then
	--		SocialMedia.Toggle()
	--	end
	--end)
end

return SocialMedia
