--!strict
-- Builds the Neo-Tokyo Plaza blockout described in the Chrono-Ops GDD (Step 1).
-- Coordinates: ground top is y = 0, X is east/west, Z is north/south (-Z = north).

local CollectionService = game:GetService("CollectionService")

local MapBuilder = {}

-- GDD dimensions (studs)
local DOOR_W = 6
local DOOR_H = 10
local HALF_COVER = 4
local FULL_COVER = 8
local WALL_T = 2

local PLAZA_HALF = 100 -- perimeter wall centerlines at +/-100
local PERIMETER_H = 24

-- Beta site: corporate lobby (west). Leaves a 16 stud corridor to the perimeter.
local LOBBY_X0, LOBBY_X1 = -84, -30
local LOBBY_Z0, LOBBY_Z1 = -35, 35
local LOBBY_H = 16

-- Alpha site: rooftop tower (east). Leaves a 16 stud corridor to the perimeter.
local TOWER_X0, TOWER_X1 = 40, 84
local TOWER_Z0, TOWER_Z1 = -35, 35
local ROOF_Y = 20

local COLORS = {
	ground = Color3.fromRGB(55, 57, 66),
	wall = Color3.fromRGB(88, 92, 104),
	building = Color3.fromRGB(70, 74, 86),
	cover = Color3.fromRGB(120, 124, 138),
	fullCover = Color3.fromRGB(100, 104, 120),
	neonPink = Color3.fromRGB(255, 60, 160),
	neonCyan = Color3.fromRGB(40, 230, 255),
}

local function box(parent: Instance, name: string, center: Vector3, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.Concrete
	p.Color = color
	p.Size = size
	p.CFrame = CFrame.new(center)
	p.Parent = parent
	return p
end

-- Wall running along `axis` ("X" = along X at z = fixed, "Z" = along Z at x = fixed)
-- from `from` to `to`. Each entry in `gaps` is the center of a DOOR_W wide opening;
-- `lintelFrom` fills the area above the opening (nil = open to the top, e.g. parapets).
local function wall(
	parent: Instance,
	name: string,
	axis: "X" | "Z",
	fixed: number,
	from: number,
	to: number,
	y0: number,
	y1: number,
	gaps: { number },
	lintelFrom: number?,
	color: Color3
)
	local function segment(a: number, b: number, bottom: number, top: number)
		local len, h = b - a, top - bottom
		if len <= 0.01 or h <= 0.01 then
			return
		end
		local mid, midY = (a + b) / 2, (bottom + top) / 2
		if axis == "X" then
			box(parent, name, Vector3.new(mid, midY, fixed), Vector3.new(len, h, WALL_T), color)
		else
			box(parent, name, Vector3.new(fixed, midY, mid), Vector3.new(WALL_T, h, len), color)
		end
	end

	local sorted = table.clone(gaps)
	table.sort(sorted)
	local cursor = from
	for _, g in sorted do
		local g0, g1 = g - DOOR_W / 2, g + DOOR_W / 2
		segment(cursor, g0, y0, y1)
		if lintelFrom then
			segment(g0, g1, y0 + lintelFrom, y1)
		end
		cursor = g1
	end
	segment(cursor, to, y0, y1)
end

local function cover(parent: Instance, name: string, x: number, z: number, sx: number, sz: number, height: number, baseY: number?)
	local color = if height >= FULL_COVER then COLORS.fullCover else COLORS.cover
	local y = (baseY or 0) + height / 2
	local p = box(parent, name, Vector3.new(x, y, z), Vector3.new(sx, height, sz), color)
	CollectionService:AddTag(p, if height >= FULL_COVER then "FullCover" else "HalfCover")
end

local function siteMarker(parent: Instance, name: string, center: Vector3, size: Vector3)
	local p = box(parent, name, center, size, COLORS.neonCyan)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("Site", name)
	CollectionService:AddTag(p, "BombSite")
end

local function buildPlaza(map: Folder)
	local ground = Instance.new("Folder")
	ground.Name = "Plaza"
	ground.Parent = map

	-- Floor plate over the baseplate so the plaza reads as its own space.
	box(ground, "PlazaFloor", Vector3.new(0, -0.5, 0), Vector3.new(PLAZA_HALF * 2, 1, PLAZA_HALF * 2), COLORS.ground, Enum.Material.Slate)

	-- Perimeter, closed except for nothing: attackers/defenders spawn inside.
	local H = PLAZA_HALF
	wall(ground, "Perimeter", "X", -H, -H, H, 0, PERIMETER_H, {}, nil, COLORS.wall)
	wall(ground, "Perimeter", "X", H, -H, H, 0, PERIMETER_H, {}, nil, COLORS.wall)
	wall(ground, "Perimeter", "Z", -H, -H, H, 0, PERIMETER_H, {}, nil, COLORS.wall)
	wall(ground, "Perimeter", "Z", H, -H, H, 0, PERIMETER_H, {}, nil, COLORS.wall)

	-- Central plaza cover (mix of half and full per GDD).
	local c = Instance.new("Folder")
	c.Name = "PlazaCover"
	c.Parent = ground
	cover(c, "FullWallN", -5, -30, 14, 3, FULL_COVER)
	cover(c, "FullWallS", 5, 30, 14, 3, FULL_COVER)
	cover(c, "Pillar", 0, 0, 4, 4, FULL_COVER)
	cover(c, "HalfNW", -12, 12, 8, 3, HALF_COVER)
	cover(c, "HalfSE", 12, -12, 8, 3, HALF_COVER)
	cover(c, "HalfW", -20, 0, 3, 10, HALF_COVER)
	cover(c, "HalfE", 20, 0, 3, 10, HALF_COVER)

	-- Neutral spawn at the south end of the plaza.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, 80)
	spawn.Parent = ground
