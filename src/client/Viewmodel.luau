--!nonstrict
-- First-person viewmodel: attaches a rig to the camera and drives sway, walk bob,
-- recoil and reload offsets with springs.
--
-- Rig convention (ReplicatedStorage.Viewmodel, optional): a Model that moves as one
-- unit via PivotTo (Motor6D-welded or anchored), with
--   * a descendant named "Muzzle" (Attachment/Part) for tracer + flash origin
--   * an optional Animator and an "Animations" folder holding Animation instances
--     named "Fire", "Reload", "Equip", "Idle"
-- If no rig exists a placeholder rifle with arms is built so the weapon is usable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraRecoil = require(script.Parent:WaitForChild("CameraRecoil"))

local Viewmodel = {}
Viewmodel.__index = Viewmodel

local BASE_OFFSET = CFrame.new(0.55, -0.55, -0.9)
local BIND_NAME = "ViewmodelUpdate"

local POS_STIFFNESS, POS_DAMPING = 140, 16
local ROT_STIFFNESS, ROT_DAMPING = 120, 14
local POS_GAIN = CameraRecoil.PeakGain(POS_STIFFNESS, POS_DAMPING)
local ROT_GAIN = CameraRecoil.PeakGain(ROT_STIFFNESS, ROT_DAMPING)

local DEFAULT_RECOIL = { Z = -0.15, Pitch = 2.5 }
local DEFAULT_LIGHT = { Color = Color3.fromRGB(0, 220, 255), Range = 12, Brightness = 4, Duration = 0.05 }

-- Damped spring on a Vector3.
local Spring = {}
Spring.__index = Spring

function Spring.new(stiffness: number, damping: number)
	return setmetatable({
		K = stiffness,
		D = damping,
		Position = Vector3.zero,
		Velocity = Vector3.zero,
	}, Spring)
end

function Spring:Update(dt: number)
	dt = math.min(dt, 1 / 30)
	local accel = -self.Position * self.K - self.Velocity * self.D
	self.Velocity += accel * dt
	self.Position += self.Velocity * dt
end

function Spring:Impulse(v: Vector3)
	self.Velocity += v
end

local function buildPlaceholder(): Model
	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local function part(name: string, size: Vector3, cf: CFrame, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = model
		return p
	end

	local dark = Color3.fromRGB(35, 38, 48)
	local skin = Color3.fromRGB(226, 180, 140)

	local root = part("Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), dark)
	root.Transparency = 1
	model.PrimaryPart = root

	part("Gun", Vector3.new(0.25, 0.35, 1.6), CFrame.new(0, 0, -0.4), dark)
	part("Barrel", Vector3.new(0.12, 0.12, 0.6), CFrame.new(0, 0.05, -1.4), Color3.fromRGB(60, 64, 78))
	part("Magazine", Vector3.new(0.2, 0.5, 0.3), CFrame.new(0, -0.38, -0.2), Color3.fromRGB(40, 230, 255))
	part("ArmR", Vector3.new(0.3, 0.3, 1.1), CFrame.new(0.15, -0.3, 0.55) * CFrame.Angles(0, 0, 0.1), skin)
	part("ArmL", Vector3.new(0.3, 0.3, 1.1), CFrame.new(-0.2, -0.15, -0.5) * CFrame.Angles(0, 0.25, 0), skin)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -0.32) -- relative to Barrel center: just past its 0.6-long tip
	muzzle.Parent = model.Barrel

	return model
end

function Viewmodel.new(muzzleLight)
	local self = setmetatable({}, Viewmodel)
	self.LightConfig = muzzleLight or DEFAULT_LIGHT

	local template = ReplicatedStorage:FindFirstChild("Viewmodel")
	self.Model = if template and template:IsA("Model") then template:Clone() else buildPlaceholder()

	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
		end
	end

	self.Muzzle = self.Model:FindFirstChild("Muzzle", true)
	self.Light = Instance.new("PointLight")
	self.Light.Brightness = 0
	self.Light.Range = self.LightConfig.Range
	self.Light.Color = self.LightConfig.Color
	if self.Muzzle then
		self.Light.Parent = self.Muzzle
	end

	-- Optional authored animations.
	self.Tracks = {}
	local animator = self.Model:FindFirstChildWhichIsA("Animator", true)
	local animations = self.Model:FindFirstChild("Animations")
	if animator and animations then
		for _, anim in animations:GetChildren() do
			if anim:IsA("Animation") then
				self.Tracks[anim.Name] = animator:LoadAnimation(anim)
			end
		end
	end

	self.PosSpring = Spring.new(POS_STIFFNESS, POS_DAMPING)
	self.RotSpring = Spring.new(ROT_STIFFNESS, ROT_DAMPING)
	self._bobTime = 0
	self._bob = Vector3.zero
	self._reloadStart = nil
	self._reloadDuration = 1
	self._lastFlash = 0

	self.Model.Parent = workspace.CurrentCamera
	-- After CameraRecoil (Camera + 1) so the gun follows the kicked camera.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		self:_update(dt)
	end)

	return self
