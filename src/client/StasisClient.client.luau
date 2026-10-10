--!nonstrict
-- Stasis Field input (key F). The server places the field where you aim and enforces
-- the cooldown; this mirrors the cooldown locally so requests aren't spammed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local STASIS_KEY = Enum.KeyCode.F
local COOLDOWN = 12 -- mirrored from StasisService

local player = Players.LocalPlayer
local deployRemote = ReplicatedStorage:WaitForChild("TimeRemotes"):WaitForChild("StasisDeploy")
local lastDeploy = -math.huge

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= STASIS_KEY then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or os.clock() - lastDeploy < COOLDOWN then
		return
	end
	lastDeploy = os.clock()

	local cf = workspace.CurrentCamera.CFrame
	deployRemote:FireServer(cf.Position, cf.LookVector)
end)
