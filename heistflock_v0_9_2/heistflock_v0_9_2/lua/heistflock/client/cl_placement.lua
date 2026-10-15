-- Placing and moving cameras with a preview, for admins. The preview follows
-- the crosshair; the real camera only moves once, when you click, so there's
-- none of the lag of dragging it with the physgun.
--
--   Left click  place          Scroll  rotate
--   R           face me again  Right click  cancel

local Theme = HeistFlock.Theme
local S = HeistFlock.S
local L = HeistFlock.L

local PLACE_RANGE = 1500
local ROTATE_STEP = 15

local placing -- { cameraId, yawOffset, onFinish, spot }
local ghostModel

-- cameraId: the camera to move, or nil to place a new one.
-- onFinish: runs when placing ends either way (e.g. to show the menu again).
function HeistFlock.StartPlacement(cameraId, onFinish)
	placing = { cameraId = cameraId or 0, yawOffset = 0, onFinish = onFinish }
	surface.PlaySound("buttons/lightswitch2.wav")
end

function HeistFlock.IsPlacing()
	return placing ~= nil
end

local function finish()
	local onFinish = placing and placing.onFinish
	placing = nil
	if onFinish then onFinish() end
end

-- Where the camera would go: pos, angle, and whether that spot is allowed.
local function findSpot()
	local ply = LocalPlayer()
	local eyes = ply:EyePos()
	local trace = util.TraceLine({
		start = eyes,
		endpos = eyes + ply:GetAimVector() * PLACE_RANGE,
		filter = function(ent) -- the server ignores cameras too
			return ent ~= ply and ent:GetClass() ~= "heistflock_camera"
		end,
		mask = MASK_SOLID,
	})
	if not trace.Hit then return end

	local ang = Angle(0, ply:EyeAngles().y + 180 + placing.yawOffset, 0) -- faces you, plus any rotation

	if HeistFlock.UsesBuiltInModel() then
		return trace.HitPos, ang, trace.HitNormal.z >= 0.7 -- the pole needs the ground
	end
	return trace.HitPos + trace.HitNormal * 10, ang, true
end

local function confirm()
	local spot = placing.spot
	if not spot or not spot.ok then
		surface.PlaySound("buttons/button10.wav")
		return
	end

	net.Start("HeistFlock_PlaceAt")
	net.WriteUInt(placing.cameraId, 16)
	net.WriteVector(spot.pos)
	net.WriteFloat(spot.ang.y)
	net.SendToServer()

	surface.PlaySound("buttons/button14.wav")
	finish()
end

-- Take over clicks, scroll and R while placing.
hook.Add("PlayerBindPress", "HeistFlock_Placement", function(ply, bind, pressed)
	if not placing or not pressed then return end

	if string.find(bind, "+attack2", 1, true) then
		finish()
		return true
	elseif string.find(bind, "+attack", 1, true) then
		confirm()
		return true
	elseif string.find(bind, "invprev", 1, true) then
		placing.yawOffset = placing.yawOffset + ROTATE_STEP
		return true
	elseif string.find(bind, "invnext", 1, true) then
		placing.yawOffset = placing.yawOffset - ROTATE_STEP
		return true
	elseif string.find(bind, "+reload", 1, true) then
		placing.yawOffset = 0
		return true
	end
end)

-- The see-through preview.
hook.Add("PostDrawTranslucentRenderables", "HeistFlock_Placement", function(depth, skybox)
	if not placing or depth or skybox then return end

	if not LocalPlayer():Alive() then
		finish()
		return
	end

	local pos, ang, ok = findSpot()
	placing.spot = pos and { pos = pos, ang = ang, ok = ok } or nil
	if not pos then return end

	local tint = ok and Theme.accent or Theme.red
	render.SetBlend(0.55)

	if HeistFlock.UsesBuiltInModel() then
		if HeistFlock.DrawBuiltInCamera then
			HeistFlock.DrawBuiltInCamera(pos, ang, 0, tint)
		end
	else
		local model = HeistFlock.Config.Model
		if not IsValid(ghostModel) or ghostModel:GetModel() ~= model then
			if IsValid(ghostModel) then ghostModel:Remove() end
			ghostModel = ClientsideModel(model, RENDERGROUP_TRANSLUCENT)
			if IsValid(ghostModel) then ghostModel:SetNoDraw(true) end
		end
		if IsValid(ghostModel) then
			ghostModel:SetPos(pos)
			ghostModel:SetAngles(ang)
			ghostModel:SetupBones()
			render.SetColorModulation(tint.r / 255, tint.g / 255, tint.b / 255)
			ghostModel:DrawModel()
			render.SetColorModulation(1, 1, 1)
		end
	end

	render.SetBlend(1)
end)

-- The controls, at the bottom of the screen.
hook.Add("HUDPaint", "HeistFlock_Placement", function()
	if not placing then return end

	local controls = {
		{ "LMB", placing.cameraId > 0 and "Move here" or "Place" },
		{ "Scroll", "Rotate" },
		{ "R", "Face me" },
		{ "RMB", "Cancel" },
	}

	surface.SetFont("HeistFlock.Small")
	local totalW = 0
	for _, control in ipairs(controls) do
		surface.SetFont("HeistFlock.MonoSm")
		local keyW = math.max(surface.GetTextSize(control[1]) + S(10), S(20))
		surface.SetFont("HeistFlock.Small")
		control.width = keyW + S(8) + surface.GetTextSize(control[2]) + S(20)
		totalW = totalW + control.width
	end

	local w, h = totalW + S(16), S(40)
	local x, y = ScrW() / 2 - w / 2, ScrH() - S(140)
	HeistFlock.DrawBox(x, y, w, h, ColorAlpha(Theme.background, 235), Theme.line)

	local cursor = x + S(16)
	for _, control in ipairs(controls) do
		local keyW = HeistFlock.DrawKey(control[1], cursor, y + (h - S(20)) / 2)
		draw.SimpleText(control[2], "HeistFlock.Small", cursor + keyW + S(8), y + h / 2, Theme.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		cursor = cursor + control.width
	end

	local spot = placing.spot
	if spot and not spot.ok then
		draw.SimpleText(L("look_at_ground"), "HeistFlock.Body", ScrW() / 2, y - S(14), Theme.red, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	end
end)