end

function Viewmodel:_update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or not self.Model.Parent then
		return
	end

	-- Mouse sway: kick the rotation spring against look direction.
	local delta = UserInputService:GetMouseDelta()
	self.RotSpring:Impulse(Vector3.new(-delta.Y * 0.012, -delta.X * 0.012, -delta.X * 0.006))

	-- Walk bob from horizontal speed.
	local character = game:GetService("Players").LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local speed = 0
	if root then
		local v = root.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	local strength = math.clamp(speed / 16, 0, 1)
	self._bobTime += dt * speed * 0.55
	local target = Vector3.new(math.sin(self._bobTime) * 0.025, -math.abs(math.cos(self._bobTime)) * 0.03, 0) * strength
	self._bob = self._bob:Lerp(target, math.min(dt * 12, 1))

	self.PosSpring:Update(dt)
	self.RotSpring:Update(dt)

	-- Procedural reload dip (skipped when an authored Reload animation exists).
	local reloadPos, reloadRot = Vector3.zero, Vector3.zero
	if self._reloadStart and not self.Tracks.Reload then
		local alpha = (os.clock() - self._reloadStart) / self._reloadDuration
		if alpha >= 1 then
			self._reloadStart = nil
		else
			local dip = math.sin(alpha * math.pi)
			reloadPos = Vector3.new(0, -0.45 * dip, 0.15 * dip)
			reloadRot = Vector3.new(-0.5 * dip, 0, 0.6 * dip)
		end
	end

	-- Muzzle flash decay.
	if self.Light.Brightness > 0 and os.clock() - self._lastFlash > self.LightConfig.Duration then
		self.Light.Brightness = 0
	end

	local pos = self.PosSpring.Position + self._bob + reloadPos
	local rot = self.RotSpring.Position + reloadRot
	local offset = BASE_OFFSET * CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
	self.Model:PivotTo(camera.CFrame * offset)
end

-- recoil = { Z = studs, Pitch = degrees } as peak displacement. Spec Z is negative for
-- kickback toward the shooter, which is +Z in camera space.
function Viewmodel:PlayFire(recoil)
	recoil = recoil or DEFAULT_RECOIL
	local jitter = (math.random() - 0.5)
	self.PosSpring:Impulse(Vector3.new(jitter * 0.02, 0, -recoil.Z) * POS_GAIN)
	self.RotSpring:Impulse(Vector3.new(math.rad(recoil.Pitch), jitter * 0.03, jitter * 0.05) * ROT_GAIN)

	self.Light.Brightness = self.LightConfig.Brightness
	self._lastFlash = os.clock()

	local track = self.Tracks.Fire
	if track then
		track:Play(0.02)
	end
end

function Viewmodel:PlayReload(duration: number)
	self._reloadStart = os.clock()
	self._reloadDuration = duration

	local track = self.Tracks.Reload
	if track then
		-- Length is 0 until the animation asset loads; play at normal speed then.
		local speed = if track.Length > 0 then track.Length / duration else 1
		track:Play(0.1, 1, speed)
	end
end

function Viewmodel:CancelReload()
	self._reloadStart = nil
	local track = self.Tracks.Reload
	if track then
		track:Stop(0.1)
	end
end

function Viewmodel:PlayEquip()
	self.PosSpring.Position = Vector3.new(0, -0.9, 0.4)
	self.RotSpring.Position = Vector3.new(-0.6, 0, 0)

	local track = self.Tracks.Equip
	if track then
		track:Play(0.05)
	end
end

function Viewmodel:GetMuzzlePosition(): Vector3?
	local m = self.Muzzle
	if not m then
		return nil
	end
	if m:IsA("Attachment") then
		return m.WorldPosition
	end
	return m.Position
end

function Viewmodel:Destroy()
	RunService:UnbindFromRenderStep(BIND_NAME)
	self.Model:Destroy()
end

return Viewmodel
