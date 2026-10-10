--!nonstrict
-- Server authority for weapons: validates fire requests, raycasts, applies damage
-- and broadcasts tracers. Each player gets a server-side BaseWeapon that enforces
-- ammo, reload and fire rate independently of the client.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BaseWeapon = require(Modules:WaitForChild("BaseWeapon"))
local Ballistics = require(Modules:WaitForChild("Ballistics"))
local WeaponConfigs = require(Modules:WaitForChild("WeaponConfigs"))
local StasisService = require(script.Parent.StasisService)
local TargetDummy = require(script.Parent.TargetDummy)

local WeaponService = {}

-- How far the claimed shot origin may be from the shooter's head (latency + camera offset).
local MAX_ORIGIN_DRIFT = 15

local OPTIONS = { FireTolerance = 0.25, ReloadTolerance = 0.3 }

local states = {} -- [Player] = { Weapon, Config, Connections }
local actionRemote: RemoteEvent
local replicateRemote: RemoteEvent
local hitConfirmedRemote: RemoteEvent

local function aliveHumanoid(character: Model?): Humanoid?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Accessory handles (hats, hair) sit over the head; resolve them to the body part
-- they are welded to so headshots aren't blocked by cosmetics.
-- Must be defined before applyDamage: local functions aren't visible above their declaration.
local function resolveHitPart(hitPart: BasePart): BasePart
	if not hitPart.Parent or not hitPart.Parent:IsA("Accessory") then
		return hitPart
	end
	local weld = hitPart:FindFirstChild("AccessoryWeld")
	if weld and weld:IsA("JointInstance") then
		local other = if weld.Part0 == hitPart then weld.Part1 else weld.Part0
		if other then
			return other
		end
	end
	return hitPart
end

-- Applies falloff (by total distance from the original shot origin) and headshot
-- multiplier. Returns isHeadshot, killed, damage when something damageable was hit.
local function applyDamage(shooter: Player, result: RaycastResult, config, baseDamage: number, distance: number)
	local hitPart = resolveHitPart(result.Instance)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	local isHeadshot = hitPart.Name == "Head"
	local damage = Ballistics.Falloff(config, baseDamage, distance)
	if isHeadshot then
		damage *= config.HeadshotMultiplier
	end

	if CollectionService:HasTag(model, "TargetDummy") then
		if model:GetAttribute("Down") then
			return nil
		end
		local killed = TargetDummy.TakeDamage(model, damage)
		return isHeadshot, killed, damage
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and Players:GetPlayerFromCharacter(model) ~= shooter then
		humanoid:TakeDamage(damage)
		return isHeadshot, humanoid.Health <= 0, damage
	end
	return nil
end

