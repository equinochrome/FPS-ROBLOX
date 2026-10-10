--!nonstrict
-- Camera impulse spring (INSTRUCTIONS.md section 3).
-- Damped spring x'' = -Stiffness * x - Damping * x' over (pitch, yaw, roll) in radians,
-- with Stiffness = 220 and Damping = 18 (underdamped, damping ratio ~0.61).
--
-- Kick values are the *peak* angle in degrees the camera reaches, so weapon configs
-- can use the spec's numbers directly (e.g. Pulse-AR Pitch +0.45).

local RunService = game:GetService("RunService")

local CameraRecoil = {}

local STIFFNESS = 220
local DAMPING = 18
local SUBSTEP = 1 / 240 -- fixed integration step so behaviour is frame-rate independent
local BIND_NAME = "CameraRecoil"
local PITCH_LIMIT = math.rad(79.5) -- just inside the default camera's 80 degree clamp

-- Velocity impulse that makes the spring's displacement peak at exactly 1 unit.
local function peakGain(k: number, d: number): number
	local w0 = math.sqrt(k)
	local zeta = d / (2 * w0)
	if zeta >= 1 then
		return w0 * math.exp(1) -- critically/over-damped approximation
	end
	local wd = w0 * math.sqrt(1 - zeta * zeta)
	local tPeak = math.atan2(wd, zeta * w0) / wd
	return wd / (math.exp(-zeta * w0 * tPeak) * math.sin(wd * tPeak))
end

local GAIN = peakGain(STIFFNESS, DAMPING)

-- Exposed so other springs (the viewmodel) can convert peak values into impulses.
CameraRecoil.PeakGain = peakGain

local position = Vector3.zero -- current offset (pitch, yaw, roll), radians
local velocity = Vector3.zero
local applied = Vector3.zero -- pitch/yaw already written into the camera

-- Add a kick whose peak is (pitchDeg, yawDeg, rollDeg).
function CameraRecoil.Kick(pitchDeg: number, yawDeg: number, rollDeg: number?)
	velocity += Vector3.new(math.rad(pitchDeg), math.rad(yawDeg), math.rad(rollDeg or 0)) * GAIN
end

-- Kick from a weapon config's CameraRecoil table { Pitch, YawMin, YawMax, Roll }.
function CameraRecoil.Fire(recoil)
	if not recoil then
		return
	end
	local yaw = recoil.YawMin + math.random() * (recoil.YawMax - recoil.YawMin)
	CameraRecoil.Kick(recoil.Pitch, yaw, recoil.Roll)
end

-- Stops the spring. `applied` is kept so the next frame unwinds whatever offset is
-- still in the camera; zeroing it would leave the aim permanently kicked.
function CameraRecoil.Reset()
	position, velocity = Vector3.zero, Vector3.zero
end

local function integrate(dt: number)
	local remaining = math.min(dt, 0.1)
	while remaining > 0 do
		local h = math.min(SUBSTEP, remaining)
		local accel = -position * STIFFNESS - velocity * DAMPING
		velocity += accel * h
		position += velocity * h
		remaining -= h
	end
end

-- Runs just after Roblox's camera update and before the viewmodel (Camera + 2).
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
	integrate(dt)

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- The default camera builds each frame from the current look vector, so pitch/yaw
	-- are written as deltas: the kick persists and the spring carries it back.
	-- It also re-levels roll every frame, so roll is applied absolutely.
	local dPitch = position.X - applied.X
	local dYaw = position.Y - applied.Y

	-- The camera module clamps pitch to +/-80 degrees when it rebuilds next frame. Any
	-- kick past that would be silently discarded while the recovery still pulled the
	-- aim back down, so only apply what fits and track what was actually applied.
	local currentPitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
	dPitch = math.clamp(dPitch, -PITCH_LIMIT - currentPitch, PITCH_LIMIT - currentPitch)
	applied = Vector3.new(applied.X + dPitch, position.Y, 0)

	camera.CFrame = camera.CFrame * CFrame.Angles(dPitch, dYaw, 0) * CFrame.Angles(0, 0, position.Z)
end)

return CameraRecoil
