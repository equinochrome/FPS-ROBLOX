--!nonstrict
-- Server side of the 3-second Time-Rewind (INSTRUCTIONS.md section 2A).
--
-- Keeps its own position/health history per player. When a client fires
-- RewindTriggered(timestamp, cframe), the claimed target is checked against the
-- server's recorded position at that time within a 12-stud tolerance. If valid, the
-- *server-recorded* health is committed once the client's 0.45s rewind playback
-- finishes; the client applies the position itself. The client never decides its own health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RewindService = {}

local TOLERANCE = 12 -- studs
local REWIND_DURATION = 0.45 -- matches client playback
local MAX_REWIND_AGE = 3.5 -- seconds; 3s of buffer plus latency slack
local MAX_SAMPLE_GAP = 0.25 -- nearest server sample must be this close to the claim
local LATENCY_WINDOW = 0.6 -- how far after the claim to look for the client's replicated position
local COOLDOWN = 8 -- ASSUMPTION: not in spec; mirrored in TimeRewindClient
local SAMPLE_RATE = 20 -- Hz
local HISTORY_SIZE = math.ceil((MAX_REWIND_AGE + 0.5) * SAMPLE_RATE)

local histories = {} -- [Player] = { samples = {}, head = 0, count = 0 }
local lastRewind = {} -- [Player] = os.clock()
local resultRemote: RemoteEvent

local function getHistory(player: Player)
	local h = histories[player]
	if not h then
		h = { samples = table.create(HISTORY_SIZE), head = 0, count = 0 }
		histories[player] = h
	end
	return h
end

local function record(player: Player, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	local h = getHistory(player)
	h.head = h.head % HISTORY_SIZE + 1
	h.samples[h.head] = { Time = now, CFrame = root.CFrame, Health = humanoid.Health }
	h.count = math.min(h.count + 1, HISTORY_SIZE)
end

local function nearestSample(player: Player, timestamp: number)
	local h = histories[player]
	if not h then
		return nil
	end
	local best, bestGap = nil, math.huge
	for i = 1, h.count do
		local s = h.samples[i]
		local gap = math.abs(s.Time - timestamp)
		if gap < bestGap then
			best, bestGap = s, gap
		end
	end
	if bestGap > MAX_SAMPLE_GAP then
		return nil
	end
	return best
end

-- The server sees a client-owned character late (one-way latency + interpolation), so
-- where the client was at `timestamp` shows up in server samples taken shortly after.
-- Returns the smallest distance to `position` across that window.
local function closestRecordedDistance(player: Player, timestamp: number, position: Vector3): number
	local h = histories[player]
	if not h then
		return math.huge
	end
	local best = math.huge
	for i = 1, h.count do
		local s = h.samples[i]
		if s.Time >= timestamp - MAX_SAMPLE_GAP and s.Time <= timestamp + LATENCY_WINDOW then
			best = math.min(best, (s.CFrame.Position - position).Magnitude)
		end
	end
	return best
end

local function isFiniteCFrame(cf: CFrame): boolean
	local p = cf.Position
	return p == p and p.Magnitude < 1e6
end

local function onRewindTriggered(player: Player, timestamp, targetCFrame)
	local function reject(reason: string)
		resultRemote:FireClient(player, false, reason)
	end

	if typeof(timestamp) ~= "number" or typeof(targetCFrame) ~= "CFrame" then
		return
	end
	if timestamp ~= timestamp or not isFiniteCFrame(targetCFrame) then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return reject("Dead")
	end

	local clock = os.clock()
	if lastRewind[player] and clock - lastRewind[player] < COOLDOWN then
		return reject("Cooldown")
	end

	local age = workspace:GetServerTimeNow() - timestamp
	if age < 0 or age > MAX_REWIND_AGE then
		return reject("Timestamp")
	end

	local sample = nearestSample(player, timestamp)
	if not sample then
		return reject("NoHistory")
	end
	if closestRecordedDistance(player, timestamp, targetCFrame.Position) > TOLERANCE then
		return reject("Tolerance")
	end

	lastRewind[player] = clock
	resultRemote:FireClient(player, true)

	-- Position is not set here: the client owns its character's physics and applies the
	-- rewound CFrame itself. A server write would land ~RTT after the client resumed
	-- moving and yank it back (rubber-band snap).
	task.delay(REWIND_DURATION, function()
		if player.Character ~= character or humanoid.Health <= 0 then
			return
		end
		humanoid.Health = math.min(sample.Health, humanoid.MaxHealth)

		-- Start fresh so the next rewind can't reuse pre-rewind history.
		histories[player] = nil
	end)
end

function RewindService.Init()
	local remotes = ReplicatedStorage:FindFirstChild("TimeRemotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "TimeRemotes"
		remotes.Parent = ReplicatedStorage
	end

	local triggered = Instance.new("RemoteEvent")
	triggered.Name = "RewindTriggered" -- client -> server: timestamp, target CFrame
	triggered.Parent = remotes
	triggered.OnServerEvent:Connect(onRewindTriggered)

	resultRemote = Instance.new("RemoteEvent")
	resultRemote.Name = "RewindResult" -- server -> client: accepted, reason?
	resultRemote.Parent = remotes

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / SAMPLE_RATE then
			return
		end
		accumulator = 0
		local now = workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			record(player, now)
		end
	end)

	local function onPlayerAdded(player: Player)
		-- A new life must not rewind into the previous one's history.
		player.CharacterAdded:Connect(function()
			histories[player] = nil
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		histories[player] = nil
		lastRewind[player] = nil
	end)
end

return RewindService
