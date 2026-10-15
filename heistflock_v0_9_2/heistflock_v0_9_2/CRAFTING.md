# Heist Flock: parts and crafting

In smash mode (the default), a camera drops its parts as items when each stage breaks, and players press E to pick them up. Where a picked-up part goes is up to you. A crafting bench isn't finished yet. This is what's in the addon now, so you can build against it.

## What works today

| Piece | File | Status |
|---|---|---|
| Materials (lens, copper, PCB, gold, solar cell, scrap), each with a model | `lua/heistflock/shared/sh_materials.lua` | Done |
| Loot per stage | `Config.Stages[i].loot` in `sh_config.lua` | Done |
| Parts dropping and picking up | `lua/heistflock/server/sv_loot.lua`, `lua/entities/heistflock_part` | Done |
| "Sell for cash" provider | `lua/heistflock/providers/money.lua` | Done |
| "Hooks only" provider | `lua/heistflock/providers/hooks.lua` | Done |
| ItemStore provider | `lua/heistflock/providers/itemstore.lua` | Not finished |
| Recipe format | `lua/heistflock/shared/sh_recipes.lua` | Done (nothing uses it yet) |
| Crafting bench, menu, item delivery | | Planned |

In steps mode, turn on `Config.Crafting.Enabled` to hand each stage's parts straight to the player instead of dropping them.

## How a part reaches a player

1. A stage breaks. `HeistFlock_CanGetLoot(ply, cam, stage)` runs; return `false` to give nothing.
2. Each entry in that stage's `loot` is rolled, e.g. `{ "copper_wire", 2, 4 }` gives 2 to 4 copper wire, as one item on the ground.
3. A player presses E on it. For `Config.Parts.OwnerTime` seconds only whoever broke the stage can.
4. `HeistFlock_GiveMaterial(ply, materialId, amount, part)` runs first. Return `true` if your addon took it.
5. Otherwise it goes to `Config.Parts.Provider`. If that provider isn't available, it's sold for cash instead.
6. If nothing took it, it stays on the ground.

## Adding your own

**A material** (in any shared file):
```lua
HeistFlock.RegisterMaterial("lithium_cell", { name = "Lithium Cell", value = 150, model = "models/items/battery.mdl" })
```

**Sending every part to another addon** (server):
```lua
hook.Add("HeistFlock_GiveMaterial", "MyCrafting", function(ply, materialId, amount)
	MyCrafting.GiveResource(ply, "metal", amount)
	return true
end)
```
Set `Parts_Provider` to `"hooks"` so a part your hook doesn't take stays on the ground instead of being sold. There's a fuller example in `hooks_reference.lua`.

**A provider** (a file in `lua/heistflock/providers/`, server only):
```lua
HeistFlock.RegisterProvider("myinventory", {
	name = "My Inventory",
	IsAvailable = function() return MyInventory ~= nil end,
	Give = function(ply, material, amount)
		return MyInventory.Give(ply, "heistflock_" .. material.id, amount) == true
	end,
})
```
Then set `Config.Parts.Provider = "myinventory"`.

**A recipe** (any shared file):
```lua
HeistFlock.RegisterRecipe("signal_jammer", {
	name = "Signal Jammer",
	time = 20,
	needs = { circuit_board = 1, copper_wire = 4 },
	gives = { type = "entity", class = "heistflock_jammer" },
})
```

## Planned next

- A crafting bench entity with a menu in the same style as the admin panel.
- A Heist Flock material inventory, so crafting works without any inventory addon.
- ItemStore and other inventory providers.
- Recipe results: entities, weapons, money and custom hooks.
