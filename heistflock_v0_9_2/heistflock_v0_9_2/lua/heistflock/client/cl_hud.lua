-- What players see while stripping cameras:
--   a prompt at the camera head when you look at it (in smash mode with
--   the stage's integrity bar),
--   a prompt over parts on the ground,
--   a progress card while you work (steps mode),
--   a result toast after each skill check (steps mode),
--   a payout card when a camera is finished.

local Config = HeistFlock.Config
local Theme = HeistFlock.Theme
local S = HeistFlock.S
local L = HeistFlock.L

local PROMPT_RANGE_MULTIPLIER = 1.6 -- the prompt appears a little before you're in range
local PART_PROMPT_RANGE = 96       -- same as the server's pick-up range
local PAYOUT_SHOW_TIME = 5
local RESULT_SHOW_TIME = 2.5

local progressAlpha = 0
local progressInfo = { name = "", stage = 1, fraction = 0, checkActive = false }
local payout       -- { amount, paid, wanted, detail, shownAt }
local skillResult  -- { passed, message, shownAt }

-- The camera the player is working on, if any (set by the server).
local function getWorkingCamera(ply)
	local cam = ply:GetNW2Entity("HeistFlock_Camera")
	if IsValid(cam) and cam:GetWorker() == ply and cam:GetStageLength() > 0 then
		return cam
	end
end

-- The camera the player is looking at, if close enough for a prompt.
local function getLookedAtCamera(ply)
	local cam = ply:GetEyeTrace().Entity
	if not IsValid(cam) or cam:GetClass() ~= "heistflock_camera" then return end

	local eyes = ply:EyePos()
	if eyes:DistToSqr(cam:NearestPoint(eyes)) > (Config.MaxDistance * PROMPT_RANGE_MULTIPLIER) ^ 2 then return end

	return cam
end

-- Prompt -------------------------------------------------------------------

-- The key to show (or nil), the text, and its color.
local function getPrompt(ply, cam)
	if cam:GetStage() >= #Config.Stages then
		return nil, L("prompt_done"), Theme.textDim
	end

	local worker = cam:GetWorker()
	if IsValid(worker) and worker ~= ply then
		return nil, L("prompt_in_use", { name = worker:Nick() }), Theme.amber
	end

	if HeistFlock.IsUsingPliers(ply) then
		return "LMB", L("prompt_strip"), Theme.text
	end

	if Config.RequirePliers then
		return nil, L("prompt_pliers"), Theme.red
	end

	return "E", L("prompt_strip"), Theme.text
end

local function drawPrompt(ply, cam)
	local anchor = (HeistFlock.GetHousingPos(cam) + Vector(0, 0, 12)):ToScreen()
	if not anchor.visible then return end

	local key, text, color = getPrompt(ply, cam)
	local stageText = cam:GetStage() .. "/" .. #Config.Stages

	surface.SetFont("HeistFlock.Body")
	local textW = surface.GetTextSize(text)
	surface.SetFont("HeistFlock.MonoSm")
	local stageW = surface.GetTextSize(stageText)

	local keyW = key and S(30) or 0
	local w = S(12) + keyW + textW + S(14) + stageW + S(12)
	local h = S(34)
	local x, y = math.Round(anchor.x - w / 2), math.Round(anchor.y - h)

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 235), Theme.line)

	local cursor = x + S(12)
	if key then
		HeistFlock.DrawKey(key, cursor, y + (h - S(20)) / 2)
		cursor = cursor + keyW
	end
	draw.SimpleText(text, "HeistFlock.Body", cursor, y + h / 2, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(stageText, "HeistFlock.MonoSm", x + w - S(12), y + h / 2, Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

-- Smash mode prompt: what to do, the stage, and what's left of it.

local function holdsSmashTool(ply)
	local weapon = ply:GetActiveWeapon()
	return IsValid(weapon) and table.HasValue(Config.Smash.Tools, weapon:GetClass())
end

-- The job rules from the settings (the server checks them again). Players
-- who can't smash cameras just see what state the camera is in.
local function jobCanSmash(ply)
	if not DarkRP or not ply.getJobTable then return true end
	if Config.BlockPolice and ply:isCP() then return false end

	local job = ply:getJobTable()
	local listed = job ~= nil and HeistFlock.IsJobListed(job)
	if Config.JobMode == "whitelist" then return listed end
	return not listed
end

local function drawSmashPrompt(ply, cam)
	local anchor = (HeistFlock.GetHousingPos(cam) + Vector(0, 0, 14)):ToScreen()
	if not anchor.visible then return end

	local stageCount = #Config.Stages
	local stage = cam:GetStage()
	local stripped = stage >= stageCount

	local key, text, color
	if stripped then
		text, color = L("prompt_smashed"), Theme.textDim
	elseif not jobCanSmash(ply) then
		text, color = L("prompt_camera"), Theme.textDim
	elseif holdsSmashTool(ply) then
		key, text, color = "LMB", L("prompt_smash"), Theme.text
	else
		text, color = L("prompt_tool"), Theme.red
	end

	-- Integrity: how much of the current stage is left. Eased, so a hit
	-- knocks a chunk off and a new stage refills.
	local needed = stripped and 1 or math.max(Config.Stages[stage + 1].hits, 1)
	local target = stripped and 0 or math.Clamp(1 - cam:GetHits() / needed, 0, 1)
	cam.ShownIntegrity = Lerp(math.min(FrameTime() * 12, 1), cam.ShownIntegrity or target, target)
	local integrity = cam.ShownIntegrity

	local stageText = L("stage_of", { stage = math.min(stage + 1, stageCount), total = stageCount })

	surface.SetFont("HeistFlock.Body")
	local textW = surface.GetTextSize(text)
	surface.SetFont("HeistFlock.MonoSm")
	local stageW = surface.GetTextSize(stageText)

	local pad = S(12)
	local keyW = key and S(30) or 0
	local w = math.max(pad + keyW + textW + S(16) + stageW + pad, S(220))
	local h = S(50)
	local x, y = math.Round(anchor.x - w / 2), math.Round(anchor.y - h)

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 235), Theme.line)

	local cursor = x + pad
	local rowY = y + S(18)
	if key then
		HeistFlock.DrawKey(key, cursor, rowY - S(10))
		cursor = cursor + keyW
	end
	draw.SimpleText(text, "HeistFlock.Body", cursor, rowY, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(stageText, "HeistFlock.MonoSm", x + w - pad, rowY, Theme.textFaint, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	local barX, barY, barW, barH = x + pad, y + h - S(14), w - pad * 2, S(5)
	local barColor = integrity > 0.5 and Theme.accent or (integrity > 0.25 and Theme.amber or Theme.red)
	draw.RoundedBox(S(2), barX, barY, barW, barH, Theme.raised)
	if integrity > 0.01 then
		draw.RoundedBox(S(2), barX, barY, math.max(barW * integrity, S(4)), barH, barColor)
	end
end

-- Parts on the ground -------------------------------------------------------

local function getLookedAtPart(ply)
	local trace = ply:GetEyeTrace()
	local part = trace.Entity
	if not IsValid(part) or part:GetClass() ~= "heistflock_part" then return end
	if trace.HitPos:DistToSqr(ply:EyePos()) > PART_PROMPT_RANGE ^ 2 then return end
	return part
end

local function drawPartPrompt(ply, part)
	local anchor = (part:WorldSpaceCenter() + Vector(0, 0, 10)):ToScreen()
	if not anchor.visible then return end

	local material = HeistFlock.GetMaterial(part:GetMaterialId())
	if not material then return end

	local amount = part:GetAmount()
	local title = amount .. "x " .. material.name
	if Config.Parts.Provider == "money" and material.value > 0 then
		title = title .. "  ·  " .. HeistFlock.FormatMoney(material.value * amount)
	end

	-- Reserved for whoever broke it, picked up, or taken as evidence.
	local key, action, actionColor = "E", L("part_pick_up"), Theme.text
	local owner = part:GetPartOwner()
	local reservedFor = part:GetOwnerUntil() - CurTime()
	local isPolice = DarkRP and ply.isCP and ply:isCP()

	if Config.Parts.PoliceConfiscate and isPolice then
		action = L("part_evidence")
	elseif IsValid(owner) and owner ~= ply and reservedFor > 0 then
		key, actionColor = nil, Theme.amber
		action = L("part_whose", { name = owner:Nick(), seconds = math.ceil(reservedFor) })
	end

	surface.SetFont("HeistFlock.Body")
	local titleW = surface.GetTextSize(title)
	local actionW = surface.GetTextSize(action)

	local pad = S(12)
	local keyW = key and S(30) or 0
	local w = math.max(titleW, keyW + actionW) + pad * 2
	local h = S(52)
	local x, y = math.Round(anchor.x - w / 2), math.Round(anchor.y - h)

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 235), Theme.line)
	draw.SimpleText(title, "HeistFlock.Body", x + pad, y + S(15), Theme.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	local cursor = x + pad
	if key then
		HeistFlock.DrawKey(key, cursor, y + S(27))
		cursor = cursor + keyW
	end
	draw.SimpleText(action, "HeistFlock.Body", cursor, y + S(37), actionColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- Progress -----------------------------------------------------------------

local function drawProgress(alpha)
	local info = progressInfo
	local w, h = S(380), S(78)
	local x, y = math.Round(ScrW() / 2 - w / 2), math.Round(ScrH() * 0.76)
	local a = 255 * alpha
	local pad = S(14)
	local stageCount = #Config.Stages

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 240 * alpha), ColorAlpha(Theme.line, a))

	draw.SimpleText(info.name, "HeistFlock.Heading", x + pad, y + S(12), ColorAlpha(Theme.text, a))
	draw.SimpleText(L("stage_of", { stage = info.stage, total = stageCount }), "HeistFlock.MonoSm",
		x + w - pad, y + S(14), ColorAlpha(Theme.textFaint, a), TEXT_ALIGN_RIGHT)

	-- One bar segment per stage: done, filling, still to do.
	local barY, barH, gap = y + S(38), S(5), S(4)
	local segmentW = (w - pad * 2 - gap * (stageCount - 1)) / stageCount
	local fillColor = info.checkActive and Theme.amber or Theme.accent

	for i = 1, stageCount do
		local segX = x + pad + (i - 1) * (segmentW + gap)
		draw.RoundedBox(S(2), segX, barY, segmentW, barH, ColorAlpha(Theme.raised, a))

		local fill = i < info.stage and 1 or (i == info.stage and info.fraction or 0)
		if fill > 0 then
			draw.RoundedBox(S(2), segX, barY, math.max(segmentW * fill, S(4)), barH, ColorAlpha(fillColor, a))
		end
	end

	local hint
	if info.checkActive then
		hint = L("hint_check")
	elseif Config.RequireHold then
		hint = L("hint_hold")
	else
		hint = L("hint_stay")
	end

	local hintY = y + S(56)
	draw.SimpleText(hint, "HeistFlock.Small", x + pad, hintY, ColorAlpha(info.checkActive and Theme.amber or Theme.textDim, a))
	draw.SimpleText(math.floor(info.fraction * 100) .. "%", "HeistFlock.MonoSm", x + w - pad, hintY + S(1),
		ColorAlpha(Theme.textDim, a), TEXT_ALIGN_RIGHT)
