local DEFAULT_WIDTH = 13
local DEFAULT_LENGTH = 31
local MIN_WIDTH, MAX_WIDTH = 7, 31
local MIN_LENGTH, MAX_LENGTH = 15, 81

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

-- Build columns rather than rows. The minimum Y in each X column forms
-- a symmetric, stepped 45-degree bow:
--   front_y(x) = bow_tip_y + abs(x - centre_x)
--
-- In stop_integrity_check(), front_tiles[x] stores the minimum Y for each X.
-- This shape therefore gives:
--   max_flat = 2 (the mirrored left/right columns)
--   distinct front rows on each side = floor(width / 2)
-- which saturates the three streamline sub-scores for the supported widths.
local function build_plan(width, length, origin_x, origin_y, tile_name)
  local half_width = math.floor(width / 2)
  local half_length = math.floor(length / 2)
  local bow_tip_y = origin_y - half_length
  local stern_y = origin_y + half_length

  local tiles = {}
  local boundary = {}
  local boundary_seen = {}

  local function add_boundary(x, y)
    local key = x .. ":" .. y
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
    end
  end

  return tiles, boundary, half_width, half_length
end

local function generate_ship(player, width, length)
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

  width = clamp(math.floor(width or DEFAULT_WIDTH), MIN_WIDTH, MAX_WIDTH)
  length = clamp(math.floor(length or DEFAULT_LENGTH), MIN_LENGTH, MAX_LENGTH)
  if width % 2 == 0 then width = width - 1 end
  if length % 2 == 0 then length = length - 1 end

  local origin_x = math.floor(player.position.x)
  local origin_y = math.floor(player.position.y)
  local tiles, boundary, half_width, half_length =
    build_plan(width, length, origin_x, origin_y, tile_name)

  -- Refuse to overwrite existing entities in the generated footprint.
  local area = {
    {origin_x - half_width - 2, origin_y - half_length - 2},
    {origin_x + half_width + 2, origin_y + half_length + 2}
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

  player.print("[SE Auto Ship] Generated pointed-bow hull: " .. width .. " x " .. length .. ".")
  player.print("The geometry is designed to score 100% streamline in the supplied SE formula.")
  player.print("Walls placed: " .. walls_placed .. ". Run the console's normal integrity check.")
  player.print("Note: this is a hull only; add propulsion and other required ship systems separately.")
end

commands.add_command("se-generate-ship",
  "Generate a pointed-bow SE ship hull. Usage: /se-generate-ship [width] [length]",
  function(command)
    local player = game.get_player(command.player_index)
    if not player then return end
    local args = {}
    for token in string.gmatch(command.parameter or "", "%S+") do
      args[#args + 1] = tonumber(token)
    end
    generate_ship(player, args[1] or DEFAULT_WIDTH, args[2] or DEFAULT_LENGTH)
  end
)
