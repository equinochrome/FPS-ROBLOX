--!nonstrict
-- 3-Second Time-Rewind, client side (INSTRUCTIONS.md section 2A).
--
-- Records a 60 Hz rolling ring buffer of 180 snapshots (3 seconds). On E:
--   1. lock movement controls and anchor HumanoidRootPart
--   2. fire RewindTriggered(timestamp, cframe) for the oldest snapshot
--   3. lerp the root backwards through every buffered frame over 0.45s,
--      spawning ghost-trail copies of the character along the recorded path
--   4. on server acceptance keep the rewound position and restore recorded velocity;
--      on rejection snap back to where the rewind started
-- Health is restored by the server from its own record (see RewindService); a client
-- cannot set its own Humanoid.Health.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

type RewindSnapshot = {
	Timestamp: number,
	CFrame: CFrame,
	Health: number,
	Velocity: Vector3,
}

local BUFFER_SIZE = 180 -- 3s at 60 Hz
local SAMPLE_INTERVAL = 1 / 60
local REWIND_DURATION = 0.45
local MIN_FRAMES = 15 -- need at least 0.25s of history to rewind
local COOLDOWN = 8 -- ASSUMPTION: mirrored from RewindService
local RESULT_TIMEOUT = 1.5 -- wait this long for the server verdict after playback
local GHOST_SPACING = 12 -- frames between ghosts (15 ghosts for a full buffer)
local GHOST_LIFETIME = 0.6
local GHOST_COLOR = Color3.fromRGB(0, 220, 255)
local REWIND_KEY = Enum.KeyCode.E

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("TimeRemotes")
local rewindRemote = remotes:WaitForChild("RewindTriggered")
local resultRemote = remotes:WaitForChild("RewindResult")

-- Default control module. Looked up in the background with a timeout so a missing
-- PlayerModule can't stall this whole script (it previously yielded forever).
local controls = nil
task.spawn(function()
	local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
	if playerModule then
		controls = require(playerModule):GetControls()
	else
		warn("[TimeRewindClient] PlayerModule not found; rewind will anchor the character without disabling input")
	end
end)

local function setControlsEnabled(enabled: boolean)
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

-- Ring buffer ----------------------------------------------------------------

local buffer: { RewindSnapshot } = table.create(BUFFER_SIZE)
local head = 0 -- index of newest snapshot
local count = 0
local accumulator = 0

local function clearBuffer()
	table.clear(buffer)
	head, count, accumulator = 0, 0, 0
end

local function push(snapshot: RewindSnapshot)
	head = head % BUFFER_SIZE + 1
	buffer[head] = snapshot
	count = math.min(count + 1, BUFFER_SIZE)
end

-- Snapshots ordered newest -> oldest.
local function framesNewestFirst(): { RewindSnapshot }
	local frames = table.create(count)
	for k = 0, count - 1 do
		frames[k + 1] = buffer[(head - 1 - k) % BUFFER_SIZE + 1]
	end
	return frames
end

-- State ----------------------------------------------------------------------

local character, humanoid, root = nil, nil, nil
local rewinding = false
local lastRewind = -math.huge
local verdict = nil -- nil = pending, true/false from server

resultRemote.OnClientEvent:Connect(function(accepted)
	verdict = accepted == true
end)

RunService.Heartbeat:Connect(function(dt)
	if rewinding or not humanoid or humanoid.Health <= 0 or not root or not root.Parent then
		return
	end
	accumulator += dt
	if accumulator < SAMPLE_INTERVAL then
		return
	end
	-- One sample per tick even after a hitch; timestamps keep the real spacing.
	accumulator = math.min(accumulator - SAMPLE_INTERVAL, SAMPLE_INTERVAL)

	push({
		Timestamp = workspace:GetServerTimeNow(),
		CFrame = root.CFrame,
		Health = humanoid.Health,
		Velocity = root.AssemblyLinearVelocity,
	})
end)

-- Ghost trail ----------------------------------------------------------------

