-- Sells materials on the spot for their value. Needs no inventory addon,
-- so it's the fallback whenever the chosen provider isn't available.

HeistFlock.RegisterProvider("money", {
	name = "Sell for cash",

	IsAvailable = function()
		return true
	end,

	Give = function(ply, material, amount)
		local total = material.value * amount
		if total <= 0 then return true end

		-- Without DarkRP (e.g. sandbox) there's no money to add; the part is
		-- still "sold" so it doesn't stay on the ground forever.
		if ply.addMoney then
			ply:addMoney(total)
		end

		-- Counted here, when it's actually paid, so loot from abandoned or
		-- unfinished cameras shows up in the dashboard's "Paid out" too.
		HeistFlock.Stats.moneyPaid = HeistFlock.Stats.moneyPaid + total

		HeistFlock.Notify(ply, amount .. "x " .. material.name .. " sold for " .. HeistFlock.FormatMoney(total))
		return true
	end,
})
