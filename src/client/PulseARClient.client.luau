--!nonstrict
-- Pulse-AR client: input -> predicted BaseWeapon -> viewmodel/tracer feedback,
-- and RemoteEvent replication to the server for authoritative damage.
--
-- Controls: Mouse1 fire (hold), R reload, 1 holster/equip.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BaseWeapon = require(Modules:WaitForChild("BaseWeapon"))
local Ballistics = require(Modules:WaitForChild("Ballistics"))
local WeaponConfigs = require(Modules:WaitForChild("WeaponConfigs"))
local CameraRecoil = require(script.Parent:WaitForChild("CameraRecoil"))
local HitmarkerHUD = require(script.Parent:WaitForChild("HitmarkerHUD"))
local Viewmodel = require(script.Parent:WaitForChild("Viewmodel"))
local Tracer = require(script.Parent:WaitForChild("Tracer"))

local remotes = ReplicatedStorage:WaitForChild("WeaponRemotes")
local actionRemote = remotes:WaitForChild("Action")
local replicateRemote = remotes:WaitForChild("Replicate")

local player = Players.LocalPlayer
local config = WeaponConfigs.PulseAR

local weapon = nil
local viewmodel = nil
local triggerHeld = false
local triggerPressed = false -- edge flag for semi-auto weapons
local spread = config.Spread.Base -- current cone half-angle, degrees
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

player.CameraMode = Enum.CameraMode.LockFirstPerson

-- HUD -----------------------------------------------------------------------

HitmarkerHUD.Init()

local gui = Instance.new("ScreenGui")
gui.Name = "WeaponHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local ammoLabel = Instance.new("TextLabel")
ammoLabel.AnchorPoint = Vector2.new(1, 1)
ammoLabel.Position = UDim2.new(1, -24, 1, -24)
ammoLabel.Size = UDim2.fromOffset(240, 48)
ammoLabel.BackgroundTransparency = 1
ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
ammoLabel.Font = Enum.Font.GothamBold
ammoLabel.TextSize = 36
ammoLabel.TextColor3 = Color3.new(1, 1, 1)
ammoLabel.TextStrokeTransparency = 0.5
ammoLabel.Parent = gui

local function updateHud()
	HitmarkerHUD.SetVisible(weapon ~= nil and weapon.State ~= "Idle")
	if not weapon then
		ammoLabel.Text = ""
	elseif weapon.State == "Reloading" then
		ammoLabel.Text = "RELOADING"
	elseif weapon.State == "Idle" then
		ammoLabel.Text = "HOLSTERED"
	else
		ammoLabel.Text = `{weapon.Mag} / {weapon.Reserve}`
	end
end

-- Weapon lifecycle ----------------------------------------------------------

local function equip()
	if not weapon or weapon.State ~= "Idle" then
		return
	end
	weapon:Equip()
	viewmodel.Model.Parent = workspace.CurrentCamera
	viewmodel:PlayEquip()
	actionRemote:FireServer("Equip", true)
end

local function unequip()
	if not weapon or weapon.State == "Idle" then
		return
	end
	weapon:Unequip()
	viewmodel:CancelReload()
	viewmodel.Model.Parent = nil
	actionRemote:FireServer("Equip", false)
end

local function teardown()
	if weapon then
		weapon:Destroy()
		weapon = nil
	end
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
	triggerHeld = false
	spread = config.Spread.Base
	CameraRecoil.Reset()
	updateHud()
end

local function onCharacterAdded(character: Model)
	teardown()

	weapon = BaseWeapon.new(config)
	viewmodel = Viewmodel.new(config.MuzzleLight)
	rayParams.FilterDescendantsInstances = { character, workspace.CurrentCamera }

	weapon.AmmoChanged:Connect(updateHud)
	weapon.StateChanged:Connect(function(newState, oldState)
		if newState == "Reloading" then
			-- Covers manual and auto-reloads; the server ignores it if already reloading.
			actionRemote:FireServer("Reload")
			viewmodel:PlayReload(config.ReloadTime)
		elseif oldState == "Reloading" and newState == "Idle" then
			viewmodel:CancelReload()
		end
		updateHud()
	end)

	-- Server already equips on spawn; mirror that locally.
	weapon:Equip()
	viewmodel:PlayEquip()
	updateHud()

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(teardown)
end

-- Shooting ------------------------------------------------------------------

-- Distance at which a ray enters the nearest stasis field, so local tracers stop
-- where the server will freeze the shot.
local function stasisCutoff(origin: Vector3, direction: Vector3, maxDistance: number): number
	local best = maxDistance
	for _, field in CollectionService:GetTagged("StasisField") do
		local radius = field:GetAttribute("Radius")
		if radius then
			local t = Ballistics.RaySphere(origin, direction, field.Position, radius, best)
			if t then
				best = t
			end
		end
	end
	return best
end

local function fireOnce()
	local ok = weapon:Fire()
	if not ok then
		return
	end

	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local direction = Ballistics.ApplySpread(camera.CFrame.LookVector, spread)
	spread = math.min(spread + config.Spread.PerShot, config.Spread.Max)

	-- Local hit-scan only decides where the tracer ends; damage is server-side.
	local result = workspace:Raycast(origin, direction * config.Range, rayParams)
	local distance = stasisCutoff(origin, direction, if result then result.Distance else config.Range)
	local endPos = origin + direction * distance

	Tracer.draw(viewmodel:GetMuzzlePosition() or origin, endPos, config.TracerColor, config.TracerLifetime)
	viewmodel:PlayFire(config.ViewmodelRecoil)
	CameraRecoil.Fire(config.CameraRecoil)

	actionRemote:FireServer("Fire", origin, direction)
end

RunService.RenderStepped:Connect(function(dt)
	spread = math.max(config.Spread.Base, spread - config.Spread.Recovery * dt)
	HitmarkerHUD.SetSpread(spread)

	local character = player.Character
	local rewinding = character and character:GetAttribute("Rewinding")
	if weapon and weapon.State == "Equipped" and triggerHeld and not rewinding then
		if config.Automatic or triggerPressed then
			fireOnce()
		end
	end
	triggerPressed = false
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = true
		triggerPressed = true
	elseif input.KeyCode == Enum.KeyCode.R then
		if weapon then
			weapon:Reload()
		end
	elseif input.KeyCode == Enum.KeyCode.One then
		if weapon and weapon:IsEquipped() then
			unequip()
		else
			equip()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerHeld = false
	end
end)

-- Replication from server ---------------------------------------------------

replicateRemote.OnClientEvent:Connect(function(kind, ...)
	if kind == "Tracer" then
		local userId, origin, endPos, exact = ...
		if exact then
			-- Re-fired from a stasis field: everyone, including the shooter, draws it as-is.
			Tracer.draw(origin, endPos, config.TracerColor, config.TracerLifetime)
			return
		end
		if userId == player.UserId then
			return -- we already drew our own
		end
		-- Approximate the shooter's gun position: below the eyes, a bit forward.
		if (endPos - origin).Magnitude < 0.1 then
			return -- .Unit of a zero vector is NaN
		end
		local forward = (endPos - origin).Unit
		Tracer.draw(origin + Vector3.new(0, -0.8, 0) + forward * 1.5, endPos, config.TracerColor, config.TracerLifetime)
	elseif kind == "Sync" then
		local mag, reserve = ...
		if weapon then
			weapon:SetAmmo(mag, reserve)
		end
	end
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
