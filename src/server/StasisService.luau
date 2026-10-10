--!nonstrict
-- Stasis Field system (INSTRUCTIONS.md section 2B).
--
-- A player deploys an 8-stud-radius sphere (key F) that lasts 4 seconds. WeaponService
-- asks FindIntersection() for every hitscan segment; a ray that enters a field stops at
-- the sphere boundary and its payload is stored with a frozen glow at the impact point.
-- When the field expires, every trapped shot is re-fired in the same frame along its
-- original direction, starting from where it was frozen.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Ballistics = require(Modules:WaitForChild("Ballistics"))

local StasisService = {}

local RADIUS = 8
local DURATION = 4.0
local COOLDOWN = 12 -- ASSUMPTION: not in spec
local MAX_DEPLOY_RANGE = 30 -- ASSUMPTION: field is placed where you aim, up to this far
local MAX_ORIGIN_DRIFT = 15 -- same tolerance as WeaponService
local FIELD_COLOR = Color3.fromRGB(140, 90, 255)

export type Payload = {
	Direction: Vector3,
	Damage: number,
	Shooter: Player,
	Origin: Vector3,
	-- Extra data needed to resume the shot:
	ImpactPoint: Vector3,
	RemainingRange: number,
	Traveled: number,
	Config: any,
}

local fields = {} -- active fields
local lastDeploy = {} -- [Player] = os.clock()
local refireHandler: ((Payload) -> ())? = nil
local folder: Folder

local function makeFieldVisual(center: Vector3): Part
	local sphere = Instance.new("Part")
	sphere.Name = "StasisField"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.one * RADIUS * 2
	sphere.Position = center
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false -- never blocks raycasts; intersection is done mathematically
	sphere.CanTouch = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.ForceField
	sphere.Color = FIELD_COLOR
	sphere:SetAttribute("Radius", RADIUS)
	CollectionService:AddTag(sphere, "StasisField") -- clients use this to cut their local tracers
	sphere.Parent = folder
	return sphere
end

local function makeFrozenGlow(parent: Instance, position: Vector3, color: Color3)
	local glow = Instance.new("Part")
	glow.Name = "FrozenShot"
	glow.Shape = Enum.PartType.Ball
	glow.Size = Vector3.one * 0.35
	glow.Position = position
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Material = Enum.Material.Neon
	glow.Color = color

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 1
	particles.Lifetime = NumberRange.new(0.3, 0.5)
	particles.Rate = 20
	particles.Speed = NumberRange.new(0)
	particles.Size = NumberSequence.new(0.6, 0)
	particles.Transparency = NumberSequence.new(0.2, 1)
	particles.Parent = glow

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 4
	light.Brightness = 1.5
	light.Parent = glow

	glow.Parent = parent
end

local function expire(field)
	local index = table.find(fields, field)
	if index then
		table.remove(fields, index)
	end

	-- Re-fire everything at once, then clear visuals.
	if refireHandler then
		for _, payload in field.Trapped do
			task.spawn(refireHandler, payload)
		end
	end
	field.Visual:Destroy()
end

function StasisService.Deploy(owner: Player, center: Vector3)
	local field = {
		Owner = owner,
		Position = center,
		Radius = RADIUS,
		Trapped = {} :: { Payload },
		Visual = makeFieldVisual(center),
	}
	table.insert(fields, field)

	-- Pulse in, then expire.
	field.Visual.Size = Vector3.one
	TweenService:Create(field.Visual, TweenInfo.new(0.15, Enum.EasingStyle.Back), {
		Size = Vector3.one * RADIUS * 2,
	}):Play()
	task.delay(DURATION, expire, field)

	return field
end

-- Nearest active field a ray enters within maxDistance. Returns field, distance.
function StasisService.FindIntersection(origin: Vector3, direction: Vector3, maxDistance: number)
	local bestField, bestT = nil, nil
	for _, field in fields do
		local t = Ballistics.RaySphere(origin, direction, field.Position, field.Radius, maxDistance)
		if t and (not bestT or t < bestT) then
			bestField, bestT = field, t
		end
	end
	return bestField, bestT
end

function StasisService.Trap(field, payload: Payload)
	table.insert(field.Trapped, payload)
	local color = payload.Config.TracerColor or FIELD_COLOR
	makeFrozenGlow(field.Visual, payload.ImpactPoint, color)
end

-- WeaponService supplies how a payload is resumed, avoiding a circular require.
function StasisService.SetRefireHandler(handler: (Payload) -> ())
	refireHandler = handler
end

local function onDeployRequest(player: Player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if origin ~= origin or direction ~= direction or direction.Magnitude < 0.5 then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head then
		return
	end
	if (origin - head.Position).Magnitude > MAX_ORIGIN_DRIFT then
		return
	end

	local now = os.clock()
	if lastDeploy[player] and now - lastDeploy[player] < COOLDOWN then
		return
	end
	lastDeploy[player] = now

	direction = direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(origin, direction * MAX_DEPLOY_RANGE, params)
	local distance = if result then math.max(result.Distance - 1, 0) else MAX_DEPLOY_RANGE

	StasisService.Deploy(player, origin + direction * distance)
end

function StasisService.Init()
	folder = Instance.new("Folder")
	folder.Name = "StasisFields"
	folder.Parent = workspace

	local remotes = ReplicatedStorage:FindFirstChild("TimeRemotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "TimeRemotes"
		remotes.Parent = ReplicatedStorage
	end

	local deployRemote = Instance.new("RemoteEvent")
	deployRemote.Name = "StasisDeploy" -- client -> server: origin, direction
	deployRemote.Parent = remotes
	deployRemote.OnServerEvent:Connect(onDeployRequest)

	Players.PlayerRemoving:Connect(function(player)
		lastDeploy[player] = nil
	end)
end

return StasisService
