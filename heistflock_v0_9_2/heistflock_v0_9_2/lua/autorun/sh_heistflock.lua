-- Runs automatically on the server and on every client.
-- Loads the rest of the addon from lua/heistflock/.

HeistFlock = HeistFlock or {}
HeistFlock.Version = "0.9.2"

local function loadFolder(folder, realm)
	local files = file.Find("heistflock/" .. folder .. "/*.lua", "LUA")

	for _, fileName in ipairs(files) do
		local path = "heistflock/" .. folder .. "/" .. fileName

		if realm == "shared" then
			if SERVER then AddCSLuaFile(path) end
			include(path)
		elseif realm == "server" then
			if SERVER then include(path) end
		elseif realm == "client" then
			if SERVER then AddCSLuaFile(path) end
			if CLIENT then include(path) end
		end
	end
end

loadFolder("shared", "shared") -- config must load first
loadFolder("server", "server")
loadFolder("client", "client")

print("[HeistFlock] v" .. HeistFlock.Version .. " loaded on the " .. (SERVER and "server" or "client"))
