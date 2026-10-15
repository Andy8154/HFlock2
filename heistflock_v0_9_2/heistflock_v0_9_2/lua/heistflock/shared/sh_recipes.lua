--[[-------------------------------------------------------------------------
	HEIST FLOCK - RECIPES (crafting groundwork, not active yet)

	Recipes turn materials from stripped cameras into items. Nothing uses
	these yet: the crafting bench, its menu and item delivery are planned for
	a later version. This file fixes the format so recipes written now keep
	working once crafting ships.

	A recipe:
		HeistFlock.RegisterRecipe("signal_jammer", {
			name     = "Signal Jammer",
			time     = 20,                                 -- seconds to craft
			needs    = { circuit_board = 1, copper_wire = 4 },
			gives    = { type = "entity", class = "heistflock_jammer" },
			canCraft = function(ply) return true end,      -- optional extra check
		})

	"gives" types planned: "entity" (spawns an entity), "weapon" (gives a
	weapon), "money", and "hook" (runs HeistFlock_CraftedItem for your addon).

	See lua/heistflock/crafting_guide.lua for the full plan.
---------------------------------------------------------------------------]]

HeistFlock.Recipes = HeistFlock.Recipes or {}

function HeistFlock.RegisterRecipe(id, data)
	assert(isstring(id) and id ~= "", "HeistFlock.RegisterRecipe: id must be a non-empty string")
	assert(istable(data) and istable(data.needs) and istable(data.gives), "HeistFlock.RegisterRecipe: needs and gives are required")

	for materialId in pairs(data.needs) do
		if not HeistFlock.GetMaterial(materialId) then
			ErrorNoHalt("[HeistFlock] Recipe " .. id .. " needs unknown material " .. tostring(materialId) .. "\n")
		end
	end

	data.id = id
	data.time = tonumber(data.time) or 10
	HeistFlock.Recipes[id] = data

	return data
end

function HeistFlock.GetRecipe(id)
	return HeistFlock.Recipes[id]
end

-- Example recipes, so the format is clear. Harmless until crafting ships.
HeistFlock.RegisterRecipe("scrap_bundle", {
	name = "Scrap Bundle",
	time = 5,
	needs = { copper_wire = 3, gold_contacts = 1 },
	gives = { type = "money", amount = 500 },
})

HeistFlock.RegisterRecipe("camera_kit", {
	name = "Camera Repair Kit",
	time = 15,
	needs = { camera_lens = 1, circuit_board = 1, copper_wire = 2 },
	gives = { type = "hook", item = "camera_kit" },
})
