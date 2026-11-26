--!strict
-- Little messages that pop up on a player's screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

export type Style = "info" | "good" | "bad" | "rare"

local Notify = {}

function Notify.send(player: Player, text: string, style: Style?)
	Net.fire(player, "Notify", text, style or "info")
end

function Notify.all(text: string, style: Style?)
	Net.fireAll("Notify", text, style or "info")
end

return Notify
