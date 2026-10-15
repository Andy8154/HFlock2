--[[-------------------------------------------------------------------------
	HEIST FLOCK - MATERIALS

	The parts a camera drops (Config.Stages[i].loot). Each has:
		name   shown to players
		value  $ each when sold (the "money" provider)
		model  what it looks like on the ground, from base game content
		color  optional tint for the model

	Other addons can add their own:
		HeistFlock.RegisterMaterial("lithium_cell", {
			name  = "Lithium Cell",
			value = 150,
			model = "models/items/battery.mdl",
		})

	See lua/heistflock/crafting_guide.lua for more.
---------------------------------------------------------------------------]]

HeistFlock.Materials = HeistFlock.Materials or {}

-- Used when a material has no model, or its model is missing on the server.
HeistFlock.FallbackPartModel = "models/gibs/metal_gib1.mdl"

function HeistFlock.RegisterMaterial(id, data)
	assert(isstring(id) and id ~= "", "HeistFlock.RegisterMaterial: id must be a non-empty string")
	assert(istable(data) and isstring(data.name), "HeistFlock.RegisterMaterial: data needs a name")

	data.id = id
	data.value = tonumber(data.value) or 0
	data.model = isstring(data.model) and data.model or HeistFlock.FallbackPartModel
	HeistFlock.Materials[id] = data

	return data
end

function HeistFlock.GetMaterial(id)
	return HeistFlock.Materials[id]
end

-- The defaults, one for each part of the built-in camera.
HeistFlock.RegisterMaterial("camera_lens", { name = "Camera Lens", value = 120,
	model = "models/dav0r/camera.mdl" })
HeistFlock.RegisterMaterial("copper_wire", { name = "Copper Wire", value = 60,
	model = "models/props_c17/pulleywheels_small01.mdl", color = Color(205, 125, 60) })
HeistFlock.RegisterMaterial("circuit_board", { name = "Circuit Board", value = 250,
	model = "models/hunter/plates/plate025x025.mdl", color = Color(30, 110, 50) })
HeistFlock.RegisterMaterial("gold_contacts", { name = "Gold Contacts", value = 140,
	model = "models/gibs/metal_gib4.mdl", color = Color(230, 180, 60) })
HeistFlock.RegisterMaterial("solar_cell", { name = "Solar Cell", value = 180,
	model = "models/hunter/plates/plate025x05.mdl", color = Color(26, 44, 92) })
HeistFlock.RegisterMaterial("scrap_metal", { name = "Scrap Metal", value = 25,
	model = "models/gibs/metal_gib2.mdl" })
