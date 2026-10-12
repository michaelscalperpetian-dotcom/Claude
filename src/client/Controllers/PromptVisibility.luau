--!strict
-- Shows each ProximityPrompt only to the players it's for (owner vs visitors,
-- night-only steal prompts, tutorial gating) and opens UI for client-only
-- prompts. Purely cosmetic: the server re-checks everything on trigger.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Clock = require(ReplicatedStorage.Shared.Util.Clock)
local ClientState = require(script.Parent.ClientState)
local DinoPanel = require(script.Parent.DinoPanel)
local ShopUI = require(script.Parent.ShopUI)

local PromptVisibility = {}

local TAG = "GamePrompt"

local function plotModel(index: number): Model?
	local plots = Workspace:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. index)
	if plot and plot:IsA("Model") then
		return plot
	end
	return nil
end

local function numberAttribute(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function shouldShow(prompt: ProximityPrompt): boolean
	local me = Players.LocalPlayer.UserId
	local snapshot = ClientState.get()
	local audience = prompt:GetAttribute("Audience")
	local plotIndex = numberAttribute(prompt, "PlotIndex")
	local plot = if plotIndex > 0 then plotModel(plotIndex) else nil
	local ownerId = numberAttribute(prompt, "OwnerId")
	if ownerId == 0 and plot then
		ownerId = numberAttribute(plot, "OwnerId")
	end

	if audience == "Owner" and ownerId ~= me then
		return false
	elseif audience == "Others" and (ownerId == me or ownerId == 0) then
		return false
	end

	if prompt:GetAttribute("HideInTutorial") and ClientState.tutorialActive() then
		return false
	end

	if prompt:GetAttribute("NightOnly") then
		if not ClientState.isNight() or ReplicatedStorage:GetAttribute("RaidsEnabled") == false then
			return false
		end
		if snapshot and snapshot.carrying then
			return false
		end
		if plot then
			local now = Clock.now()
			if
				numberAttribute(plot, "LockedUntil") > now
				or numberAttribute(plot, "ShieldUntil") > now
			then
				return false
			end
		end
	end
	return true
end

local function update(prompt: ProximityPrompt)
	local show = shouldShow(prompt)
	if prompt.Enabled ~= show then
		prompt.Enabled = show
	end
end

function PromptVisibility.init()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance)
		if instance:IsA("ProximityPrompt") then
			update(instance)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local openUI = prompt:GetAttribute("OpenUI")
		if openUI == "Shop" then
			ShopUI.open()
		elseif openUI == "Dino" then
			local key = prompt:GetAttribute("Key")
			if typeof(key) == "string" then
				DinoPanel.open(key)
			end
		end
	end)
end

function PromptVisibility.start()
	while true do
		for _, instance in CollectionService:GetTagged(TAG) do
			if instance:IsA("ProximityPrompt") then
				update(instance)
			end
		end
		task.wait(0.3)
	end
end

return PromptVisibility