end

local function buildBetaLobby(map: Folder)
	local lobby = Instance.new("Folder")
	lobby.Name = "BetaLobby"
	lobby.Parent = map

	local midX = (LOBBY_X0 + LOBBY_X1) / 2
	local midZ = (LOBBY_Z0 + LOBBY_Z1) / 2

	-- Shell: doorways are 6 wide x 10 tall. West wall solid; east wall has two doors;
	-- north and south have one door each, giving tight multi-angle entries.
	wall(lobby, "WestWall", "Z", LOBBY_X0, LOBBY_Z0, LOBBY_Z1, 0, LOBBY_H, {}, nil, COLORS.building)
	wall(lobby, "EastWall", "Z", LOBBY_X1, LOBBY_Z0, LOBBY_Z1, 0, LOBBY_H, { -18, 18 }, DOOR_H, COLORS.building)
	wall(lobby, "NorthWall", "X", LOBBY_Z0, LOBBY_X0, LOBBY_X1, 0, LOBBY_H, { midX }, DOOR_H, COLORS.building)
	wall(lobby, "SouthWall", "X", LOBBY_Z1, LOBBY_X0, LOBBY_X1, 0, LOBBY_H, { midX }, DOOR_H, COLORS.building)
	box(
		lobby,
		"Roof",
		Vector3.new(midX, LOBBY_H + 0.5, midZ),
		Vector3.new(LOBBY_X1 - LOBBY_X0 + WALL_T, 1, LOBBY_Z1 - LOBBY_Z0 + WALL_T),
		COLORS.building
	)

	-- Interior cover: reception desk and sofas (half), pillars (full).
	cover(lobby, "ReceptionDesk", -65, 0, 16, 4, HALF_COVER)
	cover(lobby, "SofaA", -45, -8, 8, 3, HALF_COVER)
	cover(lobby, "SofaB", -45, 8, 8, 3, HALF_COVER)
	for _, pos in { Vector2.new(-50, -20), Vector2.new(-50, 20), Vector2.new(-72, -20), Vector2.new(-72, 20) } do
		cover(lobby, "Pillar", pos.X, pos.Y, 4, 4, FULL_COVER)
	end

	-- Neon signage over the east doors.
	for _, z in { -18, 18 } do
		box(lobby, "NeonSign", Vector3.new(LOBBY_X1 + 1.1, DOOR_H + 2, z), Vector3.new(0.4, 1, DOOR_W), COLORS.neonPink, Enum.Material.Neon)
	end

	local sites = map:FindFirstChild("Sites") :: Folder
	siteMarker(sites, "Beta", Vector3.new(midX, 6, midZ), Vector3.new(LOBBY_X1 - LOBBY_X0 - 4, 12, LOBBY_Z1 - LOBBY_Z0 - 4))
