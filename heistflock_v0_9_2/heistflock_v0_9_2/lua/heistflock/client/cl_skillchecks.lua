-- Hands-on steps: a close-up of the part of the camera being worked on, with
-- what to do and what to avoid written underneath. The server sends each step
-- and judges the answer; this file only draws it and reports what was done.

local Theme = HeistFlock.Theme
local S = HeistFlock.S
local L = HeistFlock.L
local UI = HeistFlock.UI

local activeWindow

-- Colors for hardware (not part of the UI theme).
local METAL       = Color(62, 66, 74)
local METAL_LIGHT = Color(96, 101, 112)
local METAL_DARK  = Color(34, 36, 41)
local HOLE        = Color(14, 15, 17)
local PCB_GREEN   = Color(26, 92, 52)
local PCB_DARK    = Color(18, 64, 36)
local GOLD        = Color(226, 176, 62)
local STICKER     = Color(232, 230, 222)
local INK         = Color(30, 30, 34)

local LEAD_NAMES  = { "GND", "12V", "SOLAR" }
local LEAD_COLORS = { Color(40, 40, 44), Color(205, 52, 48), Color(232, 132, 40) }

local CABLE_COLORS = {
	Color(205, 52, 48),   -- SOLAR IN
	Color(44, 44, 48),    -- LTE ANT
	Color(60, 110, 220),  -- CAM DATA
	Color(220, 220, 214), -- IR LED
	Color(236, 196, 52),  -- BATT
	Color(56, 170, 84),   -- TAMPER
}

-- Drawing helpers --------------------------------------------------------------

-- A thick line as a four-sided shape, drawn in both windings because the
-- engine skips shapes facing the wrong way.
local function drawThickLine(x1, y1, x2, y2, width, color)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	if length == 0 then return end

	local nx, ny = -dy / length * width / 2, dx / length * width / 2
	local a, b = { x = x1 + nx, y = y1 + ny }, { x = x2 + nx, y = y2 + ny }
	local c, d = { x = x2 - nx, y = y2 - ny }, { x = x1 - nx, y = y1 - ny }

	surface.SetDrawColor(color)
	draw.NoTexture()
	surface.DrawPoly({ a, b, c, d })
	surface.DrawPoly({ d, c, b, a })
end

local function drawCircle(x, y, radius, color)
	draw.RoundedBox(radius, x - radius, y - radius, radius * 2, radius * 2, color)
end

-- Part of a ring, from 0 (top) clockwise by fraction (0-1).
local function drawArc(x, y, radius, fraction, width, color)
	local segments = math.max(math.ceil(48 * fraction), 1)
	local lastX, lastY = x, y - radius
	for i = 1, segments do
		local angle = (i / segments) * fraction * math.pi * 2
		local px, py = x + math.sin(angle) * radius, y - math.cos(angle) * radius
		drawThickLine(lastX, lastY, px, py, width, color)
		lastX, lastY = px, py
	end
end

-- A rectangle turned by angleDeg around (pivotX, pivotY). ox, oy are the
-- rectangle's top-left relative to the pivot when it isn't turned.
local function drawTurnedRect(pivotX, pivotY, ox, oy, w, h, angleDeg, color)
	local rad = math.rad(angleDeg)
	local cos, sin = math.cos(rad), math.sin(rad)
	local function point(px, py)
		return { x = pivotX + px * cos - py * sin, y = pivotY + px * sin + py * cos }
	end
	local corners = { point(ox, oy), point(ox + w, oy), point(ox + w, oy + h), point(ox, oy + h) }

	surface.SetDrawColor(color)
	draw.NoTexture()
	surface.DrawPoly(corners)
	surface.DrawPoly({ corners[4], corners[3], corners[2], corners[1] })
end

-- Splits text into lines that fit maxWidth.
local function wrapText(text, font, maxWidth)
	surface.SetFont(font)
	local lines, current = {}, ""
	for word in string.gmatch(text, "%S+") do
		local candidate = current == "" and word or (current .. " " .. word)
		if surface.GetTextSize(candidate) > maxWidth and current ~= "" then
			table.insert(lines, current)
			current = word
		else
			current = candidate
		end
	end
	if current ~= "" then table.insert(lines, current) end
	return lines
end

