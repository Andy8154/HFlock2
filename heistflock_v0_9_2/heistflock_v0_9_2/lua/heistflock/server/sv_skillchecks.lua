-- Hands-on steps ("skill checks"): the server makes each one, sends it to the
-- worker, and judges the answer, so a step can't be skipped.
--
-- These are gameplay, not anti-cheat: everything a step needs to draw has to
-- be sent to the client, so a modified client could still solve them.
--
--   screws   hold on each security screw until it backs out
--   pry      hold to lean on the pry bar, let go when the lid gives
--   battery  unplug the battery leads in the order on the service sticker
--   cable    snip the cable named on the work tag (not the tamper loop)
--   board    hold and sway to rock the modem board out, without whipping it
--   solder   keep the iron on a moving gold contact until it lifts

util.AddNetworkString("HeistFlock_SkillCheck")
util.AddNetworkString("HeistFlock_SkillAnswer")
util.AddNetworkString("HeistFlock_SkillResult")

local Config = HeistFlock.Config

local INTRO_DELAY = 0.6       -- timed steps start moving after this many seconds
local MIN_PRESS_WINDOW = 0.25 -- how old a timed press may be when it arrives, at least
local nextCheckId = 0

-- Making steps ----------------------------------------------------------------
-- Each maker returns the data the client needs to draw the step.
local makers = {}

function makers.screws()
	return { count = 4, holdTime = 0.9 }
end

function makers.pry()
	local width = 0.14
	return {
		zoneStart = math.Rand(0.5, 0.86 - width),
		zoneWidth = width,
		fillSpeed = math.Rand(0.42, 0.55), -- share of the gauge filled per second held
	}
end

-- Leads: 1 = GND, 2 = 12V, 3 = SOLAR.
function makers.battery()
	local order, layout = { 1, 2, 3 }, { 1, 2, 3 }
	table.Shuffle(order)  -- the order on the sticker
	table.Shuffle(layout) -- where each lead sits on the battery, left to right
	return { order = order, layout = layout }
end

-- Cables: 1 SOLAR IN, 2 LTE ANT, 3 CAM DATA, 4 IR LED, 5 BATT, 6 TAMPER.
local TAMPER_CABLE = 6

function makers.cable()
	local others = { 1, 2, 3, 4, 5 }
	table.Shuffle(others)

	local cables = { others[1], others[2], others[3], others[4], TAMPER_CABLE }
	table.Shuffle(cables)

	return { cables = cables, target = others[math.random(1, 4)] }
end

function makers.board()
	return { rocks = 6, minRockTime = 0.18 } -- faster swings than this bend the contacts
end

function makers.solder()
	return { duration = 3.5, speed = math.Rand(0.3, 0.42), maxOffTime = 0.6 }
end