-- Casts one hitscan segment. A stasis field in the way traps the shot at the sphere
-- boundary; otherwise it damages whatever it hits. `exactTracer` tells clients to draw
-- from the given start (re-fired shots) instead of approximating the shooter's gun.
local function traceShot(shot, exactTracer: boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { shot.Shooter.Character }

	local result = workspace:Raycast(shot.Start, shot.Direction * shot.Range, params)
	local hitDistance = if result then result.Distance else shot.Range

	local field, t = StasisService.FindIntersection(shot.Start, shot.Direction, hitDistance)
	if field then
		local impact = shot.Start + shot.Direction * t
		StasisService.Trap(field, {
			Direction = shot.Direction,
			Damage = shot.Damage,
			Shooter = shot.Shooter,
			Origin = shot.Origin,
			ImpactPoint = impact,
			RemainingRange = shot.Range - t,
			Traveled = shot.Traveled + t,
			Config = shot.Config,
		})
		replicateRemote:FireAllClients("Tracer", shot.Shooter.UserId, shot.Start, impact, exactTracer)
		return
	end

	local endPos = if result then result.Position else shot.Start + shot.Direction * shot.Range
	if result then
		local isHeadshot, killed, damage =
			applyDamage(shot.Shooter, result, shot.Config, shot.Damage, shot.Traveled + result.Distance)
		if isHeadshot ~= nil and shot.Shooter.Parent then
			hitConfirmedRemote:FireClient(shot.Shooter, isHeadshot, killed, damage)
		end
	end
	replicateRemote:FireAllClients("Tracer", shot.Shooter.UserId, shot.Start, endPos, exactTracer)
end

-- Resumes a shot released by an expiring stasis field.
local function refire(payload)
	traceShot({
		Shooter = payload.Shooter,
		Config = payload.Config,
		Damage = payload.Damage,
		Origin = payload.Origin,
		Start = payload.ImpactPoint,
		Direction = payload.Direction,
		Range = payload.RemainingRange,
		Traveled = payload.Traveled,
	}, true)
end

local SYNC_COOLDOWN = 0.25

local function sync(player: Player, weapon)
	replicateRemote:FireClient(player, "Sync", weapon.Mag, weapon.Reserve)
end

-- Rate-limited sync for rejected shots, so a burst of rejections is one packet.
local function syncThrottled(player: Player, state)
	local now = os.clock()
	if now - (state.LastSync or 0) < SYNC_COOLDOWN then
		return
	end
	state.LastSync = now
	sync(player, state.Weapon)
end

local function handleFire(player: Player, origin, direction)
	local state = states[player]
	if not state then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if origin ~= origin or direction ~= direction or direction.Magnitude < 0.5 then -- NaN / zero guard
		return
	end

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not aliveHumanoid(character) then
		return
	end
	if (origin - head.Position).Magnitude > MAX_ORIGIN_DRIFT then
		return
	end

	local weapon, config = state.Weapon, state.Config
	local ok = weapon:Fire()
	if not ok then
		-- The client already spent this round locally, so any rejection (including
		-- throttle from network jitter) means its magazine has drifted from ours.
		syncThrottled(player, state)
		return
	end

	traceShot({
		Shooter = player,
		Config = config,
		Damage = config.Damage,
		Origin = origin,
		Start = origin,
		Direction = direction.Unit,
		Range = config.Range,
		Traveled = 0,
	}, false)
end

local function onCharacterAdded(player: Player, character: Model)
	local old = states[player]
	if old then
		old.Weapon:Destroy()
	end

	local config = WeaponConfigs.PulseAR
	local weapon = BaseWeapon.new(config, OPTIONS)
	weapon:Equip()
	states[player] = { Weapon = weapon, Config = config }

	-- Re-align the client's magazine after every completed reload.
	weapon.StateChanged:Connect(function(newState, oldState)
		if oldState == "Reloading" and newState == "Equipped" then
			sync(player, weapon)
		end
	end)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			weapon:Unequip()
		end)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

-- Spawns `count` target dummies in a ring on the floor of `area` (a Model already in
-- the workspace). Floor is found by raycasting down from `castFromY` (defaults to the
-- top of the area; pass a height below any roof for covered tiles).
function WeaponService.PopulateDummies(area: Model, count: number?, castFromY: number?)
	count = count or 4
	local ringRadius = 12

	local boxCFrame, boxSize = area:GetBoundingBox()
	local center = boxCFrame.Position
	local startY = castFromY or (center.Y + boxSize.Y / 2 + 1)
	local castLength = startY - (center.Y - boxSize.Y / 2) + 1

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { area }

	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi
		local x = center.X + math.cos(angle) * ringRadius
		local z = center.Z + math.sin(angle) * ringRadius
		local hit = workspace:Raycast(Vector3.new(x, startY, z), Vector3.new(0, -castLength, 0), params)
		if hit and hit.Normal.Y > 0.7 then
			TargetDummy.spawn(area, hit.Position)
		else
			warn(`[WeaponService] No floor for dummy {i} in {area:GetFullName()}`)
		end
	end
end

function WeaponService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "WeaponRemotes"

	actionRemote = Instance.new("RemoteEvent")
	actionRemote.Name = "Action" -- client -> server
	actionRemote.Parent = folder

	replicateRemote = Instance.new("RemoteEvent")
	replicateRemote.Name = "Replicate" -- server -> clients
	replicateRemote.Parent = folder

	hitConfirmedRemote = Instance.new("RemoteEvent")
	hitConfirmedRemote.Name = "HitConfirmed" -- server -> shooter: isHeadshot, killed, damage
	hitConfirmedRemote.Parent = folder

	folder.Parent = ReplicatedStorage

	StasisService.SetRefireHandler(refire)

	actionRemote.OnServerEvent:Connect(function(player, action, ...)
		local state = states[player]
		if not state then
			return
		end

		if action == "Fire" then
			handleFire(player, ...)
		elseif action == "Reload" then
			state.Weapon:Reload()
		elseif action == "Equip" then
			local wantEquipped = ...
			if wantEquipped == true and aliveHumanoid(player.Character) then
				state.Weapon:Equip()
			elseif wantEquipped == false then
				state.Weapon:Unequip()
			end
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state then
			state.Weapon:Destroy()
			states[player] = nil
		end
	end)
end

return WeaponService