end

-- Skill check result -------------------------------------------------------

-- Called by cl_skillchecks.lua when the server judges a check.
function HeistFlock.ShowSkillResult(passed, message)
	skillResult = { passed = passed, message = message, shownAt = CurTime() }
end

local function drawSkillResult()
	local age = CurTime() - skillResult.shownAt
	if age > RESULT_SHOW_TIME then
		skillResult = nil
		return
	end

	local fade = math.Clamp((RESULT_SHOW_TIME - age) / 0.4, 0, 1)
	local rise = math.ease.OutCubic(math.min(age / 0.25, 1))
	local a = 255 * fade
	local color = skillResult.passed and Theme.accent or Theme.red
	local icon = skillResult.passed and "check" or "alert"

	surface.SetFont("HeistFlock.Heading")
	local textW = surface.GetTextSize(skillResult.message)
	local w, h = textW + S(58), S(40)
	local x = math.Round(ScrW() / 2 - w / 2)
	local y = math.Round(ScrH() * 0.76 - h - S(10) + (1 - rise) * S(10))

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 240 * fade), ColorAlpha(color, a))
	HeistFlock.DrawIcon(icon, x + S(14), y + (h - S(18)) / 2, S(18), ColorAlpha(color, a))
	draw.SimpleText(skillResult.message, "HeistFlock.Heading", x + S(42), y + h / 2, ColorAlpha(Theme.text, a),
		TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- Payout -------------------------------------------------------------------

net.Receive("HeistFlock_Payout", function()
	payout = {
		amount = net.ReadUInt(32),
		paid = net.ReadBool(),
		wanted = net.ReadBool(),
		detail = net.ReadString(),
		shownAt = CurTime(),
	}
	surface.PlaySound("ambient/levels/labs/coinslot1.wav")
end)

local function drawPayout()
	local age = CurTime() - payout.shownAt
	if age > PAYOUT_SHOW_TIME then
		payout = nil
		return
	end

	local slide = math.ease.OutCubic(math.min(age / 0.35, 1))
	local fade = math.Clamp((PAYOUT_SHOW_TIME - age) / 0.5, 0, 1)
	local a = 255 * fade

	surface.SetFont("HeistFlock.Small")
	local w = math.max(S(300), surface.GetTextSize(payout.detail) + S(32)) -- a long parts list widens the card
	local h = payout.wanted and S(100) or S(78)
	local x = math.Round(ScrW() - (w + S(24)) * slide)
	local y = math.Round(ScrH() * 0.3)
	local pad = S(16)

	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 240 * fade), ColorAlpha(Theme.line, a))
	draw.RoundedBox(0, x, y + S(10), S(2), h - S(20), ColorAlpha(Theme.accent, a))

	local title = Config.StripMode == "smash" and L("payout_smash_title") or L("payout_title")
	draw.SimpleText(string.upper(title), "HeistFlock.Label", x + pad, y + S(12), ColorAlpha(Theme.textFaint, a))
	-- No money (a smash bonus of 0, crafting into an inventory, or sandbox): lead with the title instead.
	local headline = payout.paid and ("+" .. HeistFlock.FormatMoney(payout.amount)) or title
	draw.SimpleText(headline, payout.paid and "HeistFlock.MonoBig" or "HeistFlock.Title", x + pad, y + S(26), ColorAlpha(Theme.accent, a))
	draw.SimpleText(payout.detail, "HeistFlock.Small", x + pad, y + S(58), ColorAlpha(Theme.textDim, a))

	if payout.wanted then
		HeistFlock.DrawIcon("alert", x + pad, y + S(78), S(14), ColorAlpha(Theme.red, a))
		draw.SimpleText(L("now_wanted"), "HeistFlock.Small", x + pad + S(20), y + S(77), ColorAlpha(Theme.red, a))
	end
end

-- Drawing ------------------------------------------------------------------

hook.Add("HUDPaint", "HeistFlock_HUD", function()
	local ply = LocalPlayer()
	local workingCam = getWorkingCamera(ply)

	if workingCam then
		local stage = workingCam:GetStage() + 1
		progressInfo.name = Config.Stages[stage] and Config.Stages[stage].name or ""
		progressInfo.stage = stage
		progressInfo.fraction = workingCam:GetStageProgress()
		progressInfo.checkActive = workingCam:GetCheckActive()
	else
		local cam = getLookedAtCamera(ply)
		if cam then
			if Config.StripMode == "smash" then
				drawSmashPrompt(ply, cam)
			else
				drawPrompt(ply, cam)
			end
		else
			local part = getLookedAtPart(ply)
			if part then drawPartPrompt(ply, part) end
		end
	end

	-- Fade the progress card in and out instead of popping.
	progressAlpha = math.Approach(progressAlpha, workingCam and 1 or 0, FrameTime() * 6)
	if progressAlpha > 0 then drawProgress(progressAlpha) end

	if skillResult then drawSkillResult() end
	if payout then drawPayout() end
end)
