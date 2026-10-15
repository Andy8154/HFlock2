-- The admin menu. Open with !heistflock in chat or heistflock_menu in console.
--
-- Pages: Dashboard, Cameras, Settings, Access, Diagnostics. Which pages and
-- buttons show depends on the player's access (sh_permissions.lua):
-- View sees Dashboard, Cameras and Diagnostics; Place also gets the camera
-- buttons; Manage gets everything. The server checks every action again.
-- Settings and job changes collect as unsaved changes until Save is pressed,
-- then go to the server, which checks them, saves them and sends them to
-- every player.

local Config = HeistFlock.Config
local Theme = HeistFlock.Theme
local S = HeistFlock.S
local UI = HeistFlock.UI

local INFO_REFRESH_INTERVAL = 5

local frame
local currentPage = "dashboard"
local cameraFilter = "all"
local jobSearch = ""
local pendingChanges = {} -- setting id -> new value that hasn't been saved yet
local showPage            -- defined further down

local function notify(message)
	chat.AddText(Theme.accent, "[Heist Flock] ", Theme.text, message)
end

local function can(level)
	return HeistFlock.HasAccess(LocalPlayer(), level)
end

-- Talking to the server ------------------------------------------------------

local function sendAction(action, cameraId)
	net.Start("HeistFlock_Action")
	net.WriteString(action)
	net.WriteUInt(cameraId or 0, 16)
	net.SendToServer()
end

-- Place a new camera (cameraId nil) or move one, with a preview. The menu
-- hides while you aim, and comes back when you're done.
local function startPlacing(cameraId)
	if IsValid(frame) then frame:Hide() end
	HeistFlock.StartPlacement(cameraId, function()
		if IsValid(frame) then
			frame:Show()
			frame:MakePopup()
		end
	end)
end

local function confirm(question, yesText, onYes)
	Derma_Query(question, "Heist Flock", yesText, onYes, "Cancel")
end

-- Unsaved changes ------------------------------------------------------------

local function valuesEqual(a, b)
	if istable(a) and istable(b) then
		return table.concat(a, ",") == table.concat(b, ",")
	end
	return a == b
end

-- The unsaved value if there is one, otherwise the saved one.
local function getValue(setting)
	local pending = pendingChanges[setting.id]
	if pending ~= nil then return pending end
	return HeistFlock.GetSetting(setting)
end

local function setPending(setting, value)
	if setting.type == "string" then
		value = string.Trim(value) -- the server trims too, so match it
	end

	if valuesEqual(value, HeistFlock.GetSetting(setting)) then
		pendingChanges[setting.id] = nil
	else
		pendingChanges[setting.id] = value
	end
end

local function countPending()
	return table.Count(pendingChanges)
end

local function savePending()
	if countPending() == 0 then return end

	net.Start("HeistFlock_ChangeSettings")
	net.WriteTable(pendingChanges)
	net.SendToServer()
	-- The list clears itself when the server sends the new settings back.
end

local function revertPending()
	pendingChanges = {}
	showPage(currentPage)
end

-- Layout pieces ----------------------------------------------------------------

-- Puts a scroll panel back where it was after its contents were rebuilt.
-- A freshly built page takes a few frames to lay out (and until then it's
-- too short to scroll), so keep setting it for a moment instead of once.
-- Think is wrapped only once per panel; later calls just move the target.
local function restoreScroll(scroll, amount)
	if amount <= 0 then return end

	scroll.RestoreTarget = amount
	scroll.RestoreUntil = SysTime() + 0.3
	if scroll.RestoreWrapped then return end
	scroll.RestoreWrapped = true

	local oldThink = scroll.Think
	scroll.Think = function(self, ...)
		if self.RestoreTarget and SysTime() < self.RestoreUntil then
			self:GetVBar():SetScroll(self.RestoreTarget)
		else
			self.RestoreTarget = nil
		end
		if oldThink then oldThink(self, ...) end
	end
end

local function makeScroll(parent)
	local scroll = vgui.Create("DScrollPanel", parent)
	scroll:Dock(FILL)
	UI.StyleScroll(scroll)
	scroll:GetCanvas():DockPadding(0, 0, S(8), 0)
	frame.mainScroll = scroll
	return scroll
end

-- A small uppercase heading above a group.
local function makeHeading(parent, text, topMargin)
	local heading = parent:Add("DPanel")
	heading:Dock(TOP)
	heading:DockMargin(0, topMargin or S(20), 0, S(8))
	heading:SetTall(S(14))
	heading.Paint = function(self, w, h)
		draw.SimpleText(string.upper(text), "HeistFlock.Label", 0, h / 2, Theme.textFaint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return heading
end

-- A bordered box that grows to fit the rows added to it.
local function makeGroup(parent)
	local group = parent:Add("DPanel")
	group:Dock(TOP)
	group.Paint = function(self, w, h)
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, Theme.line)
	end
	group.PerformLayout = function(self)
		self:SizeToChildren(false, true)
	end
	group.RowCount = 0
	return group
end