end

local function buildAlphaRooftop(map: Folder)
	local alpha = Instance.new("Folder")
	alpha.Name = "AlphaRooftop"
	alpha.Parent = map

	local midX = (TOWER_X0 + TOWER_X1) / 2
	local midZ = (TOWER_Z0 + TOWER_Z1) / 2
	local sizeX, sizeZ = TOWER_X1 - TOWER_X0, TOWER_Z1 - TOWER_Z0

	-- Solid tower block; roof surface sits at ROOF_Y.
	box(alpha, "Tower", Vector3.new(midX, ROOF_Y / 2, midZ), Vector3.new(sizeX, ROOF_Y, sizeZ), COLORS.building)

	-- Access ramp on the south face, 12 wide, rising to the roof edge.
	local rampRun = 40
	local rampLen = math.sqrt(rampRun ^ 2 + ROOF_Y ^ 2)
	local angle = math.atan2(ROOF_Y, rampRun)
	local ramp = box(alpha, "Ramp", Vector3.new(65, ROOF_Y / 2, TOWER_Z1 + rampRun / 2), Vector3.new(12, 1, rampLen), COLORS.cover)
	ramp.CFrame = CFrame.new(65, ROOF_Y / 2 - 0.5, TOWER_Z1 + rampRun / 2) * CFrame.Angles(angle, 0, 0)

	-- West parapet (half cover) with two openings: the long Aegis-Rail sightline
	-- over the plaza is intentionally exposed.
	wall(alpha, "Parapet", "Z", TOWER_X0 + 1, TOWER_Z0, TOWER_Z1, ROOF_Y, ROOF_Y + HALF_COVER, { -20, 20 }, nil, COLORS.cover)

	-- Rooftop cover.
	cover(alpha, "RoofFullA", 60, -15, 6, 3, FULL_COVER, ROOF_Y)
	cover(alpha, "RoofFullB", 60, 15, 6, 3, FULL_COVER, ROOF_Y)
	cover(alpha, "RoofFullC", 74, 0, 4, 10, FULL_COVER, ROOF_Y)
	cover(alpha, "RoofHalfA", 50, 0, 6, 6, HALF_COVER, ROOF_Y)
	cover(alpha, "RoofHalfB", 70, -25, 6, 6, HALF_COVER, ROOF_Y)
	cover(alpha, "RoofHalfC", 50, 25, 6, 6, HALF_COVER, ROOF_Y)

	box(alpha, "NeonStrip", Vector3.new(TOWER_X0 - 0.2, ROOF_Y - 2, midZ), Vector3.new(0.4, 1, sizeZ), COLORS.neonCyan, Enum.Material.Neon)

	local sites = map:FindFirstChild("Sites") :: Folder
	siteMarker(sites, "Alpha", Vector3.new(midX - 2, ROOF_Y + 6, midZ), Vector3.new(sizeX - 8, 12, sizeZ - 8))
end

function MapBuilder.build(): Folder
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"

	local sites = Instance.new("Folder")
	sites.Name = "Sites"
	sites.Parent = map

	buildPlaza(map)
	buildBetaLobby(map)
	buildAlphaRooftop(map)

	map.Parent = workspace
	return map
end

return MapBuilder
