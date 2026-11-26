--!strict
-- Winding up and letting go. Hold the left mouse button (or the Throw button
-- on a phone, or R2 on a gamepad) to start the power needle swinging, and let
-- go to throw where the camera is looking. The client only says when you
-- pressed and let go; the server decides how the throw goes.
--
-- Every frame it also works out whether a throw from here would work, so the
-- HUD can show the meter only by the water and say what's wrong.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Lake = require(ReplicatedStorage.Shared.Lake)
local Net = require(ReplicatedStorage.Shared.Net)
local Skip = require(ReplicatedStorage.Shared.Skip)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Audio = require(script.Parent.Audio)

local ThrowInput = {}

ThrowInput.CHARGE_WALKSPEED = 4 -- you plant your feet while winding up

-- "far": nowhere near the water (no meter). "away": by the water but facing
-- the wrong way, or with no room. "high": up on something. "ok": ready.
export type Status = "far" | "away" | "high" | "ok"

export type State = {
	status: Status,
	charging: boolean,
	startedAt: number,
	lastThrowAt: number,
}

ThrowInput.state = {
	status = "far",
	charging = false,
	startedAt = 0,
	lastThrowAt = -math.huge,
} :: State

-- Fired when a press is refused (the HUD flashes the reason).
ThrowInput.refused = Signal.new() :: Signal.Signal<Status>
-- Fired when the player lets go and the throw is sent.
ThrowInput.released = Signal.new() :: Signal.Signal<number>

local savedWalkSpeed: number? = nil
-- The finger holding the on-screen Throw button: letting it go anywhere on
-- the screen throws, even if it slid off the button first.
local holdingTouch: InputObject? = nil

local function parts(): (BasePart?, Humanoid?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

-- Where a throw would go: along the camera's view, flattened.
function ThrowInput.direction(): Vector3?
	local camera = Workspace.CurrentCamera
	local flat = camera and Lake.flatten(camera.CFrame.LookVector)
	if flat then
		return flat
	end
	local root = parts()
	return root and Lake.flatten(root.CFrame.LookVector)
end

-- Would a throw from where the player stands work right now?
function ThrowInput.check(): Status
	local root, humanoid = parts()
	if not root or not humanoid or humanoid.Sit then
		return "far"
	end
	local position = root.CFrame.Position
	if Lake.distanceFromCentre(position) > Lake.EDGE + Config.THROW_REACH then
		return "far"
	end
	if position.Y > Config.MAX_THROW_HEIGHT then
		return "high"
	end
	local direction = ThrowInput.direction()
	if not direction then
		return "away"
	end
	local entry, reach = Lake.entry(position, direction)
	if not entry or reach > Config.THROW_REACH then
		return "away"
	end
	if Lake.openWater(entry, direction) < Lake.MIN_OPEN_WATER then
		return "away"
	end
	return "ok"
end

function ThrowInput.coolingDown(): boolean
	return os.clock() - ThrowInput.state.lastThrowAt < Config.THROW_COOLDOWN
end

-- Where the needle is now (0 while not winding up).
function ThrowInput.power(): number
	local state = ThrowInput.state
	if not state.charging then
		return 0
	end
	return Skip.power(os.clock() - state.startedAt)
end

local function plantFeet(on: boolean)
	local _, humanoid = parts()
	if on then
		if humanoid and savedWalkSpeed == nil then
			savedWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = ThrowInput.CHARGE_WALKSPEED
		end
	else
		if humanoid and savedWalkSpeed then
			humanoid.WalkSpeed = savedWalkSpeed
		end
		savedWalkSpeed = nil
	end
end

local function stopCharging(tellServer: boolean)
	local state = ThrowInput.state
	if not state.charging then
		return
	end
	state.charging = false
	holdingTouch = nil
	plantFeet(false)
	if tellServer then
		Net.send("CancelCharge")
	end
end

-- Start winding up (if a throw from here would work). `touch` is the finger
-- on the Throw button, if that's what pressed.
function ThrowInput.press(touch: InputObject?)
	local state = ThrowInput.state
	if state.charging then
		return
	end
	local status: Status = ThrowInput.check() :: Status
	state.status = status
	if status ~= "ok" then
		if status ~= "far" then
			ThrowInput.refused:fire(status)
		end
		return
	end
	if ThrowInput.coolingDown() then
		return
	end
	state.charging = true
	state.startedAt = os.clock()
	holdingTouch = touch
	plantFeet(true)
	Net.send("BeginCharge")
end

-- Let go: throw (a quick tap just cancels).
function ThrowInput.letGo()
	holdingTouch = nil
	local state = ThrowInput.state
	if not state.charging then
		return
	end
	local held = os.clock() - state.startedAt
	if held < Config.MIN_CHARGE_SECONDS then
		stopCharging(true)
		return
	end
	local direction = ThrowInput.direction()
	local root = parts()
	if not direction or not root then
		stopCharging(true)
		return
	end
	stopCharging(false)
	-- face the throw
	root.CFrame = CFrame.lookAt(root.CFrame.Position, root.CFrame.Position + direction)
	Net.send("Release", direction, held)
	state.lastThrowAt = os.clock()
	Audio.play("throw")
	ThrowInput.released:fire(Skip.power(held))
end

local function isThrowInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
end

function ThrowInput.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and isThrowInput(input) then
			ThrowInput.press()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		-- (let go even over a button, so the throw never gets stuck)
		if isThrowInput(input) or (holdingTouch ~= nil and input == holdingTouch) then
			ThrowInput.letGo()
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		savedWalkSpeed = nil
		ThrowInput.state.charging = false
	end)
end

-- Once a frame (cheap; the HUD also calls it just before drawing, so it
-- never shows last frame's answer).
function ThrowInput.update()
	local state = ThrowInput.state
	if not state.charging then
		state.status = ThrowInput.check()
		return
	end
	-- gone (died, reset), or held so long it doesn't count
	local root = parts()
	if not root or os.clock() - state.startedAt > Config.MAX_CHARGE_SECONDS then
		stopCharging(true)
	end
end

function ThrowInput.start()
	RunService.RenderStepped:Connect(ThrowInput.update)
end

return ThrowInput