-- A row inside a group: title (with optional help) on the left, a control on the right.
local function makeRow(group, title, help, control, isChanged)
	group.RowCount = group.RowCount + 1
	local isFirst = group.RowCount == 1

	local row = group:Add("DPanel")
	row:Dock(TOP)
	row:SetTall(S(50))

	local helpIcon = help and UI.Help(row, help)
	if control then control:SetParent(row) end

	row.Paint = function(self, w, h)
		if not isFirst then
			surface.SetDrawColor(Theme.line)
			surface.DrawRect(S(14), 0, w - S(28), 1)
		end
		if isChanged and isChanged() then
			draw.RoundedBox(0, 0, S(10), S(2), h - S(20), Theme.accent)
		end
		draw.SimpleText(title, "HeistFlock.Body", S(16), h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	row.PerformLayout = function(self, w, h)
		if helpIcon then
			surface.SetFont("HeistFlock.Body")
			local titleW = surface.GetTextSize(title)
			helpIcon:SetPos(S(16) + titleW + S(8), (h - helpIcon:GetTall()) / 2)
		end
		if control then
			control:SetPos(w - control:GetWide() - S(14), (h - control:GetTall()) / 2)
		end
	end

	return row
end

-- A row of text: label on the left, value on the right.
local function makeInfoRow(group, label, value, valueColor)
	local row = makeRow(group, label)
	local basePaint = row.Paint
	row.Paint = function(self, w, h)
		basePaint(self, w, h)
		draw.SimpleText(tostring(value), "HeistFlock.Mono", w - S(16), h / 2, valueColor or Theme.textDim,
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	return row
end

local function makeToolbar(parent)
	local toolbar = parent:Add("DPanel")
	toolbar:Dock(TOP)
	toolbar:DockMargin(0, 0, 0, S(14))
	toolbar:SetTall(S(34))
	toolbar:SetPaintBackground(false)
	return toolbar
end

local function addToToolbar(toolbar, control, onRight)
	control:SetParent(toolbar)
	control:Dock(onRight and RIGHT or LEFT)
	control:DockMargin(onRight and S(8) or 0, 0, onRight and 0 or S(8), 0)
	return control
end

-- A toggle with a label next to it, for toolbars.
local function makeLabeledToggle(parent, text, value, onChange)
	local panel = vgui.Create("DPanel", parent)
	panel:SetPaintBackground(false)

	surface.SetFont("HeistFlock.Small")
	local textW = surface.GetTextSize(text)
	local toggle = UI.Toggle(panel, value, onChange)

	panel:SetSize(toggle:GetWide() + S(10) + textW, S(34))
	toggle:SetPos(0, (S(34) - toggle:GetTall()) / 2)
	panel.Paint = function(self, w, h)
		draw.SimpleText(text, "HeistFlock.Small", toggle:GetWide() + S(10), h / 2, Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return panel
end

local function makeEmptyState(parent, icon, title, text)
	local panel = parent:Add("DPanel")
	panel:Dock(TOP)
	panel:SetTall(S(180))
	panel.Paint = function(self, w, h)
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, Theme.line)
		HeistFlock.DrawIcon(icon, w / 2 - S(16), h / 2 - S(52), S(32), Theme.textFaint)
		draw.SimpleText(title, "HeistFlock.Heading", w / 2, h / 2 + S(4), Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(text, "HeistFlock.Small", w / 2, h / 2 + S(28), Theme.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	return panel
end

local function makeLoading(parent)
	return makeEmptyState(parent, "refresh", "Loading", "Getting the latest from the server.")
end

-- A strip of stats split by thin lines: { { label, value, color }, ... }
local function makeStatStrip(parent, stats)
	local strip = parent:Add("DPanel")
	strip:Dock(TOP)
	strip:SetTall(S(84))
	strip.Paint = function(self, w, h)
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, Theme.line)
		local cellW = w / #stats

		for i, stat in ipairs(stats) do
			local x = (i - 1) * cellW
			if i > 1 then
				surface.SetDrawColor(Theme.line)
				surface.DrawRect(x, S(16), 1, h - S(32))
			end
			draw.SimpleText(string.upper(stat[1]), "HeistFlock.Label", x + S(18), S(18), Theme.textFaint)
			draw.SimpleText(tostring(stat[2]), "HeistFlock.MonoBig", x + S(18), S(34), stat[3] or Theme.text)
		end
	end
	return strip
end

-- A bar along the bottom with Save and Revert for unsaved changes.
local function makeSaveBar(parent)
	local bar = vgui.Create("DPanel", parent)
	bar:Dock(BOTTOM)
	bar:DockMargin(0, S(12), 0, 0)
	bar:SetTall(S(52))

	local saveButton = UI.Button(bar, "Save changes", savePending, { style = "primary", icon = "save" })
	local revertButton = UI.Button(bar, "Revert", revertPending, { style = "ghost" })

	bar.Paint = function(self, w, h)
		local count = countPending()
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, count > 0 and ColorAlpha(Theme.accent, 120) or Theme.line)

		if count > 0 then
			draw.RoundedBox(S(4), S(16), h / 2 - S(4), S(8), S(8), Theme.accent)
			draw.SimpleText(count .. (count == 1 and " unsaved change" or " unsaved changes"), "HeistFlock.Body",
				S(32), h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			draw.SimpleText("No unsaved changes", "HeistFlock.Body", S(16), h / 2, Theme.textFaint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	bar.PerformLayout = function(self, w, h)
		saveButton:SetPos(w - saveButton:GetWide() - S(9), (h - saveButton:GetTall()) / 2)
		revertButton:SetPos(w - saveButton:GetWide() - revertButton:GetWide() - S(15), (h - revertButton:GetTall()) / 2)
	end

	bar.Think = function()
		local nothing = countPending() == 0
		saveButton:SetDisabled(nothing)
		revertButton:SetDisabled(nothing)
	end

	return bar
end

-- Tables: a header row and rows with fixed column widths.
-- columns = { { title, width (0 = fill) }, ... }
local function columnPositions(columns, totalWidth)
	local fixed, fillCount = 0, 0
	for _, column in ipairs(columns) do
		if column[2] == 0 then fillCount = fillCount + 1 else fixed = fixed + S(column[2]) end
	end
	local fillWidth = math.max((totalWidth - fixed - S(32)) / math.max(fillCount, 1), 0)

	local positions, x = {}, S(16)
	for i, column in ipairs(columns) do
		positions[i] = x
		x = x + (column[2] == 0 and fillWidth or S(column[2]))
	end
	return positions
end

local function makeTableHeader(parent, columns)
	local header = parent:Add("DPanel")
	header:Dock(TOP)
	header:SetTall(S(32))
	header.Paint = function(self, w, h)
		local positions = columnPositions(columns, w)
		for i, column in ipairs(columns) do
			draw.SimpleText(string.upper(column[1]), "HeistFlock.Label", positions[i], h / 2, Theme.textFaint, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		surface.SetDrawColor(Theme.line)
		surface.DrawRect(0, h - 1, w, 1)
	end
	return header
end

-- Camera info ------------------------------------------------------------------

-- "active" covers someone working on it (steps) and partly broken (smash).
local function getCameraState(cam)
	if cam.stage >= #Config.Stages then return "stripped" end
	if cam.worker ~= "" or cam.stage > 0 or (cam.hits or 0) > 0 then return "active" end
	return "ready"
end

local function countCameras(cameras)
	local counts = { all = #cameras, ready = 0, active = 0, stripped = 0 }
	for _, cam in ipairs(cameras) do
		local state = getCameraState(cam)
		counts[state] = counts[state] + 1
	end
	return counts
end

local STATE_LOOKS = {
	ready    = { "READY", Theme.accent },
	active   = { "IN PROGRESS", Theme.amber },
	damaged  = { "DAMAGED", Theme.amber },
	stripped = { "STRIPPED", Theme.red },
}

-- One plain sentence about who can strip cameras.
local function describeAccess()
	local jobs = Config.Jobs
	local text

	if Config.JobMode == "whitelist" then
		text = #jobs == 0 and "Nobody (empty whitelist)" or ("Only " .. table.concat(jobs, ", "))
	else
		text = #jobs == 0 and "Every job" or ("All except " .. table.concat(jobs, ", "))
	end

	if Config.BlockPolice then
		text = text .. ", no police"
	end
	return text
end

-- Pages --------------------------------------------------------------------------

local ACTIVITY_COLORS = { strip = Theme.accent, fail = Theme.red, wanted = Theme.amber, alpr = Theme.amber, admin = Theme.textDim }

local function buildDashboard(page)
	local info = HeistFlock.ServerInfo
	local scroll = makeScroll(page)

	if not info then
		makeLoading(scroll)
		return
	end

	local counts = countCameras(info.cameras)
	makeHeading(scroll, "Cameras", 0)
	makeStatStrip(scroll, {
		{ "On the map", counts.all },
		{ "Ready", counts.ready, Theme.accent },
		{ "Damaged", counts.active, counts.active > 0 and Theme.amber or nil },
		{ "Stripped", counts.stripped, counts.stripped > 0 and Theme.red or nil },
	})

	makeHeading(scroll, "This session")
	if Config.StripMode == "smash" then
		makeStatStrip(scroll, {
			{ "Cameras smashed", info.stats.camerasStripped },
			{ "Paid out", HeistFlock.FormatMoney(info.stats.moneyPaid) },
			{ "Parts picked up", info.stats.partsCollected or 0 },
			{ "Alarms", info.stats.alarms or 0, (info.stats.alarms or 0) > 0 and Theme.red or nil },
		})
	else
		makeStatStrip(scroll, {
			{ "Cameras stripped", info.stats.camerasStripped },
			{ "Paid out", HeistFlock.FormatMoney(info.stats.moneyPaid) },
			{ "Checks passed", info.stats.checksPassed },
			{ "Checks failed", info.stats.checksFailed },
		})
	end

	makeHeading(scroll, "Plate scanning")
	local scanningCount = 0
	for _, cam in ipairs(info.cameras) do
		if cam.scanning then scanningCount = scanningCount + 1 end
	end
	makeStatStrip(scroll, {
		{ "Cameras reading", Config.ALPR.Enabled and (scanningCount .. " / " .. #info.cameras) or "Off" },
		{ "Plates read", info.stats.platesRead or 0 },
		{ "Wanted hits", info.stats.alprHits or 0, (info.stats.alprHits or 0) > 0 and Theme.amber or nil },
		{ "Plates from", info.plateSource ~= "" and info.plateSource or "-" },
	})

	-- Two columns: activity on the left, actions and setup on the right.
	local columns = scroll:Add("DPanel")
	columns:Dock(TOP)
	columns:DockMargin(0, S(20), 0, 0)
	columns:SetPaintBackground(false)
	columns:SetTall(S(470))

	local right = vgui.Create("DPanel", columns)
	right:Dock(RIGHT)
	right:SetWide(S(300))
	right:DockMargin(S(16), 0, 0, 0)
	right:SetPaintBackground(false)

	local left = vgui.Create("DPanel", columns)
	left:Dock(FILL)
	left:SetPaintBackground(false)

	makeHeading(left, "Activity", 0)
	local feed = makeGroup(left)
	if #info.activity == 0 then
		makeRow(feed, "Nothing yet. Smashed cameras, alarms and admin changes show up here.")
	else
		for i = 1, math.min(#info.activity, 7) do
			local entry = info.activity[i]
			local row = makeRow(feed, "")
			local basePaint = row.Paint
			row.Paint = function(self, w, h)
				basePaint(self, w, h)
				draw.RoundedBox(S(3), S(16), h / 2 - S(3), S(6), S(6), ACTIVITY_COLORS[entry.kind] or Theme.textDim)
				draw.SimpleText(entry.text, "HeistFlock.Body", S(32), h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				draw.SimpleText(HeistFlock.FormatAgo(HeistFlock.ServerNow() - entry.time), "HeistFlock.MonoSm", w - S(16), h / 2,
					Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		end
	end

	makeHeading(right, "Quick actions", 0)
	local actions = makeGroup(right)
	if can("place") then
		makeRow(actions, "Place a camera", nil, UI.IconButton(actions, "plus", "Shows a preview to aim with; click to place", function()
			startPlacing()
		end))
	end
	makeRow(actions, "Show all on map", nil, UI.Toggle(actions, HeistFlock.IsShowingAllCameras(), HeistFlock.SetShowAllCameras))
	if can("place") then
		local saveRow = makeRow(actions, "Save cameras now", nil, UI.IconButton(actions, "save", "Cameras also save on their own", function()
			sendAction("save")
		end))
		UI.SetTooltip(saveRow, "Saved to " .. info.cameraSavePath)
	end

	makeHeading(right, "Setup")
	local setup = makeGroup(right)
	if Config.StripMode == "smash" then
		local totalHits = 0
		for _, stage in ipairs(Config.Stages) do totalHits = totalHits + stage.hits end
		makeInfoRow(setup, "Mode", "Smash, " .. totalHits .. " hits")
		makeInfoRow(setup, "Bonus", HeistFlock.FormatMoney(Config.Payout))
		makeInfoRow(setup, "Parts", info.partsProvider .. ", " .. info.looseParts .. " out")
	else
		makeInfoRow(setup, "Mode", "Hands-on steps")
		makeInfoRow(setup, "Payout", HeistFlock.FormatMoney(Config.Payout))
		makeInfoRow(setup, "Checks", Config.SkillChecks and (Config.SkillChecksPerCamera .. " per camera") or "Off")
	end
	local accessRow = makeRow(setup, "Access")
	UI.SetTooltip(accessRow, describeAccess())
	local accessPaint = accessRow.Paint
	accessRow.Paint = function(self, w, h)
		accessPaint(self, w, h)
		local text = describeAccess()
		if #text > 22 then text = string.sub(text, 1, 20) .. "..." end
		draw.SimpleText(text, "HeistFlock.Mono", w - S(16), h / 2, Theme.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

local function buildCameras(page)
	local canPlace = can("place")

	local toolbar = makeToolbar(page)
	if canPlace then
		addToToolbar(toolbar, UI.Button(toolbar, "Place camera", function() startPlacing() end, { style = "primary", icon = "plus",
			tooltip = "Places one on the ground you're looking at" }))
	end
	addToToolbar(toolbar, makeLabeledToggle(toolbar, "Show all on map", HeistFlock.IsShowingAllCameras(), HeistFlock.SetShowAllCameras))
	if canPlace then
		addToToolbar(toolbar, UI.Button(toolbar, "Remove all", function()
			confirm("Remove every camera on this map?", "Remove all", function() sendAction("removeall") end)
		end, { style = "danger", icon = "trash" }), true)
		addToToolbar(toolbar, UI.Button(toolbar, "Reset all", function()
			confirm("Reset every camera to untouched?", "Reset all", function() sendAction("resetall") end)
		end, { icon = "reset" }), true)
	end

	local filterBar = makeToolbar(page)
	local countText = ""
	filterBar.Paint = function(self, w, h)
		draw.SimpleText(countText, "HeistFlock.Small", w, h / 2, Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	-- Where cameras are saved, how many, and when.
	local saveBar = page:Add("DPanel")
	saveBar:Dock(TOP)
	saveBar:DockMargin(0, 0, 0, S(12))
	saveBar:SetTall(S(46))

	local saveNow = UI.Button(saveBar, "Save now", function() sendAction("save") end, { icon = "save",
		tooltip = "Cameras also save on their own whenever an admin places, moves or removes one" })
	saveNow:SetVisible(canPlace)

	saveBar.Paint = function(self, w, h)
		local info = HeistFlock.ServerInfo
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, Theme.line)
		HeistFlock.DrawIcon("save", S(16), (h - S(16)) / 2, S(16), Theme.accent)
		if not info then return end

		local status
		if info.lastSave then
			local ago = HeistFlock.FormatAgo(HeistFlock.ServerNow() - info.lastSave.time)
			status = "Saved " .. info.lastSave.count .. (info.lastSave.count == 1 and " camera" or " cameras")
				.. (ago == "now" and " just now" or (" " .. ago .. " ago"))
		elseif info.cameraFile then
			status = "Loaded from save file"
		else
			status = "Not saved yet"
		end

		draw.SimpleText(status, "HeistFlock.Body", S(42), h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetFont("HeistFlock.Body")
		local statusW = surface.GetTextSize(status)
		draw.SimpleText(info.cameraSavePath, "HeistFlock.MonoSm", S(42) + statusW + S(14), h / 2, Theme.textFaint,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	saveBar.PerformLayout = function(self, w, h)
		saveNow:SetPos(w - saveNow:GetWide() - S(6), (h - saveNow:GetTall()) / 2)
	end

	local tableBox = vgui.Create("DPanel", page)
	tableBox:Dock(FILL)
	tableBox.Paint = function(self, w, h)
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, Theme.line)
	end

	local columns = { { "Camera", 120 }, { "Status", 140 }, { "Progress", 0 }, { "Distance", 100 }, { "", 224 } }
	makeTableHeader(tableBox, columns)

	local scroll = vgui.Create("DScrollPanel", tableBox)
	scroll:Dock(FILL)
	UI.StyleScroll(scroll)
	frame.mainScroll = scroll

	local function fillList()
		local savedScroll = scroll:GetVBar():GetScroll()
		scroll:Clear()

		local info = HeistFlock.ServerInfo
		if not info then return end

		local counts = countCameras(info.cameras)
		countText = counts.all .. (counts.all == 1 and " camera" or " cameras") .. "  ·  click a row to find it"

		if counts.all == 0 then
			local empty = scroll:Add("DPanel")
			empty:Dock(TOP)
			empty:SetTall(S(200))
			empty.Paint = function(self, w, h)
				HeistFlock.DrawIcon("camera", w / 2 - S(16), h / 2 - S(46), S(32), Theme.textFaint)
				draw.SimpleText("No cameras yet", "HeistFlock.Heading", w / 2, h / 2 + S(6), Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("Look at the ground and press Place camera.", "HeistFlock.Small", w / 2, h / 2 + S(28), Theme.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			return
		end

		-- Closest first.
		local myPos = LocalPlayer():GetPos()
		local cameras = table.Copy(info.cameras)
		table.sort(cameras, function(a, b) return a.pos:DistToSqr(myPos) < b.pos:DistToSqr(myPos) end)
		local stageCount = #Config.Stages

		for _, cam in ipairs(cameras) do
			local state = getCameraState(cam)
			if cameraFilter == "all" or state == cameraFilter then
				local meters = math.Round(cam.pos:Distance(myPos) * 0.01905)

				local row = scroll:Add("DButton")
				row:SetText("")
				row:Dock(TOP)
				row:SetTall(S(46))
				row.DoClick = function()
					HeistFlock.HighlightCamera(cam.id)
					surface.PlaySound("ui/buttonclick.wav")
				end
				row.Paint = function(self, w, h)
					local positions = columnPositions(columns, w)
					local hover = UI.HoverAmount(self, self:IsHovered())
					local highlighted = HeistFlock.GetHighlightedCamera() == cam.id

					if hover > 0.01 then draw.RoundedBox(0, 0, 0, w, h, ColorAlpha(Theme.raised, 255 * hover)) end
					if highlighted then draw.RoundedBox(0, 0, S(8), S(2), h - S(16), Theme.accent) end
					surface.SetDrawColor(Theme.line)
					surface.DrawRect(S(14), h - 1, w - S(28), 1)

					draw.SimpleText(string.format("CAM-%03d", cam.id), "HeistFlock.Mono", positions[1], h / 2,
						highlighted and Theme.accent or Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					local look = STATE_LOOKS[state]
					if state == "active" and cam.worker == "" then look = STATE_LOOKS.damaged end
					UI.DrawPill(look[1], positions[2], h / 2, look[2])

					-- Progress: one small segment per stage, then a detail.
					local segW, gap = S(18), S(3)
					for i = 1, stageCount do
						local done = i <= cam.stage
						draw.RoundedBox(S(1), positions[3] + (i - 1) * (segW + gap), h / 2 - S(2), segW, S(4),
							done and (state == "stripped" and Theme.red or Theme.accent) or Theme.line)
					end
					local detail
					if cam.worker ~= "" then
						detail = cam.worker
					elseif state == "stripped" then
						detail = cam.repairIn > 0 and ("repairs in " .. HeistFlock.FormatTime(cam.repairIn)) or "until restart"
					elseif state == "active" then
						detail = cam.repairIn > 0 and ("resets in " .. HeistFlock.FormatTime(cam.repairIn)) or "until restart"
					elseif cam.scanning then
						detail = "reading plates"
					elseif Config.ALPR.Enabled then
						detail = "blind (damaged)"
					end
					if detail then
						draw.SimpleText(detail, "HeistFlock.Small", positions[3] + stageCount * (segW + gap) + S(10), h / 2,
							Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end

					draw.SimpleText(meters .. " m", "HeistFlock.Mono", positions[4], h / 2, Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end

				local buttons = {
					UI.IconButton(row, "locate", "Find it on the map", function() HeistFlock.HighlightCamera(cam.id) end),
				}
				if canPlace then
					table.Add(buttons, {
						UI.IconButton(row, "move", "Move it (aim with a preview)", function() startPlacing(cam.id) end),
						UI.IconButton(row, "teleport", "Teleport there", function() sendAction("teleport", cam.id) end),
						UI.IconButton(row, "skip", "Skip a stage (nobody is paid, no parts drop)", function() sendAction("advance", cam.id) end),
						UI.IconButton(row, "reset", "Reset to untouched", function() sendAction("reset", cam.id) end),
						UI.IconButton(row, "trash", "Remove", function()
							confirm(string.format("Remove CAM-%03d?", cam.id), "Remove", function() sendAction("remove", cam.id) end)
						end, true),
					})
				end
				row.PerformLayout = function(self, w, h)
					for i, button in ipairs(buttons) do
						button:SetPos(w - S(12) - (#buttons - i + 1) * S(34), (h - button:GetTall()) / 2)
					end
				end
			end
		end

		restoreScroll(scroll, savedScroll)
	end

	addToToolbar(filterBar, UI.Segmented(filterBar, { "all", "ready", "active", "stripped" },
		{ "All", "Ready", "Damaged", "Stripped" }, cameraFilter, function(choice)
			cameraFilter = choice
			fillList()
		end))

	fillList()
	return fillList -- runs again when new info arrives, without rebuilding the page
end

-- The right input for a setting. Changes go to the unsaved list.
local function makeSettingInput(parent, setting)
	local value = getValue(setting)
	local function changed(newValue) setPending(setting, newValue) end

	if setting.type == "bool" then
		return UI.Toggle(parent, value, changed)
	elseif setting.type == "number" then
		return UI.TextBox(parent, S(140), value, true, setting.unit, function(text)
			local number = tonumber(text)
			if number then changed(math.Clamp(math.Round(number), setting.min, setting.max)) end
		end)
	elseif setting.type == "string" then
		return UI.TextBox(parent, S(280), value, false, nil, changed)
	elseif setting.type == "list" then
		-- Shown as "a, b, c"; split back into a list on every change.
		return UI.TextBox(parent, S(280), table.concat(value, ", "), false, nil, function(text)
			local list = {}
			for _, entry in ipairs(string.Explode(",", text)) do
				entry = string.lower(string.Trim(entry))
				if entry ~= "" then table.insert(list, entry) end
			end
			changed(list)
		end)
	elseif setting.type == "choice" then
		return UI.Segmented(parent, setting.choices, setting.choiceLabels or setting.choices, value, function(choice)
			changed(choice)
			-- Switching strip mode shows a different set of settings.
			if setting.id == "StripMode" then showPage(currentPage) end
		end)
	end
end

local function buildSettings(page)
	makeSaveBar(page)
	local scroll = makeScroll(page)

	-- Settings for the other strip mode are hidden (they keep their values).
	local mode = getValue(HeistFlock.FindSetting("StripMode"))

	local lastSection, group
	for _, setting in ipairs(HeistFlock.Settings) do
		if setting.type ~= "jobs" and (setting.mode == nil or setting.mode == mode) then
			if setting.section ~= lastSection then
				makeHeading(scroll, setting.section, lastSection == nil and 0 or nil)
				group = makeGroup(scroll)
				lastSection = setting.section
			end

			makeRow(group, setting.label, setting.description, makeSettingInput(group, setting), function()
				return pendingChanges[setting.id] ~= nil
			end)
		end
	end

	makeHeading(scroll, "Defaults")
	local defaults = makeGroup(scroll)
	makeRow(defaults, "Reset every setting", "Goes back to the values in sh_config.lua.",
		UI.Button(defaults, "Reset", function()
			confirm("Reset every setting to the defaults in sh_config.lua?", "Reset", function()
				pendingChanges = {}
				net.Start("HeistFlock_ResetSettings")
				net.SendToServer()
			end)
		end, { style = "danger" }))
end

local function buildAccess(page)
	local jobsSetting = HeistFlock.FindSetting("Jobs")
	local modeSetting = HeistFlock.FindSetting("JobMode")
	local policeSetting = HeistFlock.FindSetting("BlockPolice")

	makeSaveBar(page)

	if not RPExtraTeams then
		makeEmptyState(page, "users", "DarkRP isn't running", "Jobs only exist on a DarkRP server.")
		return
	end

	local rules = makeGroup(page)
	makeRow(rules, "Job list", modeSetting.description,
		UI.Segmented(rules, modeSetting.choices, modeSetting.choiceLabels, getValue(modeSetting), function(choice)
			setPending(modeSetting, choice)
		end), function() return pendingChanges.JobMode ~= nil end)
	makeRow(rules, "Block government jobs", policeSetting.description,
		UI.Toggle(rules, getValue(policeSetting), function(value)
			setPending(policeSetting, value)
		end), function() return pendingChanges.BlockPolice ~= nil end)

	local toolbar = makeToolbar(page)
	toolbar:DockMargin(0, S(16), 0, S(12))

	local tableBox = vgui.Create("DPanel", page)
	tableBox:Dock(FILL)
	tableBox.Paint = function(self, w, h)
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, Theme.line)
	end

	local columns = { { "", 34 }, { "Job", 0 }, { "Command", 200 }, { "Result", 170 }, { "Listed", 70 } }
	makeTableHeader(tableBox, columns)

	local scroll = vgui.Create("DScrollPanel", tableBox)
	scroll:Dock(FILL)
	UI.StyleScroll(scroll)

	local function isListed(job)
		for _, listed in ipairs(getValue(jobsSetting)) do
			listed = string.lower(listed)
			if listed == string.lower(job.command) or listed == string.lower(job.name) then return true end
		end
		return false
	end

	local function toggleJob(job)
		local newList, wasListed = {}, false
		for _, listed in ipairs(getValue(jobsSetting)) do
			local lower = string.lower(listed)
			if lower == string.lower(job.command) or lower == string.lower(job.name) then
				wasListed = true
			else
				table.insert(newList, listed)
			end
		end
		if not wasListed then table.insert(newList, job.command) end
		setPending(jobsSetting, newList)
	end

	-- Can this job strip cameras with the settings as they'd be after saving?
	local function getEffect(job, index)
		local listed = isListed(job)
		local isGovernment = GAMEMODE.CivilProtection and GAMEMODE.CivilProtection[index]

		if getValue(policeSetting) and isGovernment then return false, "BLOCKED · GOV" end
		if getValue(modeSetting) == "whitelist" then return listed, listed and "CAN STRIP" or "BLOCKED" end
		return not listed, listed and "BLOCKED" or "CAN STRIP"
	end

	local function fill()
		scroll:Clear()
		local search = string.lower(jobSearch)

		for index, job in ipairs(RPExtraTeams) do
			local matches = search == "" or string.find(string.lower(job.name), search, 1, true)
				or string.find(string.lower(job.command), search, 1, true)

			if matches then
				local row = scroll:Add("DButton")
				row:SetText("")
				row:Dock(TOP)
				row:SetTall(S(44))
				row.DoClick = function()
					toggleJob(job)
					surface.PlaySound("ui/buttonclick.wav")
				end
				row.Paint = function(self, w, h)
					local positions = columnPositions(columns, w)
					local hover = UI.HoverAmount(self, self:IsHovered())
					local canStrip, effect = getEffect(job, index)
					local listed = isListed(job)

					if hover > 0.01 then draw.RoundedBox(0, 0, 0, w, h, ColorAlpha(Theme.raised, 255 * hover)) end
					surface.SetDrawColor(Theme.line)
					surface.DrawRect(S(14), h - 1, w - S(28), 1)

					draw.RoundedBox(S(3), positions[1], h / 2 - S(6), S(12), S(12), job.color or Theme.text)
					draw.SimpleText(job.name, "HeistFlock.Body", positions[2], h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText("/" .. job.command, "HeistFlock.Mono", positions[3], h / 2, Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					UI.DrawPill(effect, positions[4], h / 2, canStrip and Theme.accent or Theme.red)

					-- Checkbox
					local box = S(18)
					local bx, by = positions[5] + S(10), h / 2 - box / 2
					HeistFlock.DrawBox(bx, by, box, box, listed and Theme.accent or Theme.input, listed and Theme.accent or Theme.line, S(3))
					if listed then HeistFlock.DrawIcon("check", bx + S(2), by + S(2), box - S(4), Theme.accentText) end
				end
			end
		end
	end

	local search = UI.TextBox(toolbar, S(260), jobSearch, false, "", function(text) -- "" leaves room for the icon
		jobSearch = text
		fill()
	end)
	addToToolbar(toolbar, search)
	addToToolbar(toolbar, UI.Button(toolbar, "Clear list", function()
		setPending(jobsSetting, {})
	end, { style = "ghost" }), true)
	toolbar.Paint = function(self, w, h)
		HeistFlock.DrawIcon("search", search:GetWide() - S(26), (h - S(16)) / 2, S(16), Theme.textFaint)
	end

	fill()
end

local function buildDiagnostics(page)
	local info = HeistFlock.ServerInfo

	-- The server's report plus a few things only this game knows.
	local function fullReport()
		local latest = HeistFlock.ServerInfo
		if not latest or not latest.report then return end

		local hasIcons = file.Exists("materials/heistflock/ui/logo.png", "GAME")
		local hasFonts = file.Exists("resource/fonts/heistflock_sans.ttf", "GAME")
		return latest.report .. "\n\nYour game: " .. ScrW() .. "x" .. ScrH()
			.. "  ·  camera entity " .. (scripted_ents.Get("heistflock_camera") and "yes" or "NO")
			.. "  ·  pliers " .. (weapons.Get("heistflock_pliers") and "yes" or "NO")
			.. "  ·  icons " .. (hasIcons and "yes" or "NO") .. "  ·  fonts " .. (hasFonts and "yes" or "NO")
	end

	local toolbar = makeToolbar(page)
	addToToolbar(toolbar, UI.Button(toolbar, "Copy report", function()
		local report = fullReport()
		if not report then return end
		SetClipboardText(report)
		notify("Report copied. Paste it to whoever is helping you.")
	end, { style = "primary", icon = "check",
		tooltip = "Copies a plain-text summary: version, setup, permissions, warnings and recent events. No IPs or SteamIDs." }))
	addToToolbar(toolbar, UI.Button(toolbar, "Print to console", function()
		local report = fullReport()
		if not report then return end
		for _, line in ipairs(string.Explode("\n", report)) do print(line) end
		notify("Report printed to your console.")
	end, { style = "ghost" }))
	addToToolbar(toolbar, UI.Button(toolbar, "Refresh", HeistFlock.RequestServerInfo, { icon = "refresh", style = "ghost" }))
	if can("manage") then
		addToToolbar(toolbar, makeLabeledToggle(toolbar, "Debug logging", Config.Debug, function(enabled)
			net.Start("HeistFlock_ChangeSettings")
			net.WriteTable({ Debug = enabled })
			net.SendToServer()
		end), true)
	end

	local scroll = makeScroll(page)
	if not info then
		makeLoading(scroll)
		return
	end

	local clientEntity = scripted_ents.Get("heistflock_camera") ~= nil
	local clientWeapon = weapons.Get("heistflock_pliers") ~= nil
	local inSpawnMenu = list.Get("SpawnableEntities")["heistflock_camera"] ~= nil
	local hasIcons = file.Exists("materials/heistflock/ui/logo.png", "GAME")

	local permissions = info.permissions or { adminMods = {}, privileges = {}, fallbackGroups = {} }
	local noAdminMod = #permissions.adminMods == 0 and not permissions.cami

	local problems = #info.warnings
	for _, ok in ipairs({ info.entityRegistered, info.pliersRegistered, info.modelValid, clientEntity, clientWeapon,
		not info.noIncome, not noAdminMod }) do
		if not ok then problems = problems + 1 end
	end

	local banner = scroll:Add("DPanel")
	banner:Dock(TOP)
	banner:SetTall(S(90))
	banner.Paint = function(self, w, h)
		local color = problems == 0 and Theme.accent or Theme.red
		HeistFlock.DrawBox(0, 0, w, h, Theme.surface, ColorAlpha(color, 110))
		HeistFlock.DrawIcon(problems == 0 and "check" or "alert", S(20), S(20), S(24), color)
		local title = problems == 0 and "All systems normal" or (problems .. (problems == 1 and " problem found" or " problems found"))
		draw.SimpleText(title, "HeistFlock.Heading", S(58), S(16), Theme.text)
		draw.SimpleText("v" .. info.version .. "  ·  " .. info.map .. "  ·  " .. info.players .. " online  ·  "
			.. info.tickrate .. " tick", "HeistFlock.MonoSm", S(58), S(40), Theme.textDim)
		draw.SimpleText("Something not working? Press Copy report and paste it to whoever is helping you.", "HeistFlock.Small",
			S(58), S(64), Theme.textFaint)
	end

	local function check(group, label, value, ok, hint)
		local row = makeRow(group, label, hint)
		local basePaint = row.Paint
		local color = ok == true and Theme.accent or (ok == false and Theme.red or Theme.textFaint)
		local icon = ok == false and "alert" or "check"
		row.Paint = function(self, w, h)
			basePaint(self, w, h)
			draw.SimpleText(tostring(value), "HeistFlock.Mono", w - S(42), h / 2, Theme.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			HeistFlock.DrawIcon(icon, w - S(32), h / 2 - S(8), S(16), color)
		end
	end
	local function yesNo(value) return value and "yes" or "no" end

	if #info.warnings > 0 or info.noIncome or noAdminMod then
		makeHeading(scroll, "Warnings")
		local warnings = makeGroup(scroll)
		for _, warning in ipairs(info.warnings) do
			check(warnings, warning, "", false)
		end
		if info.noIncome then
			check(warnings, "Steps mode pays nothing: the payout is $0 and crafting is off. Set a payout.", "", false)
		end
		if noAdminMod then
			check(warnings, "No admin mod or CAMI found: only these groups can use the menu: "
				.. table.concat(permissions.fallbackGroups, ", "), "", false)
		end
	end

	makeHeading(scroll, "Server")
	local server = makeGroup(scroll)
	check(server, "Gamemode", info.gamemode, info.darkrp or nil, not info.darkrp and "Money, jobs and wanted status need DarkRP." or nil)
	check(server, "Camera entity", yesNo(info.entityRegistered), info.entityRegistered,
		not info.entityRegistered and "Check the addon folder structure and the console for Lua errors." or nil)
	check(server, "Pliers weapon", yesNo(info.pliersRegistered), info.pliersRegistered)
	check(server, "Strip mode", Config.StripMode, nil)
	check(server, "Picked-up parts go to", info.partsProvider .. (info.partsProvider ~= Config.Parts.Provider and (" (" .. Config.Parts.Provider .. " isn't available)") or ""),
		info.partsProvider == Config.Parts.Provider or false)
	check(server, "Parts on the ground", info.looseParts .. " / " .. Config.Parts.MaxLoose, nil)
	check(server, "Plate scanning", Config.ALPR.Enabled and ("on, plates from " .. info.plateSource) or "off", Config.ALPR.Enabled or nil,
		"Realistic Police plates are used automatically when it's installed.")
	check(server, "Camera model", info.builtInModel and "built-in" or Config.Model, info.modelValid,
		not info.modelValid and "The custom model isn't on the server." or nil)
	check(server, "Camera save file", info.cameraFile and info.cameraSavePath or "not created yet", info.cameraFile or nil,
		"Created when the first camera is placed. Save it any time with heistflock_save in the console.")
	check(server, "Settings changed in-game", info.changedSettings, nil,
		"Saved in garrysmod/data/heistflock/settings.json; they win over sh_config.lua and config.json. Reset to defaults clears them.")

	makeHeading(scroll, "Permissions")
	local perms = makeGroup(scroll)
	local adminMods = #permissions.adminMods > 0 and table.concat(permissions.adminMods, ", ") or "none"
	check(perms, "Admin mod", adminMods, #permissions.adminMods > 0 or nil)
	check(perms, "CAMI", permissions.cami and ("yes" .. (permissions.camiVersion and (", v" .. permissions.camiVersion) or "")) or "no",
		permissions.cami or nil, "Every supported admin mod answers through CAMI.")
	for _, privilege in ipairs(permissions.privileges) do
		local status, ok = "no CAMI", nil
		if permissions.cami then
			status, ok = privilege.registered and "registered" or "not registered", privilege.registered
		end
		check(perms, privilege.name, status .. "  ·  you: " .. (privilege.yours and "yes" or "no"), ok)
	end

	-- Plate scanning: how much work it is, and the tools to watch it.
	makeHeading(scroll, "Plate scanning")
	local scanning = makeGroup(scroll)
	local scan = info.scanStats or {}
	check(scanning, "Time per scan", string.format("last %.2f ms  ·  average %.2f ms  ·  peak %.2f ms",
		scan.lastMs or 0, scan.averageMs or 0, scan.peakMs or 0), (scan.averageMs or 0) < 2 or nil,
		"How long the server spends reading plates each scan. Under 2 ms is fine; it rises with cameras × cars.")
	check(scanning, "Work per scan", string.format("%d cameras reading  ·  %d cars  ·  %d checks  ·  %d sight lines",
		scan.cameras or 0, scan.vehicles or 0, scan.checks or 0, scan.traces or 0), nil,
		"Sight lines are only traced for cars already in range and in view, so they stay low.")
	check(scanning, "Coverage", string.format("%.0f m range  ·  %d° each side (lens %d° + head turns %d°)",
		Config.ALPR.Range * 0.01905, info.coverage or 0, Config.ALPR.FieldOfView, Config.ALPR.Swivel), nil)
	makeRow(scanning, "Scanner view", "Draws what cameras near you see, and why each car is or isn't read.",
		UI.Toggle(scanning, HeistFlock.IsScannerView(), HeistFlock.SetScannerView))
	makeRow(scanning, "Check a car", "Sit in a car or look at one, then press. Lists every camera nearby and what it sees.",
		UI.Button(scanning, "Check", HeistFlock.CheckCar, { style = "ghost" }))
	makeRow(scanning, "Send me a test alert", "A fake plate hit only you see, to check what police get.",
		UI.Button(scanning, "Send", HeistFlock.SendTestAlert, { style = "ghost" }))

	-- The last plates read, so you can compare them with the police tablet.
	local reads = info.alprReads or {}
	for i = 1, math.min(#reads, 6) do
		local read = reads[i]
		local others = #(read.cameras or {}) - 1
		check(scanning, string.format("%s  ·  CAM-%03d%s", read.plate, read.camera, others > 0 and (" +" .. others .. " more") or ""),
			(read.flagged and "flagged  ·  " or "") .. HeistFlock.FormatAgo(HeistFlock.ServerNow() - read.time),
			read.flagged and false or nil)
	end
	if #reads == 0 then
		makeRow(scanning, "No plates read yet. A car has to pass in front of a working camera.")
	end

	-- What happened recently, newest first, in plain words.
	makeHeading(scroll, "Recent events")
	local events = makeGroup(scroll)
	local recent = info.recentLog or {}
	if #recent == 0 then
		makeRow(events, "Nothing yet. Hits, parts, alarms and admin actions show up here.")
	end
	for i = #recent, math.max(#recent - 14, 1), -1 do
		local entry = recent[i]
		local row = makeRow(events, "")
		local basePaint = row.Paint
		row.Paint = function(self, w, h)
			basePaint(self, w, h)
			draw.SimpleText(entry.text, "HeistFlock.Small", S(16), h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(HeistFlock.FormatAgo(HeistFlock.ServerNow() - entry.time), "HeistFlock.MonoSm", w - S(16), h / 2,
				Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	if #recent > 15 then
		makeRow(events, "Older events are in the copied report (the last " .. #recent .. ").")
	end

	makeHeading(scroll, "Your game")
	local client = makeGroup(scroll)
	check(client, "Camera entity", yesNo(clientEntity), clientEntity)
	check(client, "In the spawn menu", yesNo(inSpawnMenu), inSpawnMenu or nil)
	check(client, "Pliers weapon", yesNo(clientWeapon), clientWeapon)
	check(client, "Fonts and icons downloaded", yesNo(hasIcons), hasIcons or nil,
		"Downloaded on join. Needs sv_allowdownload 1, FastDL or a Workshop content pack.")
end

-- The window -------------------------------------------------------------------

local PAGES = {
	{ id = "dashboard",   label = "Dashboard",   icon = "dashboard", build = buildDashboard,   access = "view" },
	{ id = "cameras",     label = "Cameras",     icon = "camera",    build = buildCameras,     access = "view" },
	{ id = "settings",    label = "Settings",    icon = "sliders",   build = buildSettings,    access = "manage" },
	{ id = "access",      label = "Access",      icon = "users",     build = buildAccess,      access = "manage" },
	{ id = "diagnostics", label = "Diagnostics", icon = "pulse",     build = buildDiagnostics, access = "view" },
}

local PAGES_USING_INFO = { dashboard = true, cameras = true, diagnostics = true }

-- Only pages this player may see.
local function findPage(id)
	for _, page in ipairs(PAGES) do
		if page.id == id and can(page.access) then return page end
	end
end

showPage = function(id)
	if not IsValid(frame) then return end

	local pageInfo = findPage(id) or PAGES[1]
	local samePage = frame.shownPage == pageInfo.id
	local savedScroll = (samePage and IsValid(frame.mainScroll)) and frame.mainScroll:GetVBar():GetScroll() or 0

	currentPage = pageInfo.id
	frame.content:Clear()
	frame.mainScroll = nil
	frame.refreshPage = nil
	frame.shownPage = currentPage

	frame.refreshPage = pageInfo.build(frame.content)

	if samePage and IsValid(frame.mainScroll) then
		restoreScroll(frame.mainScroll, savedScroll)
	end

	if PAGES_USING_INFO[currentPage] and not samePage then
		HeistFlock.RequestServerInfo()
	end
end

local function makeNavButton(parent, pageInfo)
	local button = vgui.Create("DButton", parent)
	button:SetText("")
	button:Dock(TOP)
	button:DockMargin(S(12), 0, S(12), S(2))
	button:SetTall(S(38))

	button.Paint = function(self, w, h)
		local active = currentPage == pageInfo.id
		local hover = UI.HoverAmount(self, self:IsHovered() and not active)

		if active then
			draw.RoundedBox(S(4), 0, 0, w, h, Theme.raised)
			draw.RoundedBox(0, 0, S(10), S(2), h - S(20), Theme.accent)
		elseif hover > 0.01 then
			draw.RoundedBox(S(4), 0, 0, w, h, ColorAlpha(Theme.raised, 160 * hover))
		end

		HeistFlock.DrawIcon(pageInfo.icon, S(14), (h - S(16)) / 2, S(16), active and Theme.accent or Theme.textDim)
		draw.SimpleText(pageInfo.label, "HeistFlock.Body", S(40), h / 2, active and Theme.text or Theme.textDim,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		local hasPending = (pageInfo.id == "settings" or pageInfo.id == "access") and countPending() > 0
		if hasPending then
			draw.RoundedBox(S(3), w - S(18), h / 2 - S(3), S(6), S(6), Theme.accent)
		end
	end

	button.DoClick = function()
		surface.PlaySound("ui/buttonclick.wav")
		showPage(pageInfo.id)
	end
end

local function buildSidebar()
	local sidebar = vgui.Create("DPanel", frame)
	sidebar:Dock(LEFT)
	sidebar:SetWide(S(220))
	sidebar:DockPadding(0, S(84), 0, S(72))
	sidebar.Paint = function(self, w, h)
		draw.RoundedBoxEx(S(6), 0, 0, w, h, Theme.surface, true, false, true, false)
		surface.SetDrawColor(Theme.line)
		surface.DrawRect(w - 1, 0, 1, h)

		local logo = HeistFlock.Icon("logo")
		if not logo:IsError() then
			surface.SetMaterial(logo)
			surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(S(20), S(24), S(34), S(34))
		end
		draw.SimpleText("HEIST FLOCK", "HeistFlock.Heading", S(64), S(26), Theme.text)
		draw.SimpleText("v" .. HeistFlock.Version, "HeistFlock.MonoSm", S(64), S(46), Theme.textFaint)

		surface.SetDrawColor(Theme.line)
		surface.DrawRect(S(16), h - S(64), w - S(32), 1)
		draw.SimpleText(LocalPlayer():Nick(), "HeistFlock.Body", S(64), h - S(42), Theme.text)
		local role = can("manage") and "Manager" or (can("place") and "Staff: cameras" or "Staff: view only")
		draw.SimpleText(role, "HeistFlock.Small", S(64), h - S(24), Theme.textFaint)
	end

	for _, pageInfo in ipairs(PAGES) do
		if can(pageInfo.access) then makeNavButton(sidebar, pageInfo) end
	end

	local avatar = vgui.Create("AvatarImage", sidebar)
	avatar:SetSize(S(32), S(32))
	avatar:SetPlayer(LocalPlayer(), 64)
	sidebar.PerformLayout = function(self, w, h)
		avatar:SetPos(S(20), h - S(48))
	end
end

local function buildTopBar()
	local topBar = vgui.Create("DPanel", frame)
	topBar:Dock(TOP)
	topBar:SetTall(S(72))
	topBar.Paint = function(self, w, h)
		local pageInfo = findPage(currentPage) or PAGES[1]
		draw.SimpleText(pageInfo.label, "HeistFlock.Title", S(28), h / 2, Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local close = UI.IconButton(topBar, "close", "Close", function() frame:Close() end)
	topBar.PerformLayout = function(self, w, h)
		close:SetPos(w - close:GetWide() - S(18), (h - close:GetTall()) / 2)
	end

	-- Drag the window by its top bar.
	topBar.OnMousePressed = function(self)
		frame.Dragging = { gui.MouseX() - frame.x, gui.MouseY() - frame.y }
		self:MouseCapture(true) -- so the release comes back here
	end
	topBar.OnMouseReleased = function(self)
		frame.Dragging = nil
		self:MouseCapture(false)
	end
end

local function openMenu()
	if not can("view") then
		notify("You don't have permission to open this menu.")
		return
	end

	if IsValid(frame) then frame:Remove() end

	frame = vgui.Create("DFrame")
	frame:SetSize(math.min(S(1060), ScrW() - S(40)), math.min(S(700), ScrH() - S(40)))
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(false) -- dragged by the top bar instead
	frame:DockPadding(0, 0, 0, 0)
	frame:MakePopup()
	frame:SetAlpha(0)
	frame:AlphaTo(255, 0.15)
	frame.openedAt = SysTime()

	frame.Paint = function(self, w, h)
		Derma_DrawBackgroundBlur(self, self.openedAt)
		HeistFlock.DrawBox(0, 0, w, h, Theme.background, Theme.line, S(6))
	end

	buildSidebar()
	buildTopBar()

	local content = vgui.Create("DPanel", frame)
	content:Dock(FILL)
	content:DockPadding(S(28), S(4), S(28), S(24))
	content:SetPaintBackground(false)
	frame.content = content

	-- Move while dragging, and keep camera info fresh.
	frame.nextInfoRefresh = CurTime() + INFO_REFRESH_INTERVAL
	frame.Think = function(self)
		if self.Dragging then
			local x = math.Clamp(gui.MouseX() - self.Dragging[1], 0, ScrW() - self:GetWide())
			local y = math.Clamp(gui.MouseY() - self.Dragging[2], 0, ScrH() - self:GetTall())
			self:SetPos(x, y)
		end

		if PAGES_USING_INFO[currentPage] and CurTime() >= self.nextInfoRefresh then
			self.nextInfoRefresh = CurTime() + INFO_REFRESH_INTERVAL
			HeistFlock.RequestServerInfo()
		end
	end

	showPage(currentPage)
	HeistFlock.RequestServerInfo()
end

concommand.Add("heistflock_menu", openMenu)

-- A short fingerprint of the info a page shows, leaving out values that
-- change on every update but aren't displayed there (clock, countdowns).
local function infoFingerprint(info)
	local copy = table.Copy(info)
	copy.serverTime = nil
	copy.report = nil -- has the time in it; read fresh when copied
	for _, cam in ipairs(copy.cameras or {}) do
		cam.repairIn = nil
	end
	return util.TableToJSON(copy)
end

-- New camera info: update the open page, but only if something it shows
-- changed, so the page doesn't rebuild (and jump) every few seconds.
local lastFingerprint
hook.Add("HeistFlock_InfoUpdated", "HeistFlock_RefreshMenu", function()
	if not IsValid(frame) or not PAGES_USING_INFO[currentPage] then return end

	if frame.refreshPage then
		frame.refreshPage() -- the Cameras page updates its list in place (countdowns change)
		return
	end

	local fingerprint = infoFingerprint(HeistFlock.ServerInfo)
	if fingerprint == lastFingerprint and frame.shownPage == currentPage then return end
	lastFingerprint = fingerprint

	showPage(currentPage)
end)

-- New settings from the server: drop unsaved changes that now match, and redraw.
hook.Add("HeistFlock_ConfigChanged", "HeistFlock_RefreshMenu", function()
	for id, value in pairs(pendingChanges) do
		local setting = HeistFlock.FindSetting(id)
		if not setting or valuesEqual(value, HeistFlock.GetSetting(setting)) then
			pendingChanges[id] = nil
		end
	end

	if IsValid(frame) then
		showPage(currentPage)
	end
end)
