-- Client side of the server's settings and status info.

-- Settings: each player asks once their game has loaded.
hook.Add("InitPostEntity", "HeistFlock_RequestConfig", function()
	net.Start("HeistFlock_RequestConfig")
	net.SendToServer()
end)

net.Receive("HeistFlock_SyncConfig", function()
	HeistFlock.ApplyValues(net.ReadTable())

	-- Overrides from the server's config.json that change what players see.
	local shared = net.ReadTable()
	local Config = HeistFlock.Config
	if isstring(shared.Language) and HeistFlock.Languages[shared.Language] then
		Config.Language = shared.Language
	end
	if istable(shared.StageNames) then
		for i, name in ipairs(shared.StageNames) do
			if Config.Stages[i] and isstring(name) then Config.Stages[i].name = name end
		end
		HeistFlock.RefreshStageDescriptions()
	end
	if isstring(shared.FontOverride) and shared.FontOverride ~= Config.FontOverride then
		Config.FontOverride = shared.FontOverride
		HeistFlock.CreateFonts()
	end

	-- A new camera model changes the collision box and draw size.
	for _, cam in ipairs(ents.FindByClass("heistflock_camera")) do
		cam:SetupCollisions()
		cam:UpdateRenderBounds()
	end

	hook.Run("HeistFlock_ConfigChanged")
end)

-- Status info (admins only): cameras, warnings and server checks.
-- Used by the admin menu and the camera markers.
function HeistFlock.RequestServerInfo()
	net.Start("HeistFlock_RequestInfo")
	net.SendToServer()
end

net.Receive("HeistFlock_Info", function()
	local size = net.ReadUInt(32)
	local json = util.Decompress(net.ReadData(size))
	local info = json and util.JSONToTable(json)
	if not istable(info) then return end

	-- Positions and angles travel as text in the JSON; make sure they're
	-- real vectors and angles again.
	for _, cam in ipairs(info.cameras or {}) do
		if not isvector(cam.pos) then cam.pos = Vector(string.Trim(tostring(cam.pos), "[]")) end
		if not isangle(cam.ang) then cam.ang = Angle(string.Trim(tostring(cam.ang), "{}")) end
	end

	HeistFlock.ServerInfo = info

	-- How far the server's clock is from ours, so "4m ago" can keep counting
	-- between updates without rebuilding the page.
	HeistFlock.ServerClockOffset = (HeistFlock.ServerInfo.serverTime or os.time()) - os.time()

	hook.Run("HeistFlock_InfoUpdated")
end)

-- The server's os.time() right now.
function HeistFlock.ServerNow()
	return os.time() + (HeistFlock.ServerClockOffset or 0)
end
