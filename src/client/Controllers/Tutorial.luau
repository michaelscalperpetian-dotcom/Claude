--!strict
-- First-session tutorial on the client: a hint banner and a glowing beam from
-- the player to the next thing to do. The server decides the step (and logs
-- the onboarding funnel).

local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local TutorialData = require(ReplicatedStorage.Shared.Data.TutorialData)
local Types = require(ReplicatedStorage.Shared.Types)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)
local UI = require(script.Parent.Parent.Lib.UI)

local Tutorial = {}

local banner: Frame
local bannerText: TextLabel
local stepChip: UI.Chip
local gotIt: UI.Button
local currentStep = -1

local targetPart: Part
local targetAttachment: Attachment
local beam: Beam
local playerAttachment: Attachment? = nil

local function myPlot(): Model?
	return ClientState.myPlot()
end

local function eggTarget(title: string): BasePart?
	local plot = myPlot()
	local eggs = plot and plot:FindFirstChild("Eggs")
	if not eggs then
		return nil
	end
	local fallback: BasePart? = nil
	for _, egg in eggs:GetChildren() do
		if egg:IsA("Model") and egg.PrimaryPart then
			if egg:GetAttribute("Title") == title then
				return egg.PrimaryPart
			end
			fallback = fallback or egg.PrimaryPart
		end
	end
	return fallback
end

local function targetPosition(step: number): Vector3?
	local info = TutorialData.STEPS[step]
	if not info then
		return nil
	end
	if info.target == "Incubator" then
		local part = eggTarget(if step == 1 then "Starter Egg" else "Gift Egg")
		return part and part.CFrame.Position
	elseif info.target == "Pad" then
		local plot = myPlot()
		local pad = plot and plot:FindFirstChild("CoinPad")
		return if pad and pad:IsA("BasePart") then pad.CFrame.Position else nil
	elseif info.target == "Shop" then
		local map = Workspace:FindFirstChild("Map")
		local hub = map and map:FindFirstChild("Hub")
		local shop = hub and hub:FindFirstChild("ShopPrompt")
		return if shop and shop:IsA("BasePart") then shop.CFrame.Position else nil
	end
	return nil
end

local function attachToCharacter()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local existing = root:FindFirstChild("TutorialAttachment")
	if existing and existing:IsA("Attachment") then
		playerAttachment = existing
	else
		local attachment = Instance.new("Attachment")
		attachment.Name = "TutorialAttachment"
		attachment.Parent = root
		playerAttachment = attachment
	end
	beam.Attachment0 = playerAttachment
end

-- ===== Steps =====

local function setStep(step: number)
	if step == currentStep then
		return
	end
	currentStep = step
	local info = TutorialData.STEPS[step]
	banner.Visible = info ~= nil
	gotIt.root.Visible = step == #TutorialData.STEPS
	if info then
		bannerText.Text = info.text
		stepChip.label.Text = `STEP {step} / {#TutorialData.STEPS}`
		UI.pop(banner)
	end
end

local function finish()
	Net.send("TutorialAction", "Finish")
	-- Let players opt in to "your dino is grown!" style notifications.
	task.spawn(function()
		local ok, canPrompt = pcall(function()
			return ExperienceNotificationService:CanPromptOptInAsync()
		end)
		if ok and canPrompt then
			pcall(function()
				ExperienceNotificationService:PromptOptIn()
			end)
		end
	end)
end

function Tutorial.init()
	local screen = UI.screen("Tutorial", 5)
	banner = UI.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 170),
		Size = UDim2.fromOffset(620, 84),
		BackgroundColor3 = Color3.fromRGB(255, 226, 102),
		Visible = false,
		Parent = screen,
	}, { UI.corner(22), UI.stroke(UI.Theme.ink, 4), UI.shade(0.9) }) :: Frame
	bannerText = UI.body({
		text = "",
		size = UDim2.new(1, -40, 1, -22),
		position = UDim2.fromOffset(20, 14),
		font = UI.Font,
		maxTextSize = 28,
		parent = banner,
	})
	stepChip = UI.chip({
		name = "Step",
		text = "",
		size = UDim2.fromOffset(130, 30),
		position = UDim2.new(0, 18, 0, -16),
		color = UI.Theme.purple,
		maxTextSize = 17,
		parent = banner,
	})
	gotIt = UI.button({
		name = "GotIt",
		text = "Got it! 👍",
		size = UDim2.fromOffset(190, 56),
		position = UDim2.new(0.5, 0, 1, 12),
		anchor = Vector2.new(0.5, 0),
		color = UI.Theme.green,
		parent = banner,
		onClick = finish,
	})
	gotIt.root.Visible = false

	targetPart = Instance.new("Part")
	targetPart.Name = "TutorialTarget"
	targetPart.Anchored = true
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Transparency = 1
	targetPart.Size = Vector3.one
	targetPart.Parent = Workspace.CurrentCamera or Workspace
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = targetPart
	local arrow = Instance.new("BillboardGui")
	arrow.Size = UDim2.fromOffset(80, 80)
	arrow.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	UI.text({
		text = "⬇",
		size = UDim2.fromScale(1, 1),
		color = UI.Theme.gold,
		maxTextSize = 70,
		outlineThickness = 4,
		parent = arrow,
	})
	arrow.Parent = targetPart
	TweenService:Create(
		arrow,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ StudsOffsetWorldSpace = Vector3.new(0, 7, 0) }
	):Play()

	beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(UI.Theme.gold)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.Segments = 12
	beam.CurveSize0 = 6
	beam.CurveSize1 = -4
	beam.Transparency = NumberSequence.new(0.2)
	beam.Enabled = false
	beam.Parent = targetPart

	ClientState.changed:connect(function(snapshot: Types.Snapshot)
		setStep(snapshot.tutorial)
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		attachToCharacter()
	end)
end

function Tutorial.start()
	attachToCharacter()
	local pulse = 0
	while true do
		task.wait(0.2)
		local position = if currentStep >= 1 and currentStep <= #TutorialData.STEPS
			then targetPosition(currentStep)
			else nil
		if position then
			targetPart.CFrame = CFrame.new(position)
			beam.Enabled = playerAttachment ~= nil and playerAttachment.Parent ~= nil
			local arrow = targetPart:FindFirstChildOfClass("BillboardGui")
			if arrow then
				arrow.Enabled = true
			end
		else
			beam.Enabled = false
			local arrow = targetPart:FindFirstChildOfClass("BillboardGui")
			if arrow then
				arrow.Enabled = false
			end
		end
		pulse += 1
		if currentStep == #TutorialData.STEPS and pulse % 8 == 0 then
			local lock = Hud.buttons.Lock
			if lock then
				UI.pop(lock.root)
			end
		end
	end
end

return Tutorial
