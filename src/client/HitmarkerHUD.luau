--!nonstrict
-- Dynamic crosshair and hit-confirm feedback (INSTRUCTIONS.md section 3).
--
--   Crosshair gap (px) = BaseOffset + SpreadAngle * 14 + Velocity.Magnitude * 0.8
--   HitConfirmed (server -> client): isHeadshot, killed, damage
--     Body:     white X flash, 0.12s, tick at pitch 1.0
--     Headshot: cyan-then-red double X flash, 0.20s, 1.4x size, tick at pitch 1.45

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HitmarkerHUD = {}

local BASE_OFFSET = 6 -- px, ASSUMPTION
local SPREAD_SCALE = 14
local VELOCITY_SCALE = 0.8
local LINE_LENGTH = 8
local LINE_THICKNESS = 2
local CROSSHAIR_COLOR = Color3.new(1, 1, 1)

-- The spec's rbxassetid://9114223179 is not an audio asset ("Asset type does not match
-- requested type"). Using a built-in UI tick until a real hit sound is uploaded.
local HIT_SOUND_ID = "rbxasset://sounds/volume_slider.ogg"
local MARKER_SIZE = 18 -- px, body hitmarker
local BODY = { Duration = 0.12, Scale = 1.0, Pitch = 1.0, Color = Color3.new(1, 1, 1) }
local HEAD = {
	Duration = 0.20,
	Scale = 1.4,
	Pitch = 1.45,
	FirstColor = Color3.fromRGB(0, 220, 255),
	SecondColor = Color3.fromRGB(255, 50, 50),
}

local player = Players.LocalPlayer
local spreadAngle = 0
local lines = {}
local marker = nil
local markerBars = {}
local bodySound, headSound
local flashToken = 0
local initialized = false

local function bar(parent: Instance, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.BackgroundColor3 = CROSSHAIR_COLOR
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local activeTweens = {}

local function setMarker(color: Color3, scale: number, transparency: number)
	-- A fade still running from the previous hit would overwrite this flash.
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)

	marker.Size = UDim2.fromOffset(MARKER_SIZE * scale, MARKER_SIZE * scale)
	for _, b in markerBars do
		b.BackgroundColor3 = color
		b.BackgroundTransparency = transparency
	end
end

local function fadeMarker(duration: number)
	for _, b in markerBars do
		local tween = TweenService:Create(b, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		table.insert(activeTweens, tween)
		tween:Play()
	end
end

local function flashBody()
	flashToken += 1
	setMarker(BODY.Color, BODY.Scale, 0)
	fadeMarker(BODY.Duration)
	bodySound:Play()
end

local function flashHead()
	flashToken += 1
	local token = flashToken
	local half = HEAD.Duration / 2

	setMarker(HEAD.FirstColor, HEAD.Scale, 0)
	task.delay(half, function()
		if token ~= flashToken then
			return
		end
		setMarker(HEAD.SecondColor, HEAD.Scale, 0)
		fadeMarker(half)
	end)
	headSound:Play()
end

-- Current weapon spread in degrees; drives crosshair expansion.
function HitmarkerHUD.SetSpread(degrees: number)
	spreadAngle = degrees
end

function HitmarkerHUD.SetVisible(visible: boolean)
	for _, l in lines do
		l.Visible = visible
	end
end

function HitmarkerHUD.Init()
	if initialized then
		return
	end
	initialized = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "HitmarkerHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	local center = Instance.new("Frame")
	center.Name = "Crosshair"
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(0, 0)
	center.BackgroundTransparency = 1
	center.Parent = gui

	local vertical = UDim2.fromOffset(LINE_THICKNESS, LINE_LENGTH)
	local horizontal = UDim2.fromOffset(LINE_LENGTH, LINE_THICKNESS)
	lines.Top = bar(center, vertical)
	lines.Bottom = bar(center, vertical)
	lines.Left = bar(center, horizontal)
	lines.Right = bar(center, horizontal)

	-- Hitmarker X: two diagonal bars in a square container.
	marker = Instance.new("Frame")
	marker.Name = "Hitmarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.BackgroundTransparency = 1
	marker.Parent = gui
	for _, rotation in { 45, -45 } do
		local b = bar(marker, UDim2.new(1.2, 0, 0, LINE_THICKNESS))
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.Rotation = rotation
		table.insert(markerBars, b)
	end
	setMarker(BODY.Color, BODY.Scale, 1)

	bodySound = Instance.new("Sound")
	bodySound.Name = "BodyTick"
	bodySound.SoundId = HIT_SOUND_ID
	bodySound.PlaybackSpeed = BODY.Pitch
	bodySound.Parent = gui

	headSound = bodySound:Clone()
	headSound.Name = "HeadTick"
	headSound.PlaybackSpeed = HEAD.Pitch
	headSound.Parent = gui

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0

		local offset = BASE_OFFSET + spreadAngle * SPREAD_SCALE + speed * VELOCITY_SCALE
		local reach = offset + LINE_LENGTH / 2
		lines.Top.Position = UDim2.fromOffset(0, -reach)
		lines.Bottom.Position = UDim2.fromOffset(0, reach)
		lines.Left.Position = UDim2.fromOffset(-reach, 0)
		lines.Right.Position = UDim2.fromOffset(reach, 0)
	end)

	local hitConfirmed = ReplicatedStorage:WaitForChild("WeaponRemotes"):WaitForChild("HitConfirmed")
	hitConfirmed.OnClientEvent:Connect(function(isHeadshot)
		if isHeadshot then
			flashHead()
		else
			flashBody()
		end
	end)
end

return HitmarkerHUD