local function sendAnswer(window, answer, gaveUp)
	if window.answered then return end
	window.answered = true
	window:MouseCapture(false)

	net.Start("HeistFlock_SkillAnswer")
	net.WriteUInt(window.checkId, 31)
	net.WriteUInt(window.cameraId, 16)
	net.WriteBool(gaveUp or false)
	net.WriteTable(answer or {})
	net.SendToServer()
end

local function isReady(window)
	return CurTime() >= window.startTime
end

local function mouseHeld()
	return input.IsMouseDown(MOUSE_LEFT)
end

-- Steps --------------------------------------------------------------------------
-- Each step: setup (optional), paint(window, x, y, w, h) where x/y/w/h is the
-- area to draw in, press(window, mx, my), release(window).
local steps = {}

-- Security screws: hold on each one until it backs out.
steps.screws = {
	setup = function(window)
		window.progress, window.removed, window.order = {}, {}, {}
	end,

	positions = function(x, y, w, h)
		local plateW, plateH = S(300), S(150)
		local px, py = x + (w - plateW) / 2, y + (h - plateH) / 2
		local inset = S(26)
		return px, py, plateW, plateH, {
			{ px + inset, py + inset }, { px + plateW - inset, py + inset },
			{ px + inset, py + plateH - inset }, { px + plateW - inset, py + plateH - inset },
		}
	end,

	paint = function(window, x, y, w, h)
		local data = window.data
		local px, py, pw, ph, screws = steps.screws.positions(x, y, w, h)
		local radius = S(16)

		-- The access plate.
		HeistFlock.DrawBox(px, py, pw, ph, METAL, METAL_LIGHT, S(6))
		draw.SimpleText("ACCESS PANEL  ·  DO NOT OPEN", "HeistFlock.MonoSm", px + pw / 2, py + ph / 2,
			ColorAlpha(METAL_LIGHT, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- Holding: keep going, slip off, or let go.
		local holding = window.holding
		if holding and not window.answered then
			local mx, my = window:CursorPos()
			local sx, sy = screws[holding][1], screws[holding][2]

			if not mouseHeld() then
				window.holding = nil
			elseif (mx - sx) ^ 2 + (my - sy) ^ 2 > (radius * 1.4) ^ 2 then
				window.progress[holding] = 0 -- the bit slipped off the screw
				window.holding = nil
				surface.PlaySound("physics/metal/metal_grenade_impact_soft" .. math.random(1, 3) .. ".wav")
			else
				window.progress[holding] = (window.progress[holding] or 0) + FrameTime() / data.holdTime
				if window.progress[holding] >= 1 then
					window.removed[holding] = true
					table.insert(window.order, holding)
					window.holding = nil
					surface.PlaySound("physics/metal/metal_solid_impact_soft" .. math.random(1, 3) .. ".wav")

					if #window.order == data.count then
						sendAnswer(window, { order = window.order })
					end
				end
			end
		end

		for i, pos in ipairs(screws) do
			local sx, sy = pos[1], pos[2]
			if window.removed[i] then
				drawCircle(sx, sy, S(7), HOLE)
			else
				local progress = window.progress[i] or 0
				local turn = progress * 720
				drawCircle(sx, sy, radius, METAL_DARK)
				drawCircle(sx, sy, radius - S(2), window.holding == i and METAL_LIGHT or Color(120, 125, 136))

				-- Security (star) head, turning as it comes out.
				for spoke = 0, 2 do
					local angle = math.rad(turn + spoke * 60)
					local dx, dy = math.cos(angle) * S(8), math.sin(angle) * S(8)
					drawThickLine(sx - dx, sy - dy, sx + dx, sy + dy, S(3), METAL_DARK)
				end

				if progress > 0 then
					drawArc(sx, sy, radius + S(5), progress, S(3), Theme.accent)
				end
			end
		end
	end,

	press = function(window, mx, my)
		local _, _, _, _, screws = steps.screws.positions(window.areaX, window.areaY, window.areaW, window.areaH)
		for i, pos in ipairs(screws) do
			if not window.removed[i] and (mx - pos[1]) ^ 2 + (my - pos[2]) ^ 2 <= S(20) ^ 2 then
				window.holding = i
				window:MouseCapture(true)
				return
			end
		end
	end,

	release = function(window)
		window.holding = nil
		window:MouseCapture(false)
	end,
}

-- Pry the lid: hold to build force, let go when it gives.
local function pryFill(window)
	if not window.pressTime then return 0 end
	return ((window.releaseTime or CurTime()) - window.pressTime) * window.data.fillSpeed
end

local function pryRelease(window)
	if not window.pressTime or window.releaseTime then return end
	window.releaseTime = CurTime()
	window:MouseCapture(false)
	local data = window.data
	local fill = pryFill(window)
	if fill > data.zoneStart + data.zoneWidth then
		surface.PlaySound("physics/metal/metal_box_break" .. math.random(1, 2) .. ".wav")
	end
	sendAnswer(window, { pressTime = window.pressTime, releaseTime = window.releaseTime })
end

steps.pry = {
	paint = function(window, x, y, w, h)
		local data = window.data
		local fill = math.min(pryFill(window), 1.2)

		-- Housing and lid.
		local bodyW, bodyH = S(260), S(110)
		local bx, by = x + S(40), y + h - bodyH - S(10)
		local lift = math.Clamp(fill / (data.zoneStart + data.zoneWidth), 0, 1) * S(10)
		local cracked = fill > data.zoneStart + data.zoneWidth

		HeistFlock.DrawBox(bx, by, bodyW, bodyH, METAL_DARK, METAL, S(4))
		HeistFlock.DrawBox(bx - S(4), by - S(20) - lift, bodyW + S(8), S(20), cracked and Color(90, 60, 50) or METAL, METAL_LIGHT, S(3))

		-- Light through the seam once it starts to give.
		local inZone = fill >= data.zoneStart and not cracked
		if inZone then
			draw.RoundedBox(0, bx, by - lift, bodyW, math.max(lift, S(2)), ColorAlpha(Theme.accent, 160))
		end

		-- The pry bar, wedged in the seam on the left.
		local tipX, tipY = bx + S(16), by - lift / 2
		drawThickLine(tipX, tipY, tipX - S(40), tipY + S(70) + fill * S(12), S(8), Color(150, 40, 36))

		-- Force gauge on the right; the green part is where it gives.
		local gx, gy, gw, gh = x + w - S(56), y + S(6), S(18), h - S(12)
		HeistFlock.DrawBox(gx, gy, gw, gh, Theme.input, Theme.line, S(3))
		local zoneTop = gy + gh * (1 - data.zoneStart - data.zoneWidth)
		draw.RoundedBox(0, gx + S(3), zoneTop, gw - S(6), gh * data.zoneWidth, ColorAlpha(Theme.accent, 90))
		if fill > 0 then
			local shown = math.min(fill, 1)
			draw.RoundedBox(S(2), gx + S(5), gy + gh * (1 - shown), gw - S(10), gh * shown - S(3), cracked and Theme.red or Theme.text)
		end
		draw.SimpleText("FORCE", "HeistFlock.Label", gx + gw / 2, gy - S(4), Theme.textFaint, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

		-- Creak once when it starts to give.
		if inZone and not window.creaked then
			window.creaked = true
			surface.PlaySound("physics/metal/metal_box_strain" .. math.random(1, 4) .. ".wav")
		end

		-- Let go anywhere (even off the window), or push past the zone and it cracks.
		if window.pressTime and not window.releaseTime then
			if not mouseHeld() or fill > data.zoneStart + data.zoneWidth + 0.08 then
				pryRelease(window)
			end
		end
	end,

	press = function(window)
		if window.pressTime then return end
		window.pressTime = CurTime()
		window:MouseCapture(true)
	end,

	release = pryRelease,
}

-- Battery leads: unplug them in the order on the sticker.
local function batteryLayout(window, x, y, w, h)
	local packW, packH = S(300), S(120)
	local px, py = x + (w - packW) / 2, y + h - packH - S(4)
	local spots = {}
	for slot, lead in ipairs(window.data.layout) do
		spots[lead] = { px + packW * (slot / 4), py }
	end
	return px, py, packW, packH, spots
end

steps.battery = {
	setup = function(window)
		window.unplugged, window.clicked = {}, {}
	end,

	paint = function(window, x, y, w, h)
		local data = window.data
		local px, py, pw, ph, spots = batteryLayout(window, x, y, w, h)

		HeistFlock.DrawBox(px, py, pw, ph, Color(46, 50, 58), METAL_LIGHT, S(6))
		draw.SimpleText("12V LiFePO4  ·  40Ah", "HeistFlock.MonoSm", px + S(12), py + ph - S(18), METAL_LIGHT)

		-- Service sticker with the order.
		local sx, sy, sw, sh = px + S(14), py + S(30), pw - S(28), S(48)
		draw.RoundedBox(S(2), sx, sy, sw, sh, STICKER)
		draw.SimpleText(L("battery_sticker"), "HeistFlock.Label", sx + S(8), sy + S(8), INK)
		local orderText = ""
		for i, lead in ipairs(data.order) do
			orderText = orderText .. i .. ". " .. LEAD_NAMES[lead] .. (i < #data.order and "     " or "")
		end
		draw.SimpleText(orderText, "HeistFlock.Mono", sx + S(8), sy + S(24), INK)

		-- The leads.
		for lead, spot in pairs(spots) do
			local lx, ly = spot[1], spot[2]
			local out = window.unplugged[lead]
			local lift = out and S(26) or 0

			drawThickLine(lx, ly - S(14) - lift, lx + (out and S(10) or 0), y, S(6), LEAD_COLORS[lead])
			HeistFlock.DrawBox(lx - S(14), ly - S(16) - lift, S(28), S(18), LEAD_COLORS[lead], METAL_LIGHT, S(3))
			draw.RoundedBox(S(2), lx - S(8), ly - S(4), S(16), S(6), METAL_LIGHT) -- terminal
			draw.SimpleText(LEAD_NAMES[lead], "HeistFlock.Label", lx, ly - S(22) - lift, Theme.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end

		if window.spark and CurTime() - window.spark.time < 0.4 then
			for i = 1, 6 do
				local angle = math.rad(i * 60 + CurTime() * 400)
				drawThickLine(window.spark.x, window.spark.y, window.spark.x + math.cos(angle) * S(16),
					window.spark.y + math.sin(angle) * S(16), S(2), Color(255, 230, 120))
			end
		end
	end,

	press = function(window, mx, my)
		local _, _, _, _, spots = batteryLayout(window, window.areaX, window.areaY, window.areaW, window.areaH)
		for lead, spot in pairs(spots) do
			if not window.unplugged[lead] and math.abs(mx - spot[1]) <= S(18) and my >= spot[2] - S(30) and my <= spot[2] + S(6) then
				window.unplugged[lead] = true
				table.insert(window.clicked, lead)

				local expected = window.data.order[#window.clicked]
				if lead ~= expected then
					window.spark = { x = spot[1], y = spot[2] - S(10), time = CurTime() }
					surface.PlaySound("ambient/energy/spark" .. math.random(1, 6) .. ".wav")
					sendAnswer(window, { order = window.clicked })
				else
					surface.PlaySound("physics/plastic/plastic_box_impact_soft" .. math.random(1, 4) .. ".wav")
					if #window.clicked == #window.data.order then
						sendAnswer(window, { order = window.clicked })
					end
				end
				return
			end
		end
	end,
}

-- Wiring loom: snip the cable on the work tag.
local function cableRows(window, x, y, w, h)
	local rows = {}
	local top, spacing = y + S(62), (h - S(70)) / #window.data.cables
	for i, cable in ipairs(window.data.cables) do
		rows[i] = { cable = cable, y = top + (i - 0.5) * spacing }
	end
	return rows, x + S(30), x + w - S(30)
end

local function cableY(row, px, x1, x2)
	return row.y + math.sin((px - x1) / (x2 - x1) * math.pi * 2 + row.cable) * S(4)
end

steps.cable = {
	paint = function(window, x, y, w, h)
		local data = window.data
		local rows, x1, x2 = cableRows(window, x, y, w, h)
		local mx, my = window:CursorPos()

		-- Work tag.
		HeistFlock.DrawBox(x, y, S(220), S(44), STICKER, nil, S(2))
		draw.SimpleText(L("cable_tag"), "HeistFlock.Label", x + S(10), y + S(8), INK)
		draw.SimpleText(L("cable_" .. data.target), "HeistFlock.Mono", x + S(10), y + S(22), INK)

		-- Conduit and junction box the cables run between.
		draw.RoundedBox(S(3), x1 - S(26), rows[1].y - S(18), S(22), rows[#rows].y - rows[1].y + S(36), METAL_DARK)
		draw.RoundedBox(S(3), x2 + S(4), rows[1].y - S(18), S(22), rows[#rows].y - rows[1].y + S(36), METAL)

		window.hoverRow = nil
		for i, row in ipairs(rows) do
			local hover = isReady(window) and not window.answered and math.abs(my - cableY(row, mx, x1, x2)) <= S(8) and mx > x1 and mx < x2
			if hover then window.hoverRow = i end

			local color = CABLE_COLORS[row.cable]
			local lastX, lastY = x1, cableY(row, x1, x1, x2)
			for step = 1, 24 do
				local px = x1 + (x2 - x1) * step / 24
				local py = cableY(row, px, x1, x2)
				local cutHere = window.cut and window.cut.row == i and math.abs(px - window.cut.x) < S(10)
				if not cutHere then
					drawThickLine(lastX, lastY, px, py, hover and S(9) or S(7), color)
				end
				lastX, lastY = px, py
			end

			-- Printed tag on the cable.
			local tagX = x1 + (x2 - x1) * 0.62
			local tagY = cableY(row, tagX, x1, x2)
			local name = L("cable_" .. row.cable)
			surface.SetFont("HeistFlock.Label")
			local tagW = surface.GetTextSize(name) + S(10)
			draw.RoundedBox(S(2), tagX - tagW / 2, tagY - S(7), tagW, S(14), STICKER)
			draw.SimpleText(name, "HeistFlock.Label", tagX, tagY, INK, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end,

	press = function(window, mx)
		if not window.hoverRow then return end
		local rows = cableRows(window, window.areaX, window.areaY, window.areaW, window.areaH)
		window.cut = { row = window.hoverRow, x = mx }
		surface.PlaySound("physics/metal/metal_chainlink_impact_soft" .. math.random(1, 3) .. ".wav")
		sendAnswer(window, { cut = rows[window.hoverRow].cable })
	end,
}

-- Modem board: hold and sway left and right to rock it out, gently.
steps.board = {
	setup = function(window)
		window.rocks, window.tilt, window.side = 0, 0, 0
	end,

	paint = function(window, x, y, w, h)
		local data = window.data
		local held = window.grabX and mouseHeld() and not window.answered

		-- Sway follows the mouse while held, and settles back when let go.
		local target = 0
		if held then
			local mx = window:CursorPos()
			target = math.Clamp((mx - window.grabX) / S(70), -1, 1)
		elseif window.grabX then
			window.grabX = nil
			window:MouseCapture(false)
		end
		window.tilt = Lerp(math.min(FrameTime() * 18, 1), window.tilt, target)

		-- A full swing to the other side counts as one rock.
		local side = window.tilt >= 0.75 and 1 or (window.tilt <= -0.75 and -1 or 0)
		if held and side ~= 0 and side ~= window.side then
			local now = CurTime()
			if window.side ~= 0 then
				if now - (window.lastRock or 0) < data.minRockTime then
					surface.PlaySound("physics/metal/metal_solid_strain" .. math.random(1, 5) .. ".wav")
					sendAnswer(window, { bent = true })
				else
					window.rocks = window.rocks + 1
					surface.PlaySound("physics/plastic/plastic_box_impact_soft" .. math.random(1, 4) .. ".wav")
					if window.rocks >= data.rocks then
						sendAnswer(window, { rocks = window.rocks })
					end
				end
			end
			window.lastRock = now
			window.side = side
		end

		-- Slot and board.
		local slotW = S(220)
		local pivotX, pivotY = x + w / 2, y + h - S(20)
		local rise = math.min(window.rocks / data.rocks, 1) * S(50)
		draw.RoundedBox(S(3), pivotX - slotW / 2 - S(10), pivotY - S(6), slotW + S(20), S(22), METAL_DARK)

		local boardW, boardH = slotW, S(120)
		local angle = window.tilt * 9
		local by = -boardH - rise
		drawTurnedRect(pivotX, pivotY, -boardW / 2, by, boardW, boardH, angle, PCB_GREEN)
		drawTurnedRect(pivotX, pivotY, -boardW / 2 + S(30), by + S(20), S(54), S(36), angle, Color(24, 24, 28)) -- modem chip
		drawTurnedRect(pivotX, pivotY, S(20), by + S(30), S(70), S(22), angle, PCB_DARK)
		for i = 0, 13 do
			drawTurnedRect(pivotX, pivotY, -boardW / 2 + S(12) + i * S(14.5), -S(12) - rise, S(8), S(12), angle, GOLD)
		end

		draw.SimpleText(window.rocks .. " / " .. data.rocks, "HeistFlock.MonoSm", x + w - S(4), y + S(4), Theme.textDim, TEXT_ALIGN_RIGHT)
	end,

	press = function(window, mx)
		window.grabX = mx
		window:MouseCapture(true)
	end,

	release = function(window)
		window.grabX = nil
		window:MouseCapture(false)
	end,
}

-- Gold contacts: keep the iron on the moving contact.
local function solderTarget(window, x1, x2)
	local elapsed = math.max(CurTime() - window.startTime, 0)
	local phase = (elapsed * window.data.speed) % 2
	local t = phase < 1 and phase or 2 - phase
	return x1 + (x2 - x1) * t
end

steps.solder = {
	setup = function(window)
		window.onTime, window.offTime = 0, 0
	end,

	paint = function(window, x, y, w, h)
		local data = window.data
		local stripY = y + h / 2 - S(30)
		local x1, x2 = x + S(40), x + w - S(40)

		draw.RoundedBox(S(4), x + S(10), stripY, w - S(20), S(60), PCB_GREEN)
		local padCount = 10
		for i = 0, padCount - 1 do
			local padX = x1 + (x2 - x1) * i / (padCount - 1)
			local lifted = window.onTime / data.duration > i / padCount
			draw.RoundedBox(S(2), padX - S(7), stripY + S(14), S(14), S(32), lifted and Color(120, 96, 50) or GOLD)
		end

		local targetX, targetY = solderTarget(window, x1, x2), stripY + S(30)
		local ready = isReady(window)
		local pulse = 0.6 + math.sin(CurTime() * 10) * 0.4
		drawCircle(targetX, targetY, S(14), ColorAlpha(Color(255, 140, 40), 90 * pulse))
		drawCircle(targetX, targetY, S(5), Color(255, 190, 90))

		-- The iron at the cursor.
		local mx, my = window:CursorPos()
		local holding = ready and window.pressed and mouseHeld() and not window.answered
		drawThickLine(mx, my, mx + S(30), my - S(50), S(6), Color(70, 70, 76))
		drawCircle(mx, my, S(3), holding and Color(255, 120, 40) or METAL_LIGHT)

		if holding then
			if (mx - targetX) ^ 2 + (my - targetY) ^ 2 <= S(16) ^ 2 then
				window.onTime = window.onTime + FrameTime()
				window.offTime = 0
			else
				window.offTime = window.offTime + FrameTime()
				if window.offTime > data.maxOffTime then
					sendAnswer(window, { slipped = true })
				end
			end

			if window.onTime >= data.duration then
				sendAnswer(window, { done = true })
			end
		else
			window.offTime = 0
		end

		-- Progress under the strip.
		local barY = stripY + S(78)
		draw.RoundedBox(S(2), x1, barY, x2 - x1, S(4), Theme.line)
		draw.RoundedBox(S(2), x1, barY, (x2 - x1) * math.min(window.onTime / data.duration, 1), S(4), Theme.accent)
	end,

	press = function(window)
		window.pressed = true
		window:MouseCapture(true)
	end,

	release = function(window)
		window.pressed = false
		window:MouseCapture(false)
	end,
}

-- The window -----------------------------------------------------------------------

local WIDTH, HEIGHT = 540, 440
local HEADER_H, FOOTER_H = 56, 118

local function paintWindow(window, w, h)
	local pad = S(22)
	local step = steps[window.checkType]

	HeistFlock.DrawBox(0, 0, w, h, ColorAlpha(Theme.background, 245), Theme.line, S(6))

	-- Header: what this is, and the tamper meter (time left).
	draw.SimpleText(L(window.checkType .. "_title"), "HeistFlock.Heading", pad, S(18), Theme.text)

	local timeLeft = math.Clamp((window.deadline - CurTime()) / window.timeLimit, 0, 1)
	local danger = 1 - timeLeft
	local meterColor = danger < 0.6 and Theme.accent or (danger < 0.85 and Theme.amber or Theme.red)
	local meterW = S(110)
	local mx, my = w - pad - meterW, S(24)
	draw.SimpleText(L("check_tamper"), "HeistFlock.Label", mx - S(8), my + S(2), Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.RoundedBox(S(2), mx, my, meterW, S(5), Theme.line)
	draw.RoundedBox(S(2), mx, my, meterW * danger, S(5), meterColor)

	surface.SetDrawColor(Theme.line)
	surface.DrawRect(pad, S(HEADER_H), w - pad * 2, 1)

	-- The hardware.
	window.areaX, window.areaY = pad, S(HEADER_H) + S(14)
	window.areaW, window.areaH = w - pad * 2, h - S(HEADER_H) - S(FOOTER_H) - S(20)
	if step then step.paint(window, window.areaX, window.areaY, window.areaW, window.areaH) end

	-- Instructions: what to do, then what to avoid.
	local textY = h - S(FOOTER_H) + S(6)
	surface.SetDrawColor(Theme.line)
	surface.DrawRect(pad, textY - S(8), w - pad * 2, 1)

	for _, line in ipairs(wrapText(L(window.checkType .. "_do"), "HeistFlock.Body", w - pad * 2)) do
		draw.SimpleText(line, "HeistFlock.Body", pad, textY, Theme.text)
		textY = textY + S(19)
	end
	textY = textY + S(2)
	HeistFlock.DrawIcon("alert", pad, textY + S(1), S(13), Theme.amber)
	for _, line in ipairs(wrapText(L(window.checkType .. "_avoid"), "HeistFlock.Small", w - pad * 2 - S(20))) do
		draw.SimpleText(line, "HeistFlock.Small", pad + S(20), textY, Theme.textDim)
		textY = textY + S(17)
	end

	if window.answered then
		draw.SimpleText(L("check_waiting"), "HeistFlock.Body", w - pad, h - S(26), Theme.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	elseif not isReady(window) then
		draw.SimpleText(L("check_steady"), "HeistFlock.Body", w - pad, h - S(26), Theme.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

-- startTime and deadline are absolute CurTime() values from the server.
local function openWindow(checkId, cameraId, checkType, data, startTime, deadline)
	if IsValid(activeWindow) then activeWindow:Remove() end

	local window = vgui.Create("EditablePanel")
	window:SetSize(S(WIDTH), S(HEIGHT))
	window:Center()
	window:MakePopup()
	window:SetKeyboardInputEnabled(false)
	window:SetAlpha(0)
	window:AlphaTo(255, 0.12)

	window.checkId = checkId
	window.cameraId = cameraId
	window.checkType = steps[checkType] and checkType or "screws"
	window.data = data
	window.startTime = startTime
	window.deadline = deadline
	window.timeLimit = math.max(deadline - CurTime(), 0.1)

	local step = steps[window.checkType]
	if step.setup then step.setup(window) end

	window.Paint = paintWindow

	window.OnMousePressed = function(self, mouseCode)
		-- Clicks during the short intro don't count, for every step.
		if mouseCode ~= MOUSE_LEFT or self.answered or not step.press or not isReady(self) then return end
		step.press(self, self:CursorPos())
	end

	window.OnMouseReleased = function(self, mouseCode)
		if mouseCode ~= MOUSE_LEFT or not step.release then return end
		step.release(self)
	end

	window.Think = function(self)
		-- Safety net in case the server's result never arrives.
		if CurTime() > self.deadline + 3 then
			self:Remove()
		end
	end

	local backOff = UI.Button(window, L("check_back_off"), function()
		sendAnswer(window, {}, true)
	end, { style = "ghost" })
	backOff:SetPos(S(12), window:GetTall() - S(26) - backOff:GetTall() / 2)

	surface.PlaySound("buttons/blip1.wav")
	activeWindow = window
end

net.Receive("HeistFlock_SkillCheck", function()
	local checkId = net.ReadUInt(31)
	local cameraId = net.ReadUInt(16)
	local checkType = net.ReadString()
	local data = net.ReadTable()
	local startTime = net.ReadDouble()
	local deadline = net.ReadDouble()

	openWindow(checkId, cameraId, checkType, data, startTime, deadline)
end)

net.Receive("HeistFlock_SkillResult", function()
	local passed = net.ReadBool()
	local message = net.ReadString()

	-- Close straight away so the player is free to move; the result shows
	-- on the HUD instead (see cl_hud.lua).
	if IsValid(activeWindow) then
		activeWindow:Remove()
	end

	-- An empty message means "just close", e.g. the player walked away.
	if message == "" then return end

	HeistFlock.ShowSkillResult(passed, message)
	surface.PlaySound(passed and "buttons/button9.wav" or "buttons/button10.wav")
end)
