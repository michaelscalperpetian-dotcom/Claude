--!strict
-- The stud look (Config.STUD_STYLE). The place ships with the SquareStuds
-- MaterialVariant in MaterialService set as the SmoothPlastic override, so
-- every face of every SmoothPlastic part (world, plots, dinos, eggs) shows
-- square studs once its images are added (see README). Any other style turns
-- that override off; "classic" then gets round studs from Build's surfaces.

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Studs = {}

Studs.VARIANT = "SquareStuds"

-- Runs on the server and on every client.
function Studs.apply()
	local name = if Config.STUD_STYLE == "square" then Studs.VARIANT else ""
	if name ~= "" and not MaterialService:FindFirstChild(name) then
		warn(`[Studs] MaterialService.{name} is missing, so parts stay smooth.`)
		return
	end
	local ok, err = pcall(function()
		MaterialService:SetBaseMaterialOverride(Enum.Material.SmoothPlastic, name)
	end)
	if not ok then
		warn(`[Studs] could not set the SmoothPlastic override: {err}`)
	end
end

return Studs
