--!nonstrict
-- Client-only visual tracer: a short-lived neon beam that fades out.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Tracer = {}

local LIFETIME = 0.15
local DEFAULT_COLOR = Color3.fromRGB(40, 230, 255)

function Tracer.draw(from: Vector3, to: Vector3, color: Color3?, lifetime: number?)
	local life = lifetime or LIFETIME
	local camera = workspace.CurrentCamera
	local length = (to - from).Magnitude
	if not camera or length < 0.1 then
		return
	end

	local beam = Instance.new("Part")
	beam.Name = "Tracer"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or DEFAULT_COLOR
	beam.Size = Vector3.new(0.12, 0.12, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Parent = camera -- camera is excluded from weapon raycasts

	TweenService:Create(beam, TweenInfo.new(life, Enum.EasingStyle.Quad), {
		Transparency = 1,
		Size = Vector3.new(0.02, 0.02, length),
	}):Play()
	Debris:AddItem(beam, life + 0.05)
end

return Tracer
