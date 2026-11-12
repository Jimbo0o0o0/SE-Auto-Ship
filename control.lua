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

-- Filled isosceles triangle: a single-tile apex at the bow, widening
-- evenly toward a flat stern. Width and length are odd tile dimensions.
-- The side walls use one inboard connector tile whenever a sloped edge
-- advances diagonally, keeping the perimeter 4-connected without thickening
-- the entire side.
local function build_triangle_plan(width, length, origin_x, origin_y, tile_name)
  local half_width = math.floor(width / 2)
  local half_length = math.floor(length / 2)
  local tiles, boundary, boundary_seen = {}, {}, {}
  local function add_boundary(x, y)
    local key = tile_key(x, y)
    if not boundary_seen[key] then
      boundary_seen[key] = true
      boundary[#boundary + 1] = {x = x, y = y}
    end
  end

  local previous_left, previous_right
  local steps = half_length * 2
  for row = 0, steps do
    local y = origin_y - half_length + row
    local half_span = math.floor((row * half_width) / steps)
    local left_x = origin_x - half_span
    local right_x = origin_x + half_span

    for x = left_x, right_x do
      tiles[#tiles + 1] = {
        name = tile_name,
        position = {x = x, y = y}
      }
    end

    add_boundary(left_x, y)
    add_boundary(right_x, y)
    if row == steps then
      -- Flat stern closes the wide end of the triangle.
      for x = left_x, right_x do
        add_boundary(x, y)
      end
    end

    if previous_left then
      if left_x == previous_left - 1 then
        -- Bridge the diagonal left-edge step with the closest inboard tile.
        add_boundary(previous_left, y)
      elseif left_x < previous_left - 1 then
        -- The requested slope is too steep to maintain a one-tile wall.
        return tiles, boundary, false
      end
      if right_x == previous_right + 1 then
        add_boundary(previous_right, y)
      elseif right_x > previous_right + 1 then
        return tiles, boundary, false
      end
    end

    previous_left, previous_right = left_x, right_x
  end

  return tiles, boundary, true
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

-- Shape-independent preflight model based on SE's
-- SpaceshipIntegrity.stop_integrity_check() and
-- SpaceshipIntegrity.calculate_integrity_stress().
--
-- This is a hull-only mirror: SE keeps these functions local, so another mod
-- cannot safely call them directly. Cargo, equipment, fluids, generators and
-- other integrity-affecting entities are deliberately excluded from this
-- estimate. The real SE console check remains authoritative after construction.
local function validate_plan(tiles, boundary, console_x, console_y)
  local floor_set, wall_set = {}, {}
  local widths, front_by_x = {}, {}
  local min_x, max_x, min_y, max_y

  for _, tile in ipairs(tiles) do
    local x, y = tile.position.x, tile.position.y
    local key = tile_key(x, y)
    if floor_set[key] then
      return {valid = false, reason = "duplicate-floor-position"}
    end
    floor_set[key] = true
    widths[y] = (widths[y] or 0) + 1
    if not front_by_x[x] or y < front_by_x[x] then front_by_x[x] = y end
    min_x = min_x and math.min(min_x, x) or x
    max_x = max_x and math.max(max_x, x) or x
    min_y = min_y and math.min(min_y, y) or y
    max_y = max_y and math.max(max_y, y) or y
  end

  if not min_x then
    return {valid = false, reason = "empty-plan"}
  end

  local wall_count = 0
  for _, pos in ipairs(boundary) do
    local key = tile_key(pos.x, pos.y)
    -- SE recognizes a bulkhead only when the wall entity occupies a
    -- spaceship-floor tile. Reject out-of-footprint walls.
    if not floor_set[key] then
      return {valid = false, reason = "wall-outside-floor"}
    end
    if wall_set[key] then
      return {valid = false, reason = "duplicate-wall-position"}
    end
    wall_set[key] = true
    wall_count = wall_count + 1
  end

  local console_key = tile_key(console_x, console_y)
  if not floor_set[console_key] then
    return {valid = false, reason = "console-not-on-floor"}
  end
  if wall_set[console_key] then
    return {valid = false, reason = "console-on-bulkhead"}
  end

  local cardinal = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
  local diagonal = {
    {-1, -1}, {-1, 0}, {-1, 1},
    {0, -1},           {0, 1},
    {1, -1},  {1, 0},  {1, 1}
  }

  -- SE floor-connectivity: every floor tile must be discoverable from the
  -- console by north/south/east/west movement.
  local floor_queue = {{x = console_x, y = console_y}}
  local floor_seen = {[console_key] = true}
  local floor_head = 1
  while floor_head <= #floor_queue do
    local current = floor_queue[floor_head]
    floor_head = floor_head + 1
    for _, d in ipairs(cardinal) do
      local nx, ny = current.x + d[1], current.y + d[2]
      local key = tile_key(nx, ny)
      if floor_set[key] and not floor_seen[key] then
        floor_seen[key] = true
        floor_queue[#floor_queue + 1] = {x = nx, y = ny}
      end
    end
  end
  local connected_floor_count = 0
  for _ in pairs(floor_seen) do connected_floor_count = connected_floor_count + 1 end
  if connected_floor_count ~= #tiles then
    return {valid = false, reason = "floor-not-four-connected"}
  end

  -- Additional generator requirement: the wall entities themselves must
  -- form one orthogonally connected component.
  if wall_count == 0 then
    return {valid = false, reason = "no-walls"}
  end
  local first_wall
  for _, pos in ipairs(boundary) do
    first_wall = pos
    break
  end
  local wall_queue = {{x = first_wall.x, y = first_wall.y}}
  local wall_seen = {[tile_key(first_wall.x, first_wall.y)] = true}
  local wall_head = 1
  while wall_head <= #wall_queue do
    local current = wall_queue[wall_head]
    wall_head = wall_head + 1
    for _, d in ipairs(cardinal) do
      local nx, ny = current.x + d[1], current.y + d[2]
      local key = tile_key(nx, ny)
      if wall_set[key] and not wall_seen[key] then
        wall_seen[key] = true
        wall_queue[#wall_queue + 1] = {x = nx, y = ny}
      end
    end
  end
  local connected_wall_count = 0
  for _ in pairs(wall_seen) do connected_wall_count = connected_wall_count + 1 end
  if connected_wall_count ~= wall_count then
    return {valid = false, reason = "walls-not-four-connected"}
  end

  -- SE containment: exterior cells are discovered next to the connected
  -- floor component, then spread in 8 directions. They may not reach any
  -- un-bulkheaded floor tile. Keep the simulation bounded to the hull bounds.
  local flood_min_x, flood_max_x = min_x - 1, max_x + 1
  local flood_min_y, flood_max_y = min_y - 1, max_y + 1
  local exterior_queue, exterior_seen = {}, {}
  local function enqueue_exterior(x, y)
    if x < flood_min_x or x > flood_max_x
      or y < flood_min_y or y > flood_max_y then
      return
    end
    local key = tile_key(x, y)
    if wall_set[key] or exterior_seen[key] then return end
    if floor_set[key] then
      -- SE would classify this as floor_exterior. The generator rejects any
      -- such leak, rather than allowing an unstable disconnected section.
      return false
    end
    exterior_seen[key] = true
    exterior_queue[#exterior_queue + 1] = {x = x, y = y}
    return true
  end

  -- SE's floor-connectivity pass seeds every cardinal neighbour that is not
  -- a floor tile as exterior (including concave pockets).
  for _, tile in ipairs(tiles) do
    local x, y = tile.position.x, tile.position.y
    for _, d in ipairs(cardinal) do
      local nx, ny = x + d[1], y + d[2]
      if not floor_set[tile_key(nx, ny)] then
        if enqueue_exterior(nx, ny) == false then
          return {valid = false, reason = "containment-leak"}
        end
      end
    end
  end

  local exterior_head = 1
  while exterior_head <= #exterior_queue do
    local current = exterior_queue[exterior_head]
    exterior_head = exterior_head + 1
    for _, d in ipairs(diagonal) do
      local nx, ny = current.x + d[1], current.y + d[2]
      local key = tile_key(nx, ny)
      if floor_set[key] and not wall_set[key] then
        return {valid = false, reason = "containment-leak"}
      end
      enqueue_exterior(nx, ny)
    end
  end

  -- Exact streamline geometry from stop_integrity_check(): one foremost
  -- (minimum-y) tile per x-column, split around the SE average-x midpoint.
  local max_x_exclusive = max_x + 1
  local width = max_x_exclusive - min_x
  local average_x = math.floor((min_x + max_x_exclusive) / 2)
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
  local streamline_flatness = math.min(1, (1 - (max_flat - 2) / (width - 2)) * 1.5)
  local streamline_denominator = math.max(0.5, (width - 1) / 2.5)
  local streamline_left = math.min(1, 2 * (key_count(left_by_y) - 1) / streamline_denominator)
  local streamline_right = math.min(1, 2 * (key_count(right_by_y) - 1) / streamline_denominator)
  local streamline = (streamline_flatness + streamline_left + streamline_right
    + 3 * math.min(streamline_flatness, math.min(streamline_left, streamline_right))) / 6

  -- Exact phantom-tile scan from calculate_integrity_stress(). Note that SE
  -- starts the back scan at the exclusive bottom bound (max_y + 1), and the
  -- back-side denominator below intentionally matches the SE implementation.
  local front_y, back_y = min_y, max_y + 1
  local front_max_width, back_max_width = 0, 0
  local phantom_tiles, thin_section_count = 0, 0
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
          thin_section_count = thin_section_count + 1
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
          thin_section_count = thin_section_count + 1
        end
      end
      back_y = back_y - 1
    end
  end

  local tile_count = #tiles
  local total_row_width = 0
  local row_count = 0
  for _, row_width in pairs(widths) do
    total_row_width = total_row_width + row_width
    row_count = row_count + 1
  end
  local average_row_width = total_row_width / math.max(1, row_count)
  local hull_length = max_y + 1 - min_y

  -- Hull-only version of SE structural stress:
  -- tiles + phantom tile cost - wall credit, followed by long-ship multiplier.
  local structural_stress = tile_count
    + phantom_tiles * 0.25
    - wall_count * 0.75
  local long_multiplier = 1 + 0.05 * (hull_length / average_row_width - 4)
  if long_multiplier > 1 then
    structural_stress = structural_stress * long_multiplier
  else
    long_multiplier = 1
  end

  -- SE's corridor allowance discounts up to 10% of floor tile count for
  -- clear connected tiles. For a hull-only ghost plan, assume wall tiles and
  -- the console tile are occupied; any later entities may reduce this value.
  local estimated_empty_tiles = math.max(0, tile_count - wall_count - 1)
  local effective_empty_tiles = math.min(tile_count * 0.1, estimated_empty_tiles)
  structural_stress = structural_stress - effective_empty_tiles

  return {
    valid = true,
    streamline = streamline,
    structural_stress = structural_stress,
    container_stress = 0,
    total_stress = structural_stress,
    tile_count = tile_count,
    wall_count = wall_count,
    phantom_tiles = phantom_tiles,
    thin_section_count = thin_section_count,
    estimated_empty_tiles = estimated_empty_tiles,
    effective_empty_tiles = effective_empty_tiles,
    long_multiplier = long_multiplier,
    width = width,
    height = hull_length,
    floor_four_connected = true,
    walls_four_connected = true,
    walls_seal_eight_way = true
  }
end

-- Build a real blueprint item in the player's inventory. Blueprint tile
-- coordinates are tile origins; entity coordinates are tile centers. Both
-- are translated to a zero-based local coordinate system.
local function create_hull_blueprint(player, tiles, boundary, tile_name, wall_name, console_name, origin_x, origin_y, shape)
  local inventory = player.get_main_inventory()
  if not inventory then
    player.print("[SE Auto Ship] Cannot create blueprint: player inventory is unavailable.")
    return false
  end

  local slot
  for i = 1, #inventory do
    local candidate = inventory[i]
    if candidate and not candidate.valid_for_read then
      slot = candidate
      break
    end
  end
  if not slot then
    player.print("[SE Auto Ship] Cannot create blueprint: your main inventory has no empty slot.")
    return false
  end

  local min_x, min_y = math.huge, math.huge
  for _, tile in ipairs(tiles) do
    min_x = math.min(min_x, tile.position.x)
    min_y = math.min(min_y, tile.position.y)
  end

  local blueprint_tiles = {}
  for _, tile in ipairs(tiles) do
    blueprint_tiles[#blueprint_tiles + 1] = {
      name = tile_name,
      position = {x = tile.position.x - min_x, y = tile.position.y - min_y}
    }
  end

  local blueprint_entities = {}
  local entity_number = 1
  for _, pos in ipairs(boundary) do
    blueprint_entities[#blueprint_entities + 1] = {
      entity_number = entity_number,
      name = wall_name,
      position = {x = pos.x - min_x + 0.5, y = pos.y - min_y + 0.5},
      direction = defines.direction.north
    }
    entity_number = entity_number + 1
  end
  blueprint_entities[#blueprint_entities + 1] = {
    entity_number = entity_number,
    name = console_name,
    position = {x = origin_x - min_x + 0.5, y = origin_y - min_y + 0.5},
    direction = defines.direction.north
  }

  slot.set_stack({name = "blueprint"})
  if not slot.valid_for_read or slot.name ~= "blueprint" then
    player.print("[SE Auto Ship] Cannot create blueprint: failed to create blueprint item.")
    return false
  end

  local ok, err = pcall(function()
    slot.set_blueprint_entities(blueprint_entities)
    slot.set_blueprint_tiles(blueprint_tiles)
    slot.label = "SE Auto Ship - " .. shape
  end)
  if not ok then
    slot.clear()
    player.print("[SE Auto Ship] Blueprint setup failed: " .. tostring(err))
    return false
  end

  player.print("[SE Auto Ship] Blueprint created in your main inventory: " .. #blueprint_tiles
    .. " floor tiles, " .. (#boundary + 1) .. " entities.")
  return true
end

local function generate_ship(player, shape, size_a, size_b, output_mode)
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
  local width, length
  if shape == "sphere" then
    radius = clamp(math.floor(size_a or DEFAULT_SPHERE_RADIUS), MIN_SPHERE_RADIUS, MAX_SPHERE_RADIUS)
    tiles, boundary = build_sphere_plan(radius, origin_x, origin_y, tile_name)
  else
    width = clamp(math.floor(size_a or DEFAULT_WIDTH), MIN_WIDTH, MAX_WIDTH)
    length = clamp(math.floor(size_b or DEFAULT_LENGTH), MIN_LENGTH, MAX_LENGTH)
    if width % 2 == 0 then width = width - 1 end
    if length % 2 == 0 then length = length - 1 end
    if shape == "triangle" then
      -- Limit side slope to at most one horizontal tile per vertical step,
      -- otherwise a thin orthogonally connected perimeter is impossible.
      if length < width then length = width end
      local build_ok
      tiles, boundary, build_ok = build_triangle_plan(width, length, origin_x, origin_y, tile_name)
      if not build_ok then
        player.print("[SE Auto Ship] Refusing triangle: its side slope cannot form a one-tile connected wall.")
        return
      end
    else
      tiles, boundary = build_pointed_plan(width, length, origin_x, origin_y, tile_name)
    end
  end

  local validation = validate_plan(tiles, boundary, origin_x, origin_y)
  if not validation.valid then
    local reasons = {
      ["empty-plan"] = "the shape contains no floor tiles",
      ["duplicate-floor-position"] = "the shape generator emitted the same floor tile more than once",
      ["duplicate-wall-position"] = "the shape generator emitted the same wall position more than once",
      ["wall-outside-floor"] = "a wall is not placed on a spaceship floor tile",
      ["console-not-on-floor"] = "the console is not on a floor tile",
      ["console-on-bulkhead"] = "the console overlaps a bulkhead",
      ["floor-not-four-connected"] = "not all floor tiles connect to the console orthogonally",
      ["no-walls"] = "the hull has no bulkhead walls",
      ["walls-not-four-connected"] = "bulkhead walls are not one orthogonally connected component",
      ["containment-leak"] = "SE's 8-way exterior flood reaches an un-walled floor tile"
    }
    player.print("[SE Auto Ship] Refusing to place ghosts: " .. (reasons[validation.reason] or validation.reason))
    return
  end
  if output_mode == "blueprint" then
    if not create_hull_blueprint(player, tiles, boundary, tile_name, wall_name, console_name,
      origin_x, origin_y, shape) then
      return
    end
    local output_count = #boundary + 1
    if shape == "sphere" then
      player.print("[SE Auto Ship] Blueprint shape: sphere, radius " .. radius .. ".")
    elseif shape == "triangle" then
      player.print("[SE Auto Ship] Blueprint shape: triangle, " .. width .. " x " .. length .. ".")
    else
      player.print("[SE Auto Ship] Blueprint shape: pointed, " .. width .. " x " .. length .. ".")
    end
    player.print(string.format("SE-matched hull estimate: streamline %.2f%% | structural stress %.1f | container stress %.1f",
      validation.streamline * 100, validation.structural_stress, validation.container_stress))
    player.print("Estimate only; the actual SE console integrity check happens after the blueprint is built.")
    player.print("The blueprint is in your main inventory. No ghosts or world entities were placed.")
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

  -- Create ghosts for every floor tile, wall and console. Nothing is built
  -- immediately; construction robots can fulfil the ghosts later.
  local tiles_ghosted = 0
  for _, tile in ipairs(tiles) do
    local p = tile.position
    local ghost = surface.create_entity{
      name = "tile-ghost",
      inner_name = tile.name,
      position = {p.x + 0.5, p.y + 0.5},
      force = player.force
    }
    if ghost then tiles_ghosted = tiles_ghosted + 1 end
  end

  local walls_ghosted = 0
  for _, pos in ipairs(boundary) do
    local ghost = surface.create_entity{
      name = "entity-ghost",
      inner_name = wall_name,
      position = {pos.x + 0.5, pos.y + 0.5},
      force = player.force,
      expires = false
    }
    if ghost then walls_ghosted = walls_ghosted + 1 end
  end

  local console_ghost = surface.create_entity{
    name = "entity-ghost",
    inner_name = console_name,
    position = {origin_x + 0.5, origin_y + 0.5},
    force = player.force,
    expires = false
  }
  if not console_ghost then
    player.print("[SE Auto Ship] Floor and wall ghosts created, but console ghost placement failed.")
  end

  if tiles_ghosted ~= #tiles or walls_ghosted ~= #boundary then
    player.print("[SE Auto Ship] Warning: created " .. tiles_ghosted .. "/" .. #tiles .. " floor ghosts and " .. walls_ghosted .. "/" .. #boundary .. " wall ghosts.")
    player.print("Check for obstructing entities or unsupported ghost placement positions.")
  end

  if shape == "sphere" then
    player.print("[SE Auto Ship] Generated sphere hull, radius " .. radius .. " (diameter " .. (radius * 2 + 1) .. ").")
  elseif shape == "triangle" then
    player.print("[SE Auto Ship] Generated triangular hull, " .. width .. " x " .. length .. " (apex bow, flat stern).")
  else
    player.print("[SE Auto Ship] Generated pointed-bow hull, " .. validation.width .. " x " .. validation.height .. ".")
  end
  player.print(string.format("SE-matched hull estimate: streamline %.2f%% | structural stress %.1f | container stress %.1f", validation.streamline * 100, validation.structural_stress, validation.container_stress))
  player.print("Hull plan: " .. validation.tile_count .. " floor tiles, " .. walls_ghosted .. " wall ghosts, " .. string.format("%.2f", validation.phantom_tiles) .. " phantom tiles.")
  if shape == "sphere" then
    player.print("Sphere perimeter: one-tile-thick, 4-way connected and sealed against the 8-way containment flood.")
  elseif shape == "triangle" then
    player.print("Triangle perimeter: thin sloped sides with only the connector tiles needed for 4-way wall continuity.")
  end
  if validation.streamline < 0.9999 then
    player.print("[SE Auto Ship] Note: this size's rasterized outline does not score 100% streamline.")
  end
  player.print("Estimate only: mirrors SE hull formulas, assuming completed wall entities and an otherwise empty ship. Cargo, fluids, equipment, generators and other entities are excluded.")
  player.print("Actual SE integrity has NOT been checked: ghosts are not completed floor/wall entities. Build the ghosts, then run the spaceship console integrity check.")
  player.print("Created " .. tiles_ghosted .. " floor ghosts, " .. walls_ghosted .. " wall ghosts, and " .. (console_ghost and 1 or 0) .. " console ghost.")
  player.print("Construction robots can build these ghosts when materials and logistic coverage are available.")
  player.print("Hull only: add propulsion and other required ship systems separately.")
end

commands.add_command("se-blueprint-ship",
  "Create an SE ship hull blueprint. Usage: /se-blueprint-ship [pointed [width] [length] | triangle [width] [length] | sphere [radius]]",
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
    elseif args[1] == "triangle" then
      shape = "triangle"
      size_a = tonumber(args[2]) or DEFAULT_WIDTH
      size_b = tonumber(args[3]) or DEFAULT_LENGTH
    elseif args[1] == "pointed" then
      size_a = tonumber(args[2]) or DEFAULT_WIDTH
      size_b = tonumber(args[3]) or DEFAULT_LENGTH
    else
      size_a = tonumber(args[1]) or DEFAULT_WIDTH
      size_b = tonumber(args[2]) or DEFAULT_LENGTH
    end
    generate_ship(player, shape, size_a, size_b, "blueprint")
  end
)

commands.add_command("se-generate-ship",
  "Generate an SE ship hull. Usage: /se-generate-ship [pointed [width] [length] | triangle [width] [length] | sphere [radius]]",
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
    elseif args[1] == "triangle" then
      shape = "triangle"
      size_a = tonumber(args[2]) or DEFAULT_WIDTH
      size_b = tonumber(args[3]) or DEFAULT_LENGTH
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
