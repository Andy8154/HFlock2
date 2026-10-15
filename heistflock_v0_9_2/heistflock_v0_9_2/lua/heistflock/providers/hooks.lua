-- Hands parts to your own addon and nothing else. Take them in:
--   hook.Add("HeistFlock_GiveMaterial", "MyAddon", function(ply, materialId, amount, source) ... return true end)
-- See hooks_reference.lua for an example. A part no hook takes stays on the
-- ground, and the player is told so.

HeistFlock.RegisterProvider("hooks", {
	name = "Hooks only (your own addon)",

	IsAvailable = function()
		return true
	end,

	-- Only reached when no hook took the material.
	Give = function(ply, material, amount)
		HeistFlock.Log("No HeistFlock_GiveMaterial hook took " .. amount .. "x " .. material.id .. " for " .. ply:Nick())
		return false
	end,
})
