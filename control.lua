local DEFAULT_WIDTH = 13
local DEFAULT_LENGTH = 31
local DEFAULT_SPHERE_RADIUS = 10
local MIN_WIDTH, MAX_WIDTH = 7, 31
local MIN_LENGTH, MAX_LENGTH = 15, 81
local MIN_SPHERE_RADIUS, MAX_SPHERE_RADIUS = 4, 30

local function find_prototype(collection, exact_names, pattern)
  for _, name in ipairs(exact_names) do
    if collection[name] then return name end
  end
  local matches = {}
  for name, _ in pairs(collection) do
    if string.find(name, pattern, 1, true) then
      matches[#matches + 1] = name
    end
  end
  table.sort(matches)
  return matches[1], matches
end

local function find_parts()
  local tile_name, tile_matches = find_prototype(prototypes.tile,
    {"se-spaceship-floor", "se-spaceship-floor-1"}, "spaceship-floor")
  local console_name, console_matches = find_prototype(prototypes.entity,
    {"se-spaceship-console"}, "spaceship-console")
  local wall_name, wall_matches = find_prototype(prototypes.entity,
    {"se-spaceship-wall"}, "spaceship-wall")
  return tile_name, console_name, wall_name, tile_matches, console_matches, wall_matches
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function tile_key(x, y)
  return x .. ":" .. y
end

local function build_pointed_plan(width, length, origin_x, origin_y, tile_name)
  local half_width = math.floor(width / 2)
  local half_length = math.floor(length / 2)
  local bow_tip_y = origin_y - half_length
  local stern_y = origin_y + half_length
  local tiles, boundary, boundary_seen = {}, {}, {}

  local function add_boundary(x, y)
    local key = tile_key(x, y)
    if not boundary_seen[key] then
      boundary_seen[key] = true
      boundary[#boundary + 1] = {x = x, y = y}
    end
  end

  for col = -half_width, half_width do
    local x = origin_x + col
    local front_y = bow_tip_y + math.abs(col)
    for y = front_y, stern_y do
      tiles[#tiles + 1] = {name = tile_name, position = {x = x, y = y}}
      if col == -half_width or col == half_width or y == front_y or y == stern_y then
        add_boundary(x, y)
      end
      -- The pointed front advances diagonally one tile per column. Add the
      -- inboard tile behind each bow tile so adjacent wall entities touch
      -- orthogonally instead of only at their corners.
      if y == front_y then
        add_boundary(x, y + 1)
      end
    end
  end
  return tiles, boundary
end

-- A filled, integer-grid disk. Boundary walls are placed on every floor tile
-- with at least one cardinal neighbour outside the disk.
local function build_sphere_plan(radius, origin_x, origin_y, tile_name)
  local tiles, boundary = {}, {}
  local inside = {}
  local radius_squared = radius * radius

  for dx = -radius, radius do
    inside[dx] = {}
    for dy = -radius, radius do
      if dx * dx + dy * dy <= radius_squared then
        inside[dx][dy] = true
        tiles[#tiles + 1] = {
          name = tile_name,
          position = {x = origin_x + dx, y = origin_y + dy}
        }
      end
    end
  end

  -- Start with the actual one-tile digital-circle edge: floor cells with
  -- at least one cardinal neighbour outside the filled disk.
  local base_boundary = {}
  local base_seen = {}
  local function key(dx, dy) return tile_key(dx, dy) end
  local function add_base(dx, dy)
    local k = key(dx, dy)
    if not base_seen[k] then
      base_seen[k] = true
      local pos = {x = dx, y = dy}
      base_boundary[#base_boundary + 1] = pos
      boundary[#boundary + 1] = {x = origin_x + dx, y = origin_y + dy}
    end
  end

  local cardinal = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
  for dx = -radius, radius do
    for dy = -radius, radius do
      if inside[dx] and inside[dx][dy] then
        local edge = false
        for _, d in ipairs(cardinal) do
          local nx, ny = dx + d[1], dy + d[2]
          if not (inside[nx] and inside[nx][ny]) then
            edge = true
            break
          end
        end
        if edge then add_base(dx, dy) end
      end
    end
  end

  -- SE discovers bulkheads with 4-way connectivity, but its containment pass
  -- expands exterior floor in 8 directions. The raw digital-circle edge has
  -- diagonal-only joins. For each diagonal pair of BASE edge cells, add only
  -- one of the two orthogonal bridge cells, choosing the one closest to the
  -- outer radius. Do not recursively bridge newly added cells: that would
  -- progressively fill the interior and make a thick band.
  local diagonal = {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
  local connector_seen = {}
  for _, pos in ipairs(base_boundary) do
    local dx, dy = pos.x, pos.y
    for _, d in ipairs(diagonal) do
      local nx, ny = dx + d[1], dy + d[2]
      if base_seen[key(nx, ny)] then
        local x1, y1 = dx + d[1], dy
        local x2, y2 = dx, dy + d[2]
        local in1 = inside[x1] and inside[x1][y1]
        local in2 = inside[x2] and inside[x2][y2]
        local cx, cy
        if in1 and in2 then
          local r1, r2 = x1 * x1 + y1 * y1, x2 * x2 + y2 * y2
          if r1 > r2 or (r1 == r2 and (x1 < x2 or (x1 == x2 and y1 < y2))) then
            cx, cy = x1, y1
          else
            cx, cy = x2, y2
          end
        elseif in1 then
          cx, cy = x1, y1
        elseif in2 then
          cx, cy = x2, y2
        end
        if cx then
          local k = key(cx, cy)
          if not base_seen[k] and not connector_seen[k] then
            connector_seen[k] = true
            boundary[#boundary + 1] = {x = origin_x + cx, y = origin_y + cy}
          end
        end
      end
    end
  end
  return tiles, boundary
end

-- Mirrors the relevant calculations in the supplied
-- SpaceshipIntegrity.stop_integrity_check() and calculate_integrity_stress().
-- Assumes every generated tile is connected, perimeter walls are recognised as
-- bulkheads, and no extra containers/generators/equipment are installed.
local function walls_are_four_connected(boundary)
  if #boundary == 0 then return false end
  local wall_set = {}
  for _, pos in ipairs(boundary) do
    wall_set[tile_key(pos.x, pos.y)] = true
  end
  local first = boundary[1]
  local queue = {{x = first.x, y = first.y}}
  local visited = {[tile_key(first.x, first.y)] = true}
  local head = 1
  local directions = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
  while head <= #queue do
    local current = queue[head]
    head = head + 1
    for _, delta in ipairs(directions) do
      local nx, ny = current.x + delta[1], current.y + delta[2]
      local key = tile_key(nx, ny)
      if wall_set[key] and not visited[key] then
        visited[key] = true
        queue[#queue + 1] = {x = nx, y = ny}
      end
    end
  end
  for key, _ in pairs(wall_set) do
    if not visited[key] then return false end
  end
  return true
end

-- Simulate the exterior side of SE's containment pass. That pass spreads to
-- floor tiles in all 8 directions, so no non-wall floor tile may be reachable
-- from outside while treating bulkhead tiles as blockers.
local function walls_seal_eight_way(tiles, boundary)
  local floor_set, wall_set = {}, {}
  local min_x, max_x, min_y, max_y
  for _, tile in ipairs(tiles) do
    local x, y = tile.position.x, tile.position.y
    floor_set[tile_key(x, y)] = true
    min_x = min_x and math.min(min_x, x) or x
    max_x = max_x and math.max(max_x, x) or x
    min_y = min_y and math.min(min_y, y) or y
    max_y = max_y and math.max(max_y, y) or y
  end
  for _, pos in ipairs(boundary) do
    local key = tile_key(pos.x, pos.y)
    if not floor_set[key] then return false end
    wall_set[key] = true
  end
  if not min_x then return false end

  local queue, visited = {}, {}
  -- CRITICAL: keep the flood fill inside the finite expanded hull bounds.
  -- Without these limits, every exterior tile is enqueued forever and the
  -- Factorio main thread hangs while the command runs.
  local flood_min_x, flood_max_x = min_x - 1, max_x + 1
  local flood_min_y, flood_max_y = min_y - 1, max_y + 1
  local function enqueue(x, y)
    if x < flood_min_x or x > flood_max_x
      or y < flood_min_y or y > flood_max_y then
      return
    end
    local key = tile_key(x, y)
    if not wall_set[key] and not visited[key] then
      visited[key] = true
      queue[#queue + 1] = {x = x, y = y}
    end
  end

  -- Seed the exterior on all four sides of a one-tile expanded bounding box.
  for x = min_x - 1, max_x + 1 do
    enqueue(x, min_y - 1)
    enqueue(x, max_y + 1)
  end
  for y = min_y - 1, max_y + 1 do
    enqueue(min_x - 1, y)
    enqueue(max_x + 1, y)
  end

  local head = 1
  while head <= #queue do
    local current = queue[head]
    head = head + 1
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local nx, ny = current.x + dx, current.y + dy
          local key = tile_key(nx, ny)
          if floor_set[key] and not wall_set[key] then
            return false -- exterior flood has leaked into the ship interior
          end
          enqueue(nx, ny)
        end
      end
    end
  end
  return true
end

local function validate_plan(tiles, boundary)
  local widths, front_by_x = {}, {}
  local min_x, max_x, min_y, max_y
  for _, tile in ipairs(tiles) do
    local x, y = tile.position.x, tile.position.y
    widths[y] = (widths[y] or 0) + 1
    if not front_by_x[x] or y < front_by_x[x] then front_by_x[x] = y end
    min_x = min_x and math.min(min_x, x) or x
    max_x = max_x and math.max(max_x, x) or x
    min_y = min_y and math.min(min_y, y) or y
    max_y = max_y and math.max(max_y, y) or y
  end

  local width = max_x - min_x + 1
  local height = max_y - min_y + 1
  local average_x = math.floor((min_x + max_x + 1) / 2)
  local front_by_y, left_by_y, right_by_y = {}, {}, {}
  local max_flat = 0
  for x, y in pairs(front_by_x) do
    front_by_y[y] = (front_by_y[y] or 0) + 1
    max_flat = math.max(max_flat, front_by_y[y])
    if x < average_x then
      left_by_y[y] = true
    else
      right_by_y[y] = true
    end
  end

  local function key_count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
  end

  local flatness = math.min(1, (1 - (max_flat - 2) / (width - 2)) * 1.5)
  local denominator = math.max(0.5, (width - 1) / 2.5)
  local left = math.min(1, 2 * (key_count(left_by_y) - 1) / denominator)
  local right = math.min(1, 2 * (key_count(right_by_y) - 1) / denominator)
  local streamline = (flatness + left + right + 3 * math.min(flatness, math.min(left, right))) / 6

  -- Reproduce the alternating front/back weak-section scan.
  local front_y, back_y = min_y, max_y
  local front_max_width, back_max_width = 0, 0
  local phantom_tiles = 0
  while front_y <= back_y do
    if front_max_width <= back_max_width then
      local row_width = widths[front_y]
      if row_width then
        if front_max_width < row_width then
          front_max_width = math.min(row_width, front_max_width + 2)
        end
        if row_width < front_max_width / 2 then
          local hollow = front_max_width / 2 - row_width
          phantom_tiles = phantom_tiles + hollow * hollow / (front_max_width / 2)
        end
      end
      front_y = front_y + 1
    else
      local row_width = widths[back_y]
      if row_width then
        if back_max_width < row_width then
          back_max_width = math.min(row_width, back_max_width + 2)
        end
        if row_width < back_max_width / 2 then
          local hollow = back_max_width / 2 - row_width
          phantom_tiles = phantom_tiles + hollow * hollow / (front_max_width / 2)
        end
      end
      back_y = back_y - 1
    end
  end

  local tile_count = #tiles
  local wall_count = #boundary
  local average_row_width = tile_count / height
  local length_ratio = height / average_row_width
  local long_multiplier = math.max(1, 1 + 0.05 * (length_ratio - 4))
  local structural_stress = (tile_count + phantom_tiles * 0.25 - wall_count * 0.75) * long_multiplier

  return {
    streamline = streamline,
    structural_stress = structural_stress,
    tile_count = tile_count,
    wall_count = wall_count,
    phantom_tiles = phantom_tiles,
    max_flat = max_flat,
    width = width,
    height = height,
    walls_four_connected = walls_are_four_connected(boundary),
    walls_seal_eight_way = walls_seal_eight_way(tiles, boundary)
  }
end

local function generate_ship(player, shape, size_a, size_b)
  local surface = player.surface
  local tile_name, console_name, wall_name, tile_matches, console_matches, wall_matches = find_parts()
  if not tile_name or not console_name or not wall_name then
    player.print("[SE Auto Ship] Could not identify all Space Exploration prototypes.")
    player.print("Floor tile: " .. tostring(tile_name))
    player.print("Console: " .. tostring(console_name))
    player.print("Wall: " .. tostring(wall_name))
    if tile_matches then player.print("Floor candidates: " .. table.concat(tile_matches, ", ")) end
    if console_matches then player.print("Console candidates: " .. table.concat(console_matches, ", ")) end
    if wall_matches then player.print("Wall candidates: " .. table.concat(wall_matches, ", ")) end
    return
  end

  local origin_x = math.floor(player.position.x)
  local origin_y = math.floor(player.position.y)
  local tiles, boundary, radius
  if shape == "sphere" then
    radius = clamp(math.floor(size_a or DEFAULT_SPHERE_RADIUS), MIN_SPHERE_RADIUS, MAX_SPHERE_RADIUS)
    tiles, boundary = build_sphere_plan(radius, origin_x, origin_y, tile_name)
  else
    local width = clamp(math.floor(size_a or DEFAULT_WIDTH), MIN_WIDTH, MAX_WIDTH)
    local length = clamp(math.floor(size_b or DEFAULT_LENGTH), MIN_LENGTH, MAX_LENGTH)
    if width % 2 == 0 then width = width - 1 end
    if length % 2 == 0 then length = length - 1 end
    tiles, boundary = build_pointed_plan(width, length, origin_x, origin_y, tile_name)
  end

  local validation = validate_plan(tiles, boundary)
  if not validation.walls_four_connected then
    player.print("[SE Auto Ship] Refusing to build: perimeter walls are not connected vertically/horizontally.")
    return
  end
  if shape == "sphere" and not validation.walls_seal_eight_way then
    player.print("[SE Auto Ship] Refusing to build: sphere perimeter leaves an 8-way containment leak.")
    return
  end
  local pad = 2
  local area = {
    {origin_x - math.floor(validation.width / 2) - pad, origin_y - math.floor(validation.height / 2) - pad},
    {origin_x + math.floor(validation.width / 2) + pad, origin_y + math.floor(validation.height / 2) + pad}
  }
  for _, entity in pairs(surface.find_entities_filtered{area = area}) do
    if entity.valid and entity.type ~= "character" then
      player.print("[SE Auto Ship] Aborted: an entity is inside the proposed ship area.")
      return
    end
  end

  surface.set_tiles(tiles, true, false, false, false)
  local walls_placed = 0
  for _, pos in ipairs(boundary) do
    local wall = surface.create_entity{
      name = wall_name,
      position = {pos.x + 0.5, pos.y + 0.5},
      force = player.force,
      raise_built = true
    }
    if wall then walls_placed = walls_placed + 1 end
  end

  if walls_placed ~= #boundary then
    player.print("[SE Auto Ship] Warning: only " .. walls_placed .. " of " .. #boundary .. " perimeter walls were placed.")
    player.print("The ship may fail integrity; repair missing walls before running the check.")
  end

  local console = surface.create_entity{
    name = console_name,
    position = {origin_x + 0.5, origin_y + 0.5},
    force = player.force,
    raise_built = true
  }
  if not console then
    player.print("[SE Auto Ship] Hull and walls placed, but console placement failed.")
    return
  end

  if shape == "sphere" then
    player.print("[SE Auto Ship] Generated sphere hull, radius " .. radius .. " (diameter " .. (radius * 2 + 1) .. ").")
  else
    player.print("[SE Auto Ship] Generated pointed-bow hull, " .. validation.width .. " x " .. validation.height .. ".")
  end
  player.print(string.format("Validation: streamline %.2f%% | estimated structural stress %.1f", validation.streamline * 100, validation.structural_stress))
  player.print("Hull: " .. validation.tile_count .. " floor tiles, " .. walls_placed .. " perimeter walls, " .. string.format("%.2f", validation.phantom_tiles) .. " phantom tiles.")
  if shape == "sphere" then
    player.print("Sphere perimeter: one-tile-thick, 4-way connected and sealed against the 8-way containment flood.")
  end
  if validation.streamline < 0.9999 then
    player.print("[SE Auto Ship] Note: this size's rasterized outline does not score 100% streamline.")
  end
  player.print("Stress estimate excludes containers, fluids, equipment, and generators. Run the console integrity check for the in-game result.")
  player.print("Hull only: add propulsion and other required ship systems separately.")
end

commands.add_command("se-generate-ship",
  "Generate an SE ship hull. Usage: /se-generate-ship [pointed [width] [length] | sphere [radius]]",
  function(command)
    local player = game.get_player(command.player_index)
    if not player then return end
    local args = {}
    for token in string.gmatch(command.parameter or "", "%S+") do
      args[#args + 1] = token
    end
    local shape = "pointed"
    local size_a, size_b
    if args[1] == "sphere" then
      shape = "sphere"
      size_a = tonumber(args[2]) or DEFAULT_SPHERE_RADIUS
    elseif args[1] == "pointed" then
      size_a = tonumber(args[2]) or DEFAULT_WIDTH
      size_b = tonumber(args[3]) or DEFAULT_LENGTH
    else
      -- Keep the previous command format working: /se-generate-ship [width] [length]
      size_a = tonumber(args[1]) or DEFAULT_WIDTH
      size_b = tonumber(args[2]) or DEFAULT_LENGTH
    end
    generate_ship(player, shape, size_a, size_b)
  end
)
