local AllSounds = {

	["UI"] = {
		["SmallClick"] = {
			SoundId = "rbxassetid://4048494255",
			Volume = 0.5,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
	},
	["Misc"] = {
		["Transition"] = {
			SoundId = "rbxassetid://128533327576149",
			Volume = 1.0,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Counting"] = {
			SoundId = "rbxassetid://4612384022",
			Volume = 0.8,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Woosh1"] = {
			SoundId = "rbxassetid://5530025800",
			Volume = 0.8,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Applause"] = {
			SoundId = "rbxassetid://79849708789930",
			Volume = 2.8,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Death"] = {
			SoundId = "rbxassetid://8223773319",
			Volume = 0.5,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Scream"] = { -- Lego Yoda
			SoundId = "rbxassetid://2977012439",
			Volume = 0.6,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Cha-ching"] = {
			SoundId = "rbxassetid://4614051739",
			Volume = 0.3,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Ka-ching"] = {
			SoundId = "rbxassetid://1210852193",
			Volume = 0.7,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1,
		},
		["Awarded"] = {
			SoundId = "rbxassetid://3269373680",
			Volume = 0.3,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["PurchaseFail"] = {
			SoundId = "rbxassetid://4612385808",
			Volume = 0.2,
			RollOffMaxDistance = 1,
			RollOffMinDistance = 1
		},
		["Poof"] = {
			SoundId = "rbxassetid://769380905",
			Volume = 1,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Build"] = {
			SoundId = "rbxassetid://6339604994",
			Volume = 0.5,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["CarHorn"] = {
			SoundId = "rbxassetid://5945905639",
			Volume = 0.2,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Siren"] = {
			SoundId = "rbxassetid://9065275258",
			Volume = 0.2,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Construction"] = {
			SoundId = "rbxassetid://922634581",
			Volume = 0.2,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["CarAmbiance"] = {
			SoundId = "rbxassetid://115479531446660",
			Volume = 0.5,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Upgrade"] = {
			SoundId = "rbxassetid://90007756301452",
			Volume = 0.5,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Downgrade"] = {
			SoundId = "rbxassetid://100910483233315",
			Volume = 0.5,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Error"] = {
			SoundId = "rbxassetid://91800555512422",
			Volume = 0.5,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Windmill"] = {
			SoundId = "rbxassetid://8506795592",
			Volume = 0.3,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["AirplaneLand"] = {
			SoundId = "rbxassetid://5037983034",
			Volume = 0.5,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		},
		["Factory"] = {
			SoundId = "rbxassetid://125290674958012",
			Volume = 0.2,
			RollOffMaxDistance = 500,
			RollOffMinDistance = 20
		}

	},
}

for SoundCategory, Data in AllSounds do
	for SoundName, SubData in Data do
		assert(SubData["SoundId"] ~= nil, "Missing SoundId Key for Sound ["..SoundCategory.."/"..SoundName.."]")
		assert(SubData["Volume"] ~= nil, "Missing Volume Key for Sound ["..SoundCategory.."/"..SoundName.."]")
		--assert(SubData["RollOffMaxDistance"] ~= nil, "Missing RollOffMaxDistance Key for Sound ["..SoundCategory.."/"..SoundName.."]")
		--assert(SubData["RollOffMinDistance"] ~= nil, "Missing RollOffMinDistance Key for Sound ["..SoundCategory.."/"..SoundName.."]")
	end
end

return AllSounds