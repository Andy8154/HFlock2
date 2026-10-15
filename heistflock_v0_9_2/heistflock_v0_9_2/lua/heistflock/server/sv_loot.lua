--[[-------------------------------------------------------------------------
	HEIST FLOCK - LOOT AND PARTS

	Each stage has a loot table (Config.Stages[i].loot). In smash mode the
	rolled parts drop from the camera as heistflock_part items that players
	pick up with E. In steps mode with crafting on, they go straight to the
	player. Either way a material is handed out the same way:

		1. The HeistFlock_GiveMaterial hook, for your own addon. Return true
		   to take it.
		2. Otherwise the provider in Config.Parts.Provider: sold for cash,
		   ItemStore, or one another addon registered.

	Providers live in lua/heistflock/providers/ and look like this:
		HeistFlock.RegisterProvider("myinventory", {
			name = "My Inventory",
			IsAvailable = function() return MyInventory ~= nil end,
			Give = function(ply, material, amount) ... return true end,
		})
	Give returns true if the player got it. A part nobody took stays on the
	ground.
---------------------------------------------------------------------------]]

local Config = HeistFlock.Config
local L = HeistFlock.L

local MAX_PARTS_PER_STAGE = 4
local PICKUP_RANGE = 96

HeistFlock.Providers = HeistFlock.Providers or {}

function HeistFlock.RegisterProvider(id, provider)
	provider.id = id
	HeistFlock.Providers[id] = provider
end

for _, fileName in ipairs(file.Find("heistflock/providers/*.lua", "LUA")) do
	include("heistflock/providers/" .. fileName)
end

-- The chosen provider, or selling for cash when it isn't available.
function HeistFlock.GetActiveProvider()
	local provider = HeistFlock.Providers[Config.Parts.Provider]
	if provider and provider.IsAvailable() then
		return provider
	end
	return HeistFlock.Providers.money
end

-- Checked once everything has loaded (other addons may add providers).
hook.Add("InitPostEntity", "HeistFlock_CheckProvider", function()
	local chosen = Config.Parts.Provider
	local provider = HeistFlock.Providers[chosen]

	if not provider then
		HeistFlock.Warn("Parts provider \"" .. tostring(chosen) .. "\" doesn't exist, so parts are sold for cash instead. Options: "
			.. table.concat(table.GetKeys(HeistFlock.Providers), ", ") .. ".")
	elseif not provider.IsAvailable() then
		HeistFlock.Warn("Parts provider \"" .. chosen .. "\" isn't available on this server, so parts are sold for cash instead.")
	end
end)

-- Rolls a stage's loot table into { { material, amount }, ... }, one entry
-- per material.
local function rollLoot(stageNumber)
	local stage = Config.Stages[stageNumber]
	local drops, byMaterial = {}, {}

	for _, entry in ipairs(stage and stage.loot or {}) do
		local materialId, low, high = entry[1], entry[2] or 1, entry[3] or entry[2] or 1
		local amount = math.random(low, math.max(low, high))

		if HeistFlock.GetMaterial(materialId) and amount > 0 then
			if byMaterial[materialId] then
				byMaterial[materialId].amount = byMaterial[materialId].amount + amount
			else
				byMaterial[materialId] = { material = materialId, amount = amount }
				table.insert(drops, byMaterial[materialId])
			end
		end
	end

	return drops
end

-- Gives a material to a player: your own addon first (the
-- HeistFlock_GiveMaterial hook), then the provider. Never both: the provider
-- only runs when no hook took it. source is the part entity, or "stage" in
-- steps mode.
-- Returns a result and the cash it sold for:
--   "given"    the player got it
--   "refused"  nothing took it (e.g. the hooks provider with no hook)
--   "error"    a hook or provider errored. It may have given part of the
--              reward before failing, so callers treat it as used up.
local function giveMaterial(ply, material, amount, source)
	if hook.Run("HeistFlock_GiveMaterial", ply, material.id, amount, source) then
		return "given", 0
	end

	local provider = HeistFlock.GetActiveProvider()
	if provider.Give(ply, material, amount) ~= true then return "refused", 0 end
	return "given", provider.id == "money" and material.value * amount or 0
