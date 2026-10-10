--!nonstrict
-- Stationary hitbox dummy for testing weapons. Health lives in attributes;
-- the dummy "goes down" briefly then resets instead of using a Humanoid.

local CollectionService = game:GetService("CollectionService")

local TargetDummy = {}

local MAX_HEALTH = 100
local RESPAWN_TIME = 2.5
local HIT_COLOR = Color3.fromRGB(255, 70, 70)

local function part(model: Model, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p:SetAttribute("BaseColor", color)
	p.Parent = model
	return p
end

local function updateLabel(model: Model)
	local head = model:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("HealthGui")
	local label = gui and gui:FindFirstChild("Label")
	if label then
		if model:GetAttribute("Down") then
			label.Text = "DOWN"
		else
			label.Text = `{math.ceil(model:GetAttribute("Health"))} / {MAX_HEALTH}`
		end
	end
end

function TargetDummy.spawn(parent: Instance, groundPosition: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "TargetDummy"

	local base = Color3.fromRGB(230, 200, 60)
	local g = groundPosition
	part(model, "Legs", Vector3.new(2, 2, 1), g + Vector3.new(0, 1, 0), base)
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), g + Vector3.new(0, 3, 0), base)
	local head = part(model, "Head", Vector3.new(1.5, 1.5, 1.5), g + Vector3.new(0, 4.75, 0), base)
	model.PrimaryPart = torso

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthGui"
	gui.Size = UDim2.fromOffset(100, 24)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = gui

	model:SetAttribute("Health", MAX_HEALTH)
	model:SetAttribute("Down", false)
	CollectionService:AddTag(model, "TargetDummy")
	model.Parent = parent
	updateLabel(model)
	return model
end

-- Returns true if this hit took the dummy down.
function TargetDummy.TakeDamage(model: Model, amount: number): boolean
	if model:GetAttribute("Down") then
		return false
	end

	local health = math.max(model:GetAttribute("Health") - amount, 0)
	model:SetAttribute("Health", health)

	-- Hit flash.
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			p.Color = HIT_COLOR
			task.delay(0.08, function()
				p.Color = p:GetAttribute("BaseColor")
			end)
		end
	end

	if health <= 0 then
		model:SetAttribute("Down", true)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = 0.7
				p.CanQuery = false
			end
		end
		updateLabel(model)

		task.delay(RESPAWN_TIME, function()
			model:SetAttribute("Health", MAX_HEALTH)
			model:SetAttribute("Down", false)
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") then
					p.Transparency = 0
					p.CanQuery = true
				end
			end
			updateLabel(model)
		end)
		return true
	end

	updateLabel(model)
	return false
end

return TargetDummy