-- A step for a stage, from the stage's own "checks" list (only the steps that
-- are turned on). Avoids repeating the last one when there's a choice.
-- Returns nil when the stage has no steps turned on.
function HeistFlock.PickCheckType(lastType, stagePool)
	local candidates = HeistFlock.GetStageCheckTypes(stagePool)
	if #candidates == 0 then return nil end

	local others = {}
	for _, checkType in ipairs(candidates) do
		if checkType ~= lastType then table.insert(others, checkType) end
	end
	if #others == 0 then others = candidates end

	return others[math.random(#others)]
end

-- checkType must be a known step (PickCheckType only returns known ones).
function HeistFlock.CreateSkillCheck(checkType)

	-- Each step gets its own number, so a very late answer to an old step
	-- can never be judged against a newer one.
	nextCheckId = (nextCheckId + 1) % 2 ^ 31

	return {
		id = nextCheckId,
		type = checkType,
		data = makers[checkType](),
		createdAt = CurTime(),
		startTime = CurTime() + INTRO_DELAY,
		deadline = CurTime() + Config.SkillCheckTime,
	}
end

-- Checking answers ------------------------------------------------------------
-- Each checker returns true, or false and the language key of the reason.
-- Anything odd in an answer is a fail; the receiver treats errors as fails too.
local checkers = {}

local function isRealNumber(value)
	return isnumber(value) and value == value
end

local function isWholeNumberInRange(value, low, high)
	return isnumber(value) and value == math.floor(value) and value >= low and value <= high
end

-- Seconds since the step appeared, by the server's clock.
local function elapsed(check)
	return CurTime() - check.createdAt
end

-- A client CurTime() from an answer. CurTime() is synced between client and
-- server, so this is when the player really clicked. It can't be in the
-- future, and can't be older than the player's ping plus a margin.
local function clampPressTime(time, ply)
	local now = CurTime()
	local window = math.max(MIN_PRESS_WINDOW, ply:Ping() / 1000 + 0.15)
	return math.Clamp(time, now - window, now)
end

-- answer.order = the screws in the order they came out; each one once.
function checkers.screws(check, answer)
	local count = check.data.count
	if not istable(answer.order) or #answer.order ~= count then return false, "result_wrong" end

	local seen = {}
	for i = 1, count do
		local screw = answer.order[i]
		if not isWholeNumberInRange(screw, 1, count) or seen[screw] then return false, "result_wrong" end
		seen[screw] = true
	end

	-- Every screw needs holding for a moment; this can't have been quicker.
	if elapsed(check) < count * check.data.holdTime * 0.75 then return false, "result_wrong" end
	return true
end

-- answer.pressTime / answer.releaseTime = client CurTime() at press and release.
function checkers.pry(check, answer, ply)
	if not isRealNumber(answer.pressTime) or not isRealNumber(answer.releaseTime) then return false, "result_wrong" end

	local release = clampPressTime(answer.releaseTime, ply)
	local press = math.Clamp(answer.pressTime, check.startTime - 0.1, release)
	local fill = (release - press) * check.data.fillSpeed
	local zoneStart = check.data.zoneStart - 0.02
	local zoneEnd = check.data.zoneStart + check.data.zoneWidth + 0.02

	if fill < zoneStart then return false, "fail_not_loose" end
	if fill > zoneEnd then return false, "fail_cracked" end
	return true
end

-- answer.order = the leads unplugged, in order (1 GND, 2 12V, 3 SOLAR).
function checkers.battery(check, answer)
	if not istable(answer.order) or #answer.order == 0 then return false, "fail_short" end

	for i, lead in ipairs(answer.order) do
		if lead ~= check.data.order[i] then return false, "fail_short" end
	end
	if #answer.order ~= #check.data.order then return false, "result_wrong" end
	-- Three leads, each a separate click after the intro.
	if elapsed(check) < INTRO_DELAY + 0.3 then return false, "result_wrong" end
	return true
end

-- answer.cut = the cable snipped.
function checkers.cable(check, answer)
	if answer.cut == TAMPER_CABLE then return false, "fail_tamper" end
	if answer.cut ~= check.data.target then return false, "fail_wrong_cable" end
	-- One click, and the tag can be read during the intro, so only a small
	-- margin past it; anything quicker was sent before the step started.
	if elapsed(check) < INTRO_DELAY + 0.1 then return false, "result_wrong" end
	return true
end

-- answer.rocks = swings made, or answer.bent = true if a swing was too fast.
function checkers.board(check, answer)
	if answer.bent then return false, "fail_bent" end
	if not isWholeNumberInRange(answer.rocks, check.data.rocks, 1000) then return false, "result_wrong" end
	if elapsed(check) < check.data.rocks * check.data.minRockTime then return false, "result_wrong" end
	return true
end

-- answer.done = true, or answer.slipped = true.
function checkers.solder(check, answer)
	if answer.slipped then return false, "fail_slipped" end
	if answer.done ~= true then return false, "result_wrong" end
	if elapsed(check) < check.data.duration * 0.9 then return false, "result_wrong" end
	return true
end

-- Talking to the client -------------------------------------------------------
function HeistFlock.SendSkillCheck(ply, cam, check)
	net.Start("HeistFlock_SkillCheck")
	net.WriteUInt(check.id, 31)
	net.WriteUInt(cam:EntIndex(), 16)
	net.WriteString(check.type)
	net.WriteTable(check.data)
	net.WriteDouble(check.startTime) -- absolute times; CurTime() is synced
	net.WriteDouble(check.deadline)
	net.Send(ply)
end

function HeistFlock.SendSkillResult(ply, passed, message)
	if not IsValid(ply) then return end

	net.Start("HeistFlock_SkillResult")
	net.WriteBool(passed)
	net.WriteString(message)
	net.Send(ply)
end

-- Closes the window without a result, e.g. when the player walks away.
function HeistFlock.CloseSkillCheck(ply)
	HeistFlock.SendSkillResult(ply, false, "")
end

local MAX_ANSWER_BITS = 8192 -- real answers are a few hundred bits

net.Receive("HeistFlock_SkillAnswer", function(len, ply)
	-- Ignore oversized or rapid-fire messages before reading anything big.
	if len > MAX_ANSWER_BITS then return end
	if HeistFlock.IsThrottled(ply, "skillanswer", 0.1) then return end

	local checkId = net.ReadUInt(31)
	local cam = Entity(net.ReadUInt(16))
	local gaveUp = net.ReadBool()
	local answer = net.ReadTable()

	if not IsValid(cam) or cam:GetClass() ~= "heistflock_camera" then return end
	if cam:GetWorker() ~= ply or not cam.ActiveCheck then return end
	if cam.ActiveCheck.id ~= checkId then return end -- an answer to an older step

	local check = cam.ActiveCheck

	if CurTime() > check.deadline then
		cam:FailSkillCheck(ply, "result_too_slow")
		return
	end

	if gaveUp then
		cam:FailSkillCheck(ply, "result_gave_up")
		return
	end

	-- A broken answer must never count as a pass, so errors are failures.
	local ok, passed, reasonKey = pcall(checkers[check.type], check, answer, ply)

	if ok and passed == true then
		cam:PassSkillCheck(ply)
	else
		cam:FailSkillCheck(ply, ok and reasonKey or "result_wrong")
	end
end)
