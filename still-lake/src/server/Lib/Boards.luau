--!strict
-- A wooden leaderboard: two posts, a cream face and a SurfaceGui with a title
-- and BoardData.ROWS rows, each with Rank / Player / Score labels for the
-- Leaderboards system to fill in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Palette)
local BoardData = require(script.Parent.BoardData)
local Build = require(script.Parent.Build)

local Boards = {}

local INK = Color3.fromRGB(58, 44, 40)

type Column = { name: string, x: number, width: number, align: Enum.TextXAlignment }
local COLUMNS: { Column } = {
	{ name = "Rank", x = 0.02, width = 0.14, align = Enum.TextXAlignment.Center },
	{ name = "Player", x = 0.17, width = 0.5, align = Enum.TextXAlignment.Left },
	{ name = "Score", x = 0.67, width = 0.31, align = Enum.TextXAlignment.Right },
}

-- `base` stands on the ground; its -Z (front) is the readable side.
function Boards.build(
	key: string,
	title: string,
	color: Color3,
	base: CFrame,
	parent: Instance
): SurfaceGui
	local model = Build.model(key, parent)
	for _, side in { -1, 1 } do
		Build.block(
			Vector3.new(0.9, 13, 0.9),
			base * CFrame.new(side * 4.6, 6.5, 0.6),
			Palette.woodDark,
			model,
			{ name = "Post", shadow = false }
		)
	end
	local face = Build.block(
		Vector3.new(9.6, 10.5, 0.6),
		base * CFrame.new(0, 7.4, 0),
		Palette.cream,
		model,
		{ name = "Face", decor = true }
	)
	-- a little roof keeps the rain off
	Build.block(
		Vector3.new(11, 0.6, 2),
		base * CFrame.new(0, 13.1, 0.3),
		Palette.roof,
		model,
		{ name = "Cap", decor = true, shadow = false }
	)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.PixelsPerStud = 40
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = face

	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundColor3 = color
	heading.BorderSizePixel = 0
	heading.Size = UDim2.fromScale(1, 0.13)
	heading.Font = Enum.Font.FredokaOne
	heading.Text = title
	heading.TextScaled = true
	heading.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = heading
	heading.Parent = gui

	local rowHeight = 0.85 / BoardData.ROWS
	for row = 1, BoardData.ROWS do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. row
		frame.BackgroundColor3 = if row % 2 == 0
			then Color3.fromRGB(246, 236, 216)
			else Color3.fromRGB(255, 250, 240)
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromScale(0, 0.14 + (row - 1) * rowHeight)
		frame.Size = UDim2.fromScale(1, rowHeight)
		frame.Parent = gui
		for _, column in COLUMNS do
			local text = Instance.new("TextLabel")
			text.Name = column.name
			text.BackgroundTransparency = 1
			text.Position = UDim2.fromScale(column.x, 0.12)
			text.Size = UDim2.fromScale(column.width, 0.76)
			text.Font = Enum.Font.FredokaOne
			text.TextScaled = true
			text.TextXAlignment = column.align
			text.TextColor3 = INK
			text.Text = if column.name == "Rank" then tostring(row) else ""
			text.Parent = frame
		end
	end
	return gui
end

return Boards
