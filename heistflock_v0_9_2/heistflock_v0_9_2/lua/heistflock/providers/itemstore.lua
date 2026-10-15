-- ItemStore inventory. NOT FINISHED.
--
-- Putting parts into ItemStore needs an ItemStore item class for each
-- material, written against ItemStore's own code, which this addon was not
-- built with. Until that's done this provider reports itself unavailable,
-- and parts are sold for cash instead (Diagnostics shows a warning).
--
-- In the meantime, an ItemStore server can use the "hooks" provider and
-- add the parts itself from a HeistFlock_GiveMaterial hook.

HeistFlock.RegisterProvider("itemstore", {
	name = "ItemStore (not finished)",

	IsAvailable = function()
		return false
	end,

	Give = function(ply, material, amount)
		return false
	end,
})
