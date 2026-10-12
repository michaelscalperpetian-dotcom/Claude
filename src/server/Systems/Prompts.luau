--!strict
-- One place that creates ProximityPrompts and routes their triggers to the
-- system that owns each action. Prompts carry attributes the client uses to
-- decide who sees them (owner only, visitors only, night only...). The client
-- only hides/shows; every handler re-validates on the server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Prompts = {}

Prompts.TAG = "GamePrompt"

export type Audience = "Owner" | "Others" | "All"

export type Options = {
	action: string, -- handler name, or "OpenUI" for client-only prompts
	text: string,
	objectText: string?,
	audience: Audience,
	ownerId: number?,
	plotIndex: number?,
	key: string?, -- id of the thing this prompt acts on (egg id, incubator slot...)
	hold: number?,
	keyCode: Enum.KeyCode?,
	distance: number?,
	nightOnly: boolean?,
	hideInTutorial: boolean?,
	openUI: string?,
}

type Handler = (player: Player, prompt: ProximityPrompt) -> ()

local handlers: { [string]: Handler } = {}
local lastTrigger: { [Player]: { [string]: number } } = {}

function Prompts.register(action: string, handler: Handler)
	assert(handlers[action] == nil, `prompt action {action} registered twice`)
	handlers[action] = handler
end

function Prompts.create(parent: Instance, options: Options): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = options.text
	prompt.ObjectText = options.objectText or ""
	prompt.HoldDuration = options.hold or 0
	prompt.KeyboardKeyCode = options.keyCode or Enum.KeyCode.E
	prompt.MaxActivationDistance = options.distance or 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", options.action)
	prompt:SetAttribute("Audience", options.audience)
	if options.ownerId then
		prompt:SetAttribute("OwnerId", options.ownerId)
	end
	if options.plotIndex then
		prompt:SetAttribute("PlotIndex", options.plotIndex)
	end
	if options.key then
		prompt:SetAttribute("Key", options.key)
	end
	if options.nightOnly then
		prompt:SetAttribute("NightOnly", true)
	end
	if options.hideInTutorial then
		prompt:SetAttribute("HideInTutorial", true)
	end
	if options.openUI then
		prompt:SetAttribute("OpenUI", options.openUI)
	end
	CollectionService:AddTag(prompt, Prompts.TAG)
	prompt.Parent = parent
	return prompt
end

function Prompts.key(prompt: ProximityPrompt): string?
	local key = prompt:GetAttribute("Key")
	return if typeof(key) == "string" then key else nil
end

function Prompts.ownerId(prompt: ProximityPrompt): number?
	local id = prompt:GetAttribute("OwnerId")
	return if typeof(id) == "number" then id else nil
end

function Prompts.init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local action = prompt:GetAttribute("Action")
		if typeof(action) ~= "string" then
			return
		end
		local handler = handlers[action]
		if not handler then
			return
		end
		-- Light rate limit: max 8 triggers per second per action.
		local now = os.clock()
		local perPlayer = lastTrigger[player]
		if not perPlayer then
			perPlayer = {}
			lastTrigger[player] = perPlayer
		end
		local last = perPlayer[action]
		if last and now - last < 0.125 then
			return
		end
		perPlayer[action] = now
		handler(player, prompt)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTrigger[player] = nil
	end)
end

return Prompts
