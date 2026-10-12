--!strict
-- Toasts and one-shot visual effects sent to clients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Style = "info" | "good" | "bad" | "rare" | "event"

local Notify = {}

function Notify.send(player: Player, text: string, style: Style?)
	Net.fire(player, "Notify", text, style or "info")
end

function Notify.all(text: string, style: Style?)
	Net.fireAll("Notify", text, style or "info")
end

-- Effects: "Hatch", "Roar", "Mutate", "Reward", "Stolen", "Caught", "Collect", "Dex"
function Notify.effect(player: Player, kind: string, data: { [string]: any })
	Net.fire(player, "Effect", kind, data)
end

function Notify.effectAll(kind: string, data: { [string]: any })
	Net.fireAll("Effect", kind, data)
end

return Notify
