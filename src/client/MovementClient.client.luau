--!nonstrict
-- Sprint / crouch. Hold Shift to sprint (forward movement only), hold C or Left Ctrl
-- to crouch. Crouch lowers the camera and (R15) hip height, slows movement, and
-- stays active while there is a ceiling too low to stand under.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WALK_SPEED = 16
local SPRINT_SPEED = 26
local CROUCH_SPEED = 8

local CROUCH_CAMERA_DROP = 1.5 -- studs the camera sinks when fully crouched
local CROUCH_HIP_FRACTION = 0.5 -- fraction of HipHeight removed when crouched (R15)
local STAND_CLEARANCE = 4.5 -- headroom needed above the root part to stand
local TRANSITION_RATE = 12 -- higher = snappier crouch transition
local SPRINT_FORWARD_DOT = 0.3 -- how "forward" movement must be to count as sprinting

local player = Players.LocalPlayer

local character = nil
local humanoid = nil
local root = nil
local standingHipHeight = 0
local crouchAlpha = 0 -- 0 standing .. 1 crouched

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function onCharacterAdded(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	standingHipHeight = humanoid.HipHeight
	crouchAlpha = 0
	rayParams.FilterDescendantsInstances = { char }
	humanoid.WalkSpeed = WALK_SPEED
end

local function ceilingAbove(): boolean
	return workspace:Raycast(root.Position, Vector3.new(0, STAND_CLEARANCE, 0), rayParams) ~= nil
end

RunService.RenderStepped:Connect(function(dt)
	if not humanoid or humanoid.Health <= 0 or not root or not root.Parent then
		return
	end

	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local crouchHeld = not typing
		and (UserInputService:IsKeyDown(Enum.KeyCode.C) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl))

	-- Don't stand up into a low ceiling.
	local wantsCrouch = crouchHeld or (crouchAlpha > 0.05 and ceilingAbove())

	local wantsSprint = false
	if not typing and not wantsCrouch and crouchAlpha < 0.1 and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		local camera = workspace.CurrentCamera
		local move = humanoid.MoveDirection
		if camera and move.Magnitude > 0.1 then
			local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.01 then
				wantsSprint = move.Unit:Dot(look.Unit) > SPRINT_FORWARD_DOT
			end
		end
	end

	-- Smooth crouch transition.
	local target = if wantsCrouch then 1 else 0
	crouchAlpha += (target - crouchAlpha) * math.min(dt * TRANSITION_RATE, 1)
	if math.abs(target - crouchAlpha) < 0.001 then
		crouchAlpha = target
	end

	humanoid.CameraOffset = Vector3.new(0, -CROUCH_CAMERA_DROP * crouchAlpha, 0)
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		humanoid.HipHeight = standingHipHeight * (1 - CROUCH_HIP_FRACTION * crouchAlpha)
	end

	local speed = if wantsCrouch then CROUCH_SPEED elseif wantsSprint then SPRINT_SPEED else WALK_SPEED
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