end

function HeistFlock.GiveMaterial(ply, materialId, amount, source)
	local material = HeistFlock.GetMaterial(materialId)
	if not material or not isnumber(amount) or amount <= 0 or not IsValid(ply) then return "refused", 0 end

	local ok, result, value = pcall(giveMaterial, ply, material, amount, source)
	if not ok then
		HeistFlock.Warn("Giving " .. amount .. "x " .. materialId .. " failed (provider \"" .. Config.Parts.Provider
			.. "\" or a HeistFlock_GiveMaterial hook): " .. tostring(result))
		return "error", 0
	end
	return result, value
end

-- Steps mode -----------------------------------------------------------------

-- Called by the camera after each stage. Does nothing unless crafting is on.
-- Returns what was handed out: { { material, amount, value }, ... }, where
-- value is the cash it sold for (only with the money provider).
function HeistFlock.GiveStageLoot(ply, cam, stageNumber)
	if not Config.Crafting.Enabled then return {} end
	if hook.Run("HeistFlock_CanGetLoot", ply, cam, stageNumber) == false then return {} end

	local drops = rollLoot(stageNumber)
	for _, drop in ipairs(drops) do
		local result, value = HeistFlock.GiveMaterial(ply, drop.material, drop.amount, "stage")
		drop.value = value
		if result ~= "given" then
			HeistFlock.Log(ply:Nick() .. " didn't get " .. drop.amount .. "x " .. drop.material .. " (" .. result .. ")")
		end
	end

	if #drops > 0 then
		hook.Run("HeistFlock_LootGiven", ply, drops)
		HeistFlock.Log(ply:Nick() .. " got loot from stage " .. stageNumber)
	end

	return drops
end

-- "3x Copper Wire, 1x Circuit Board" from a list of drops.
function HeistFlock.SummarizeDrops(drops)
	local totals, order = {}, {}
	for _, drop in ipairs(drops) do
		if not totals[drop.material] then table.insert(order, drop.material) end
		totals[drop.material] = (totals[drop.material] or 0) + drop.amount
	end

	local parts = {}
	for _, materialId in ipairs(order) do
		local material = HeistFlock.GetMaterial(materialId)
		table.insert(parts, totals[materialId] .. "x " .. (material and material.name or materialId))
	end
	return table.concat(parts, ", ")
end

-- Whether the flat payout should still be paid (steps mode).
function HeistFlock.ShouldPayFlatPayout()
	return not (Config.Crafting.Enabled and Config.Crafting.ReplacePayout)
end

-- Smash mode: parts on the ground ------------------------------------------------

HeistFlock.LooseParts = HeistFlock.LooseParts or {} -- oldest first

-- Parts take themselves off the list when removed (ENT:OnRemove), so it
-- never holds removed entities for long.
function HeistFlock.ForgetPart(part)
	table.RemoveByValue(HeistFlock.LooseParts, part)
end

-- Keeps the list to Config.Parts.MaxLoose by removing the oldest parts.
local function makeRoomForPart()
	local parts = HeistFlock.LooseParts
	for i = #parts, 1, -1 do
		if not IsValid(parts[i]) then table.remove(parts, i) end
	end

	while #parts >= Config.Parts.MaxLoose do
		local oldest = table.remove(parts, 1)
		if IsValid(oldest) then
			oldest.Collected = true -- going away; nobody can pick it up this tick
			oldest:Remove()
		end
	end
end

