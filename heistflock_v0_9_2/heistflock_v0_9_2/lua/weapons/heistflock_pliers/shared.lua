-- Pliers. Uses crowbar models as placeholders until custom ones are made.
--   Smash mode: left click swings at a Flock camera. Only cameras take
--               damage from them, so they're not a weapon.
--   Steps mode: left click a Flock camera to start stripping it, then stay close.

SWEP.PrintName = "Pliers"
SWEP.Author = "Heist Flock"
SWEP.Instructions = "Left click a Flock camera to smash it apart, then press E on the parts that fall off to sell them."
SWEP.Category = "Heist Flock"
SWEP.Spawnable = true
SWEP.AdminOnly = true

SWEP.Slot = 1
SWEP.SlotPos = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.UseHands = true
SWEP.HoldType = "melee"

SWEP.ViewModel = HeistFlock and HeistFlock.Config.PliersViewModel or "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = HeistFlock and HeistFlock.Config.PliersWorldModel or "models/weapons/w_crowbar.mdl"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true -- keeps firing while left click is held
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local WORK_SWING_DELAY = 0.7 -- steps mode: seconds between swings while working
local IDLE_CHECK_DELAY = 0.2 -- steps mode: how often to check for a camera when not aiming at one
local SMASH_SWING_DELAY = 0.5 -- smash mode: seconds between swings
local SMASH_RANGE = 75
local SMASH_DAMAGE = 10       -- only counted as one hit; the number doesn't matter

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

-- The camera the owner is aiming at and can reach, if any.
function SWEP:GetTargetCamera()
	local owner = self:GetOwner()
	local cam = owner:GetEyeTrace().Entity

	if IsValid(cam) and cam:GetClass() == "heistflock_camera" and HeistFlock.IsInRange(owner, cam) then
		return cam
	end
end

-- Smash mode: one swing. Hits a camera if there's one in reach.
function SWEP:Smash(owner)
	self:SetNextPrimaryFire(CurTime() + SMASH_SWING_DELAY)

	local eyes = owner:EyePos()
	local trace = util.TraceHull({
		start = eyes,
		endpos = eyes + owner:GetAimVector() * SMASH_RANGE,
		mins = Vector(-4, -4, -4),
		maxs = Vector(4, 4, 4),
		filter = owner,
		mask = MASK_SHOT_HULL,
	})
	local cam = trace.Entity
	local hitCamera = IsValid(cam) and cam:GetClass() == "heistflock_camera"

	if IsFirstTimePredicted() then
		self:SendWeaponAnim(trace.Hit and ACT_VM_HITCENTER or ACT_VM_MISSCENTER)
		owner:SetAnimation(PLAYER_ATTACK1)
		if not trace.Hit then
			self:EmitSound("Weapon_Crowbar.Single") -- a swing at nothing
		elseif not hitCamera then
			self:EmitSound("Weapon_Crowbar.Melee_HitWorld") -- the camera plays its own clang
		end
	end

	if SERVER and hitCamera then
		local dmg = DamageInfo()
		dmg:SetAttacker(owner)
		dmg:SetInflictor(self)
		dmg:SetDamage(SMASH_DAMAGE)
		dmg:SetDamageType(DMG_CLUB)
		dmg:SetDamagePosition(trace.HitPos)
		dmg:SetDamageForce(owner:GetAimVector() * 100)
		cam:TakeDamageInfo(dmg)
	end
end

-- Left click: a swing in smash mode, or starts work on the camera you're
-- aiming at in steps mode.
function SWEP:PrimaryAttack()
	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	if HeistFlock.Config.StripMode == "smash" then
		self:Smash(owner)
		return
	end

	local cam = self:GetTargetCamera()

	-- Only swing when there's a camera to work on.
	if not cam then
		self:SetNextPrimaryFire(CurTime() + IDLE_CHECK_DELAY)
		return
	end

	self:SetNextPrimaryFire(CurTime() + WORK_SWING_DELAY)

	-- Prediction can run this more than once per click; animate only once.
	if IsFirstTimePredicted() then
		self:SendWeaponAnim(ACT_VM_HITCENTER)
		owner:SetAnimation(PLAYER_ATTACK1)
	end

	-- Starting work happens on the server only.
	-- A held button keeps firing; only a fresh click may switch cameras.
	-- The click is remembered in Think, because the swing delay can push this
	-- call a moment past the tick the button went down.
	if SERVER then
		local freshPress = owner:KeyPressed(IN_ATTACK)
			or CurTime() - (self.LastPressAt or -1) <= WORK_SWING_DELAY + 0.1
		self.LastPressAt = nil
		cam:TryStart(owner, freshPress)
	end
end

-- The camera this weapon's owner is working on, if any.
function SWEP:GetWorkingCamera()
	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	local cam = owner:GetNW2Entity("HeistFlock_Camera")
	if IsValid(cam) and cam:GetWorker() == owner and not cam:GetCheckActive() then
		return cam
	end
end

-- While working, keep swinging on its own so nobody has to keep clicking.
function SWEP:Think()
	if CLIENT then return end

	local owner = self:GetOwner()
	if IsValid(owner) and owner:KeyPressed(IN_ATTACK) then
		self.LastPressAt = CurTime() -- a fresh click, for PrimaryAttack
	end

	if CurTime() < (self.NextWorkSwing or 0) then return end

	local cam = self:GetWorkingCamera()
	if not cam then return end

	self.NextWorkSwing = CurTime() + WORK_SWING_DELAY + math.Rand(0, 0.25)

	self:SendWeaponAnim(ACT_VM_HITCENTER)
	owner:SetAnimation(PLAYER_ATTACK1)
	owner:EmitSound("physics/metal/metal_computer_impact_bullet" .. math.random(1, 3) .. ".wav", 60, math.random(95, 110))
end

function SWEP:SecondaryAttack()
end

if CLIENT then
	local ICON = Material("entities/heistflock_pliers.png", "smooth")

	-- The weapon selection icon (the menu when scrolling through weapons).
	function SWEP:DrawWeaponSelection(x, y, width, height, alpha)
		if ICON:IsError() then -- icon didn't download: the name instead
			draw.SimpleText(self.PrintName, "DermaLarge", x + width / 2, y + height / 2, Color(255, 255, 255, alpha),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end

		local size = math.min(width, height) * 0.8

		surface.SetDrawColor(255, 255, 255, alpha)
		surface.SetMaterial(ICON)
		surface.DrawTexturedRect(x + (width - size) / 2, y + (height - size) / 2, size, size)
	end
end