-- Pose of every visible body part relative to the root, captured once per rewind.
local function captureGhostTemplate(root: BasePart): { { Part: BasePart, Offset: CFrame } }
	local template = {}
	for _, d in root.Parent:GetDescendants() do
		local ghost = if d:IsA("BasePart") and d ~= root and d.Transparency < 1 then d:Clone() else nil
		if ghost then -- Clone() is nil for non-Archivable parts
			ghost:ClearAllChildren()
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Massless = true
			ghost.Material = Enum.Material.Neon
			ghost.Color = GHOST_COLOR
			ghost.Transparency = 0.6
			ghost.LocalTransparencyModifier = 0
			if ghost:IsA("MeshPart") then
				ghost.TextureID = ""
			end
			table.insert(template, { Part = ghost, Offset = root.CFrame:ToObjectSpace(d.CFrame) })
		end
	end
	return template
end

local function spawnGhost(template, at: CFrame)
	local model = Instance.new("Model")
	model.Name = "RewindGhost"
	for _, entry in template do
		local p = entry.Part:Clone()
		p.CFrame = at * entry.Offset
		p.Parent = model
		TweenService:Create(p, TweenInfo.new(GHOST_LIFETIME), { Transparency = 1 }):Play()
	end
	model.Parent = workspace.CurrentCamera -- local-only, excluded from weapon raycasts
	Debris:AddItem(model, GHOST_LIFETIME + 0.1)
end

-- Rewind ---------------------------------------------------------------------

local function rewind()
	if rewinding or count < MIN_FRAMES or os.clock() - lastRewind < COOLDOWN then
		return
	end
	if not humanoid or humanoid.Health <= 0 or not root or not root.Parent then
		return
	end

	rewinding = true
	verdict = nil
	-- Pin this life's instances: a respawn mid-rewind reassigns the module-level ones.
	local myCharacter, myRoot = character, root
	myCharacter:SetAttribute("Rewinding", true)

	local frames = framesNewestFirst()
	local target = frames[#frames] -- frame t-180 (or the oldest we have)
	local startCFrame = myRoot.CFrame
	local template = captureGhostTemplate(myRoot)

	rewindRemote:FireServer(target.Timestamp, target.CFrame)

	setControlsEnabled(false)
	myRoot.Anchored = true

	-- Lerp backwards through every buffered frame.
	local elapsed = 0
	local nextGhost = 1
	while elapsed < REWIND_DURATION and myRoot.Parent do
		elapsed += RunService.RenderStepped:Wait()
		local alpha = math.min(elapsed / REWIND_DURATION, 1)
		local f = 1 + alpha * (#frames - 1)
		local i = math.floor(f)
		local j = math.min(i + 1, #frames)
		myRoot.CFrame = frames[i].CFrame:Lerp(frames[j].CFrame, f - i)

		while nextGhost <= f do
			spawnGhost(template, frames[nextGhost].CFrame)
			nextGhost += GHOST_SPACING
		end
	end

	-- Wait for the server's verdict if it hasn't arrived yet.
	local waited = 0
	while verdict == nil and waited < RESULT_TIMEOUT do
		waited += task.wait()
	end

	if character == myCharacter and myRoot.Parent then
		if verdict == true then
			myRoot.CFrame = target.CFrame
			myRoot.Anchored = false
			myRoot.AssemblyLinearVelocity = target.Velocity
		else
			myRoot.CFrame = startCFrame
			myRoot.Anchored = false
		end
		setControlsEnabled(true)
		clearBuffer()
	end

	for _, entry in template do
		entry.Part:Destroy()
	end
	myCharacter:SetAttribute("Rewinding", nil)
	lastRewind = os.clock()
	rewinding = false
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= REWIND_KEY then
		return
	end
	task.spawn(rewind)
end)

-- Lifecycle ------------------------------------------------------------------

local function onCharacterAdded(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	root = char:WaitForChild("HumanoidRootPart")
	clearBuffer()
	setControlsEnabled(true) -- in case we died mid-rewind
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
