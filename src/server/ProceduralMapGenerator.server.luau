--!nonstrict
-- Procedural 3-lane map generator.
--
-- Builds a 5x5 grid of 64-stud tiles from ReplicatedStorage.Assets.MapTiles:
--   * Tile_Spawn_A at (1, 3), Tile_Spawn_B at (5, 3)
--   * 4-way junctions at (2, 3) and (4, 3) split into three lanes:
--       Alpha  (rows 1-2), Center (row 3, through the courtyard), Beta (rows 4-5)
--   * side lanes pick a random row per column, so layouts vary by seed
-- Tiles are rotated in 90-degree steps to match each cell's required openings and
-- positioned so their Socket_* attachments land exactly on the shared cell edges.
-- Sockets are alignment anchors only: a tile may carry all four. Which sides are
-- doorways is probed by raycasting across each socketed edge, or taken from an
-- "Openings" string attribute on the prefab (e.g. "NE", in the prefab's own axes).
-- Each tile's sockets and detected openings are printed at startup.
-- A BFS over socket-to-socket connections must reach Spawn B from Spawn A (and every
-- lane must be continuous) before the map is parented to Workspace.GeneratedMap.
--
-- Grid coordinates: X = column (1 = west, 5 = east), Y = row (1 = north, 5 = south).
-- World: columns run along +X, rows along +Z, grid centred on the origin.
--
-- Seed: set the Workspace attribute "MapSeed" (number) to reproduce a match; otherwise
-- one is derived from tick(). The seed used is printed and stored on GeneratedMap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Hold spawning until there is ground to stand on; released at the bottom of this script.
Players.CharacterAutoLoads = false

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local TargetDummy = require(script.Parent:WaitForChild("TargetDummy"))
local WeaponService = require(script.Parent:WaitForChild("WeaponService"))

local GridSize = Vector2.new(5, 5)
local TileSize = 64

local SPAWN_A = Vector2.new(1, 3)
local SPAWN_B = Vector2.new(5, 3)
local JUNCTION_A = Vector2.new(2, 3)
local JUNCTION_B = Vector2.new(4, 3)
local COURTYARD = Vector2.new(3, 3)
local ALPHA_ROWS = { 1, 2 }
local BETA_ROWS = { 4, 5 }

local MAX_ATTEMPTS = 25
local SOCKET_TOLERANCE = 0.1 -- studs; sockets closer than this count as flush
local SIDE_COURTYARD_CHANCE = 0.35 -- chance a side-lane straight becomes a courtyard choke
local COURTYARD_DUMMIES = 4

local TILE_NAMES = {
	SpawnA = "Tile_Spawn_A",
	SpawnB = "Tile_Spawn_B",
	Straight = "Tile_Corridor_Straight",
	Corner = "Tile_Corridor_Corner",
	Courtyard = "Tile_Choke_Courtyard",
	Intersection = "Tile_Intersection_4Way",
}

local DIR_ORDER = { "N", "E", "S", "W" }
local GRID_STEP = {
	N = Vector2.new(0, -1),
	E = Vector2.new(1, 0),
	S = Vector2.new(0, 1),
	W = Vector2.new(-1, 0),
}
local WORLD_DIR = {
	N = Vector3.new(0, 0, -1),
	E = Vector3.new(1, 0, 0),
	S = Vector3.new(0, 0, 1),
	W = Vector3.new(-1, 0, 0),
}
local OPPOSITE = { N = "S", S = "N", E = "W", W = "E" }

-- Helpers --------------------------------------------------------------------

local function cellKey(p: Vector2): string
	return `{p.X},{p.Y}`
end

local function inBounds(p: Vector2): boolean
	return p.X >= 1 and p.X <= GridSize.X and p.Y >= 1 and p.Y <= GridSize.Y
end

local function cellCenter(p: Vector2): Vector3
	local offsetX = (GridSize.X + 1) / 2
	local offsetY = (GridSize.Y + 1) / 2
	return Vector3.new((p.X - offsetX) * TileSize, 0, (p.Y - offsetY) * TileSize)
end

-- Horizontal direction name closest to a vector.
local function classify(v: Vector3): string
	if math.abs(v.X) >= math.abs(v.Z) then
		return if v.X >= 0 then "E" else "W"
	end
	return if v.Z >= 0 then "S" else "N"
end

-- Canonical string for a set of openings, e.g. { N = true, E = true } -> "NE".
local function openingKey(openings): string
	local s = ""
	for _, d in DIR_ORDER do
		if openings[d] then
			s ..= d
		end
	end
	return s
end

local function dirBetween(a: Vector2, b: Vector2): string?
	local delta = b - a
	for d, step in GRID_STEP do
		if step == delta then
			return d
		end
	end
	return nil
end

-- Prefab analysis ------------------------------------------------------------

local PROBE_HEIGHTS = { 1.5, 3.5 } -- studs above the socket
local PROBE_REACH = 1.5 -- studs either side of the tile edge
local PROBE_ORIGIN = CFrame.new(0, 10000, 0) -- far from the play space

-- Which socketed sides are doorways rather than walls. A temporary copy of the prefab
-- is placed far away and short rays are cast across each edge at the socket (both
-- directions, so walls that overhang the edge are caught). Raycasts test real mesh /
-- union collision geometry, not bounding boxes.
local function probeOpenings(prefab: Model, localSockets): { [string]: boolean }
	local probe = prefab:Clone()
	probe:PivotTo(PROBE_ORIGIN)
	for _, d in probe:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	probe.Parent = workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { probe }
	params.RespectCanCollide = true

	local open = {}
	for d, offset in localSockets do
		local edge = PROBE_ORIGIN:PointToWorldSpace(offset)
		local inward = -WORLD_DIR[d]
		local blocked = false
		for _, h in PROBE_HEIGHTS do
			local outside = edge + Vector3.new(0, h, 0) - inward * PROBE_REACH
			local inside = edge + Vector3.new(0, h, 0) + inward * PROBE_REACH
			if
				workspace:Raycast(outside, inside - outside, params)
				or workspace:Raycast(inside, outside - inside, params)
			then
				blocked = true
				break
			end
		end
		open[d] = not blocked or nil
	end

	probe:Destroy()
	return open
end

-- For each prefab and each 90-degree rotation, record which sides have sockets and
-- where each socket sits relative to the pivot after rotation.
local function analyzePrefabs(folder: Instance)
	local catalog = {} -- [prefabName] = { Prefab, Variants = { { Rotation, Key, Sockets = { [dir] = offset } } } }

	for role, name in TILE_NAMES do
		local prefab = folder:FindFirstChild(name)
		if not prefab or not prefab:IsA("Model") then
			error(`[ProceduralMapGenerator] Missing tile prefab {folder:GetFullName()}.{name} (role {role})`)
		end

		local pivot = prefab:GetPivot()
		local localSockets = {}
		for _, d in prefab:GetDescendants() do
			local named = d:IsA("Attachment") and string.match(d.Name, "^Socket_([NESW])$")
			if named and d.Parent:IsA("BasePart") then
				local offset = pivot:ToObjectSpace(d.Parent.CFrame * d.CFrame).Position
				local actual = classify(offset)
				if actual ~= named then
					warn(
						`[ProceduralMapGenerator] {name}.{d.Name} sits on the {actual} side of the pivot; `
							.. `using its position, not its name`
					)
				end
				if math.abs(Vector3.new(offset.X, 0, offset.Z).Magnitude - TileSize / 2) > 1 then
					warn(
						`[ProceduralMapGenerator] {name}.{d.Name} is {math.floor(Vector3.new(offset.X, 0, offset.Z).Magnitude * 10) / 10} `
							.. `studs from the pivot; expected {TileSize / 2} (tile edge)`
					)
				end
				if localSockets[actual] then
					warn(`[ProceduralMapGenerator] {name} has two sockets on its {actual} side`)
				end
				localSockets[actual] = offset
			end
		end
		if next(localSockets) == nil then
			error(`[ProceduralMapGenerator] {name} has no Socket_N/S/E/W attachments`)
		end

		-- Sockets are alignment anchors; which of them are doorways is decided separately.
		local localOpen, source
		local override = prefab:GetAttribute("Openings")
		if typeof(override) == "string" and override ~= "" then
			localOpen, source = {}, "Openings attribute"
			for letter in string.gmatch(string.upper(override), "[NESW]") do
				if localSockets[letter] then
					localOpen[letter] = true
				else
					warn(`[ProceduralMapGenerator] {name}.Openings lists {letter} but there is no socket on that side`)
				end
			end
		else
			localOpen, source = probeOpenings(prefab, localSockets), "probed"
		end
		print(
			`[ProceduralMapGenerator] {name}: sockets {openingKey(localSockets)} | open {openingKey(localOpen)} ({source})`
		)

		local unanchored = 0
		for _, d in prefab:GetDescendants() do
			if d:IsA("BasePart") and not d.Anchored then
				unanchored += 1
			end
		end
		if unanchored > 0 then
			warn(`[ProceduralMapGenerator] {name} has {unanchored} unanchored parts; anchoring them on placement`)
		end

		local extents = prefab:GetExtentsSize()
		if math.max(extents.X, extents.Z) > TileSize + 0.1 then
			warn(`[ProceduralMapGenerator] {name} is {extents} studs; geometry wider than {TileSize} will overlap neighbours`)
		end

		local variants = {}
		for quarterTurns = 0, 3 do
			local rotation = CFrame.Angles(0, quarterTurns * math.pi / 2, 0)
			local sockets = {}
			local openings = {}
			for localDir, offset in localSockets do
				local rotated = rotation:VectorToWorldSpace(offset)
				local d = classify(rotated)
				sockets[d] = rotated
				if localOpen[localDir] then
					openings[d] = true
				end
			end
			table.insert(variants, {
				Rotation = rotation,
				Key = openingKey(openings), -- open sides after rotation; what cells match on
				Open = openings,
				Sockets = sockets, -- every socket, used for alignment
			})
		end

		catalog[name] = { Prefab = prefab, Variants = variants }
	end

	return catalog
end

-- Layout ---------------------------------------------------------------------

-- Appends cells moving vertically within `col` from row `from` (exclusive) to `to`.
local function walk(path, col: number, from: number, to: number)
	if from == to then
		return
	end
	local step = if to > from then 1 else -1
	for r = from + step, to, step do
		table.insert(path, Vector2.new(col, r))
	end
end

-- A side lane leaving JUNCTION_A vertically, crossing columns 2-4 within `rows`, and
-- re-entering JUNCTION_B vertically. Monotone in X, so it never revisits a cell.
local function sideLane(rng: Random, rows): { Vector2 }
	local r2 = rows[rng:NextInteger(1, #rows)]
	local r3 = rows[rng:NextInteger(1, #rows)]
	local path = { JUNCTION_A }
	walk(path, JUNCTION_A.X, JUNCTION_A.Y, r2)
	table.insert(path, Vector2.new(3, r2))
	walk(path, 3, r2, r3)
	table.insert(path, Vector2.new(4, r3))
	walk(path, JUNCTION_B.X, r3, JUNCTION_B.Y)
	return path
end

local function generateLayout(rng: Random)
	local cells = {} -- [key] = { Pos, Openings = {}, Lane }

	local function cell(p: Vector2, lane: string)
		local k = cellKey(p)
		local c = cells[k]
		if not c then
			c = { Pos = p, Openings = {}, Lane = lane }
			cells[k] = c
		end
		return c
	end

	local lanes = {
		Center = { SPAWN_A, JUNCTION_A, COURTYARD, JUNCTION_B, SPAWN_B },
		Alpha = sideLane(rng, ALPHA_ROWS),
		Beta = sideLane(rng, BETA_ROWS),
	}

	for laneName, path in lanes do
		for i, p in path do
			assert(inBounds(p), `lane {laneName} left the grid at {p}`)
			cell(p, laneName)
			if i > 1 then
				local prev = path[i - 1]
				local d = dirBetween(prev, p)
				assert(d, `lane {laneName} is not contiguous at {p}`)
				cells[cellKey(prev)].Openings[d] = true
				cells[cellKey(p)].Openings[OPPOSITE[d]] = true
			end
		end
	end

	cells[cellKey(SPAWN_A)].Lane = "SpawnA"
	cells[cellKey(SPAWN_B)].Lane = "SpawnB"
	cells[cellKey(JUNCTION_A)].Lane = "Junction"
	cells[cellKey(JUNCTION_B)].Lane = "Junction"
	cells[cellKey(COURTYARD)].Lane = "Courtyard"

	return cells, lanes
end

-- Which prefabs may fill a cell, in preference order.
local function candidatesFor(c, rng: Random): { string }
	local key = openingKey(c.Openings)
	local count = #key

	if c.Lane == "SpawnA" then
		return { TILE_NAMES.SpawnA }
	elseif c.Lane == "SpawnB" then
		return { TILE_NAMES.SpawnB }
	elseif c.Lane == "Courtyard" then
		return { TILE_NAMES.Courtyard, TILE_NAMES.Straight }
	elseif count == 4 then
		return { TILE_NAMES.Intersection }
	elseif key == "NS" or key == "EW" then
		if rng:NextNumber() < SIDE_COURTYARD_CHANCE then
			return { TILE_NAMES.Courtyard, TILE_NAMES.Straight }
		end
		return { TILE_NAMES.Straight, TILE_NAMES.Courtyard }
	elseif count == 2 then
		return { TILE_NAMES.Corner }
	end
	return {}
end

-- Placement ------------------------------------------------------------------

-- Pivot CFrame that puts every socket of `variant` on the matching edge midpoint of
-- the cell, with all sockets at Y = 0. Pivots that are off-centre or at a different
-- height from tile to tile are corrected, so only the socket placement matters.
local function alignToSockets(variant, center: Vector3): CFrame
	local sum, n = Vector3.zero, 0
	for d, offset in variant.Sockets do
		local edge = center + WORLD_DIR[d] * (TileSize / 2)
		sum += edge - offset
		n += 1
	end
	return CFrame.new(sum / n) * variant.Rotation
end

local function placeTiles(cells, catalog, rng: Random, parent: Model)
	local placed = {} -- [key] = { Model, Sockets = { [dir] = worldPos }, Name }

	-- Fixed grid order so the same seed always consumes random numbers identically.
	local ordered = {}
	for y = 1, GridSize.Y do
		for x = 1, GridSize.X do
			local k = cellKey(Vector2.new(x, y))
			if cells[k] then
				table.insert(ordered, k)
			end
		end
	end

	for _, k in ordered do
		local c = cells[k]
		local key = openingKey(c.Openings)
		local chosen, chosenName = nil, nil
		local candidates = candidatesFor(c, rng)
		for _, name in candidates do
			local matches = {}
			for _, v in catalog[name].Variants do
				if v.Key == key then
					table.insert(matches, v)
				end
			end
			if #matches > 0 then
				chosen = matches[rng:NextInteger(1, #matches)]
				chosenName = name
				break
			end
		end

		if not chosen then
			-- Spell out what each candidate can provide so the fix is obvious from Output.
			local offers = {}
			for _, name in candidates do
				local keys, seen = {}, {}
				for _, v in catalog[name].Variants do
					local label = if v.Key == "" then "none" else v.Key
					if not seen[label] then
						seen[label] = true
						table.insert(keys, label)
					end
				end
				table.insert(offers, `{name} offers {table.concat(keys, "/")}`)
			end
			return nil,
				`no tile has exactly the openings "{key}" needed at {c.Pos} ({c.Lane}); {table.concat(offers, "; ")}`
		end
		if c.Lane == "Courtyard" and chosenName ~= TILE_NAMES.Courtyard then
			warn(`[ProceduralMapGenerator] {TILE_NAMES.Courtyard} can't provide openings "{key}"; using {chosenName} at the centre`)
		end

		local pivot = alignToSockets(chosen, cellCenter(c.Pos))
		local tile = catalog[chosenName].Prefab:Clone()
		tile.Name = `{chosenName}_{c.Pos.X}_{c.Pos.Y}`
		tile:PivotTo(pivot)
		for _, d in tile:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true -- unanchored tile geometry would fall into the void
			end
		end
		tile:SetAttribute("GridX", c.Pos.X)
		tile:SetAttribute("GridY", c.Pos.Y)
		tile:SetAttribute("Lane", c.Lane)
		tile.Parent = parent

		local worldSockets = {}
		for d, offset in chosen.Sockets do
			worldSockets[d] = pivot.Position + offset
		end
		placed[k] = { Model = tile, Sockets = worldSockets, Open = chosen.Open, Name = chosenName }
	end

	return placed
end

-- Validation -----------------------------------------------------------------

-- Two cells are connected only if both facing sides are open doorways and their
-- sockets meet at the same world point.
local function connected(placed, a: Vector2, d: string): boolean
	local b = a + GRID_STEP[d]
	local ta, tb = placed[cellKey(a)], placed[cellKey(b)]
	if not ta or not tb then
		return false
	end
	if not ta.Open[d] or not tb.Open[OPPOSITE[d]] then
		return false -- a wall on either side blocks the way
	end
	local sa, sb = ta.Sockets[d], tb.Sockets[OPPOSITE[d]]
	return sa ~= nil and sb ~= nil and (sa - sb).Magnitude <= SOCKET_TOLERANCE
end

local function bfs(placed, from: Vector2, to: Vector2): boolean
	local queue = { from }
	local visited = { [cellKey(from)] = true }
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		if current == to then
			return true
		end
		for _, d in DIR_ORDER do
			local nextPos = current + GRID_STEP[d]
			local k = cellKey(nextPos)
			if inBounds(nextPos) and not visited[k] and connected(placed, current, d) then
				visited[k] = true
				table.insert(queue, nextPos)
			end
		end
	end
	return false
end

local function validate(placed, lanes): (boolean, string?)
	if not bfs(placed, SPAWN_A, SPAWN_B) then
		return false, "BFS found no path from Spawn A to Spawn B"
	end
	for laneName, path in lanes do
		for i = 2, #path do
			local d = dirBetween(path[i - 1], path[i])
			if not connected(placed, path[i - 1], d) then
				return false, `{laneName} lane is broken between {path[i - 1]} and {path[i]} (sockets not flush)`
			end
		end
	end
	return true
end

-- Spawns ---------------------------------------------------------------------

-- Spawn tiles may not ship with a SpawnLocation; add one on the floor if missing.
local function ensureSpawnLocation(tile: Model, socketY: number)
	if tile:FindFirstChildWhichIsA("SpawnLocation", true) then
		return
	end
	local center = tile:GetPivot().Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { tile }
	local hit = workspace:Raycast(Vector3.new(center.X, socketY + 4, center.Z), Vector3.new(0, -20, 0), params)
	if not hit then
		warn(`[ProceduralMapGenerator] No floor under the centre of {tile.Name}; spawn pad placed at socket height`)
	end
	local floorY = if hit then hit.Position.Y else socketY

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "GeneratedSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = Vector3.new(center.X, floorY + 0.5, center.Z)
	spawn.Parent = tile
end

local function socketHeight(entry): number
	for _, pos in entry.Sockets do
		return pos.Y
	end
	return 0
end

-- Main -----------------------------------------------------------------------

local function generate(seed: number?)
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local folder = assets and assets:WaitForChild("MapTiles", 10)
	if not folder then
		error("[ProceduralMapGenerator] ReplicatedStorage.Assets.MapTiles not found")
	end

	local catalog = analyzePrefabs(folder)
	seed = seed or math.floor(tick())
	local rng = Random.new(seed)

	local map, lastError = nil, nil
	for attempt = 1, MAX_ATTEMPTS do
		local candidate = Instance.new("Model")
		candidate.Name = "GeneratedMap"

		local cells, lanes = generateLayout(rng)
		local placed, placeError = placeTiles(cells, catalog, rng, candidate)
		local ok, reason = false, placeError
		if placed then
			ok, reason = validate(placed, lanes)
		end

		if ok then
			map = { Model = candidate, Placed = placed }
			break
		end
		lastError = reason
		candidate:Destroy()
		warn(`[ProceduralMapGenerator] Attempt {attempt} rejected: {reason}`)
	end

	if not map then
		error(`[ProceduralMapGenerator] No valid layout after {MAX_ATTEMPTS} attempts (seed {seed}): {lastError}`)
	end

	local existing = workspace:FindFirstChild("GeneratedMap")
	if existing then
		existing:Destroy()
	end
	map.Model:SetAttribute("Seed", seed)
	map.Model.Parent = workspace
	print(`[ProceduralMapGenerator] Generated map with seed {seed}`)

	local spawnA = map.Placed[cellKey(SPAWN_A)]
	local spawnB = map.Placed[cellKey(SPAWN_B)]
	ensureSpawnLocation(spawnA.Model, socketHeight(spawnA))
	ensureSpawnLocation(spawnB.Model, socketHeight(spawnB))

	local courtyard = map.Placed[cellKey(COURTYARD)]
	WeaponService.PopulateDummies(courtyard.Model, COURTYARD_DUMMIES, socketHeight(courtyard) + 4)
end

-- If generation fails for any reason, load the static plaza so players never spawn
-- over the void, and make the failure impossible to miss in Output.
local function buildFallback(reason: string)
	warn(`[ProceduralMapGenerator] GENERATION FAILED, loading fallback plaza instead.\n{reason}`)
	local existing = workspace:FindFirstChild("GeneratedMap")
	if existing then
		existing:Destroy()
	end
	local map = MapBuilder.build()
	for _, position in { Vector3.new(-12, 0, 50), Vector3.new(0, 0, 55), Vector3.new(12, 0, 50), Vector3.new(-24, 0, 40) } do
		TargetDummy.spawn(map, position)
	end
end

local ok, err = pcall(generate, workspace:GetAttribute("MapSeed"))
if not ok then
	buildFallback(tostring(err))
end

if not workspace:FindFirstChildWhichIsA("SpawnLocation", true) then
	warn("[ProceduralMapGenerator] No SpawnLocation exists after map load; players will spawn at the origin")
end

-- Map is in place: spawn everyone (including anyone who loaded early) and resume
-- normal auto-loading for joins and respawns.
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	player:LoadCharacter()
end