-- Drops a finished stage's parts from the camera head. breaker is the
-- player who landed the stage's last hit; the parts are theirs for a while.
function HeistFlock.DropStageParts(cam, stageNumber, breaker)
	if hook.Run("HeistFlock_CanGetLoot", breaker, cam, stageNumber) == false then return {} end

	local drops = rollLoot(stageNumber)
	local origin = HeistFlock.GetHousingPos(cam) + cam:GetForward() * 6

	for i = 1, math.min(#drops, MAX_PARTS_PER_STAGE) do
		makeRoomForPart()

		local part = ents.Create("heistflock_part")
		if not IsValid(part) then break end

		part:SetupPart(drops[i].material, drops[i].amount, breaker)
		part:SetPos(origin + VectorRand() * 3)
		part:SetAngles(AngleRand())
		part:Spawn()

		local phys = part:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:SetVelocity(cam:GetForward() * 70 + VectorRand() * 40 + Vector(0, 0, 90))
			phys:AddAngleVelocity(VectorRand() * 200)
		end

		table.insert(HeistFlock.LooseParts, part)
	end

	return drops
end

-- A player pressed E on a part.
function HeistFlock.CollectPart(ply, part)
	if part.Collected or not ply:Alive() or ply:InVehicle() then return end
	if DarkRP and ply.isArrested and ply:isArrested() then return end

	local materialId, amount = part:GetMaterialId(), part:GetAmount()
	local material = HeistFlock.GetMaterial(materialId)
	if not material then
		part:Remove()
		return
	end

	local owner = part:GetPartOwner()
	local reservedFor = part:GetOwnerUntil() - CurTime()
	if IsValid(owner) and owner ~= ply and reservedFor > 0 then
		HeistFlock.Notify(ply, L("part_reserved", { name = owner:Nick(), seconds = math.ceil(reservedFor) }), true)
		return
	end

	if hook.Run("HeistFlock_CanCollectPart", ply, part) == false then return end

	-- Marked before anything is handed out, so nothing (another press, a hook
	-- that collects parts itself) can get the same part twice.
	part.Collected = true

	if Config.Parts.PoliceConfiscate and DarkRP and ply.isCP and ply:isCP() then
		part:Remove()
		HeistFlock.Notify(ply, L("part_confiscated", { part = material.name }))
		HeistFlock.Log(ply:Nick() .. " confiscated " .. amount .. "x " .. materialId)
		hook.Run("HeistFlock_PartConfiscated", ply, materialId, amount)
		return
	end

	local result, value = HeistFlock.GiveMaterial(ply, materialId, amount, part)

	if result == "refused" then
		part.Collected = nil -- nothing was given, so it stays on the ground
		HeistFlock.Notify(ply, L("part_not_taken"), true)
		HeistFlock.Log(ply:Nick() .. " couldn't pick up " .. amount .. "x " .. materialId .. ": nothing took it (provider \""
			.. HeistFlock.GetActiveProvider().id .. "\")")
		return
	end

	-- "given", or "error": an error may have paid out part of it already, so
	-- the part is used up either way. The error is on the Diagnostics page.
	part:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 60)
	part:Remove()

	if result == "error" then
		HeistFlock.Notify(ply, L("part_error"), true)
		return
	end

	HeistFlock.Stats.partsCollected = (HeistFlock.Stats.partsCollected or 0) + amount
	hook.Run("HeistFlock_PartCollected", ply, materialId, amount, value)
	HeistFlock.Log(ply:Nick() .. " picked up " .. amount .. "x " .. materialId
		.. (value > 0 and (" and sold it for " .. HeistFlock.FormatMoney(value)) or ""))
end

-- E on a part. Done here rather than in ENT:Use, so prop protection addons
-- that block using unowned entities don't stop players picking parts up.
hook.Add("KeyPress", "HeistFlock_PickUpPart", function(ply, key)
	if key ~= IN_USE then return end

	local eyes = ply:EyePos()
	local trace = util.TraceHull({
		start = eyes,
		endpos = eyes + ply:GetAimVector() * PICKUP_RANGE,
		mins = Vector(-3, -3, -3),
		maxs = Vector(3, 3, 3),
		filter = ply,
	})

	local part = trace.Entity
	if IsValid(part) and part:GetClass() == "heistflock_part" then
		if HeistFlock.IsThrottled(ply, "pickup", 0.2) then return end
		HeistFlock.CollectPart(ply, part)
	end
end)
