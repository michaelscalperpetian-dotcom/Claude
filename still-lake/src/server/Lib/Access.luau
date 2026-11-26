--!strict
-- Who may use the test tools: everyone in Studio, and in live games the
-- game's owner plus anyone in Config.DEV_USER_IDS.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Access = {}

function Access.isDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.DEV_USER_IDS, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

return Access
