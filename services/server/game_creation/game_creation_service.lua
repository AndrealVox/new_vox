local constants = require 'constants'
local rng = _radiant.math.get_default_rng()
local Array2D = require 'services.server.world_generation.array_2D'
local BlueprintGenerator = require 'services.server.world_generation.blueprint_generator'

local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2

local validator = radiant.validator
local log = radiant.log.create_logger('world_generation')
local NUM_STARTING_CITIZENS = constants.game_creation.num_starting_citizens
local GENDERS = radiant.map_to_array(constants.population.genders)
local MALE = constants.population.genders.male
local FEMALE = constants.population.genders.female

local DEFAULT_WORLD_GENERATION_RADIUS = 2
local WORLD_GENERATION_RADII = {
   default = DEFAULT_WORLD_GENERATION_RADIUS,
   small = 1,
   tiny = 1,
}

local MIN_STARTING_ITEM_RADIUS = 0
local MAX_STARTING_ITEM_RADIUS = 5

local GameCreationService = class()

function GameCreationService:create_camp_command(session, response, pt)
   validator.expect_argument_types({'table'}, pt)
   validator.expect.table.fields({'x', 'y', 'z'}, pt)
   
   if validator.is_host_player(session) then
      stonehearth.calendar:start()
      stonehearth.hydrology:start()
   end

   stonehearth.world_generation:set_starting_location(Point2(pt.x, pt.z))

   local facing = 180
   local player_id = session.player_id
   local town = stonehearth.town:get_town(player_id)
   local pop = stonehearth.population:get_population(player_id)
   local random_town_name = town:get_town_name()
   local inventory = stonehearth.inventory:get_inventory(player_id)

   -- save that the camp has been placed
   pop:place_camp()

   -- place the stanfard in the middle of the camp
   local location = Point3(pt.x, pt.y, pt.z)

   local standard, standard_ghost = stonehearth.player:get_kingdom_banner_style(session.player_id)
   if not standard then
      standard = 'stonehearth:camp_standard'
   end

   local banner_entity = radiant.entities.create_entity(standard, { owner = player_id })
   inventory:add_item(banner_entity)
   radiant.terrain.place_entity(banner_entity, location, { facing = facing, force_iconic = false })
   town:set_banner(banner_entity)

   -- build the camp
   local camp_x = pt.x
   local camp_z = pt.z

   local citizen_locations = {
   }
    
   if next(pop:get_generated_citizens()) == nil then
      -- for quick start. TODO: make quick start integrate existing starting flow so we don't need to do this
      self:_generate_initial_roster(pop)
   end

   -- get final citizens and destroy gender entity copies
   local final_citizens = self:_get_final_citizens(pop, true)

   local citizen_offset = 3
    local no_citizens = 0
    -- count the number of final citizens
   for _, citizen in pairs(final_citizens) do
        no_citizens = no_citizens +1
    end
    
    local height_width = 0
    -- set the height and width of the square to place citizens
    if no_citizens >= 9 then
        height_width = math.floor(math.ceil(math.sqrt(no_citizens))/2)
    else
        height_width = math.floor(3/2)
    end
    local lIndex = 1   -- location index
    local yIndex = 0 -- y placement index
    for yIndex = (-1*height_width), height_width do
        local xIndex = 0
        for xIndex = height_width * -1, height_width do
            table.insert(citizen_locations,  {x=camp_x+(xIndex * citizen_offset), y=camp_z+(yIndex * citizen_offset)})
            if yIndex == 0 and xIndex == 0 then -- if its camp location move it above grid(unused spot)
                citizen_locations[lIndex].y = camp_z + ((height_width+1) * citizen_offset)
            end
            xIndex = xIndex +1
            lIndex = lIndex +1
        end
        yIndex = yIndex +1
    end
    
   local index = 1
   for _, citizen in pairs(final_citizens) do
      local location = citizen_locations[index]
      self:_place_citizen_embark(citizen, location.x, location.y, { facing = facing })
      index = index + 1
   end

   pop:unset_generated_citizens()

   local town =  stonehearth.town:get_town(player_id)
   town:check_for_combat_job_presence()

   local hearth = self:_place_item(pop, 'stonehearth:decoration:firepit_hearth', camp_x, camp_z+5, { facing = facing, force_iconic = false })
   inventory:add_item(hearth)
   town:set_hearth(hearth)

   local starting_resource = stonehearth.player:get_kingdom_starting_resource(player_id) or 'stonehearth:resources:wood:oak_log'
   local item1 = pop:create_entity(starting_resource)
   local item2 = pop:create_entity(starting_resource)
   self:try_place_entity_on_terrain(item1, camp_x, camp_z)
   self:try_place_entity_on_terrain(item2, camp_x, camp_z)
   inventory:add_item(item1)
   inventory:add_item(item2)
   radiant.entities.pickup_item(final_citizens[1], item1)
   radiant.entities.pickup_item(final_citizens[2], item2)
   
   stonehearth.game_master:get_game_master(player_id):start()

   local game_options = pop:get_game_options()

   if validator.is_host_player(session) then
      -- Open game to remote players if specified
      if game_options.remote_connections_enabled then
         stonehearth.session_server:set_remote_connections_enabled(true)
      end

      -- Set max number of remote players if specified
      if game_options.max_players then
         stonehearth.session_server:set_max_players(game_options.max_players)
      end
   end

   -- Spawn initial items
   local starting_items = radiant.entities.spawn_items(game_options.starting_items, location,
      MIN_STARTING_ITEM_RADIUS, MAX_STARTING_ITEM_RADIUS, { owner = player_id })

   -- add all the spawned items to the inventory, have citizens pick up items
   local i = 3
   for id, item in pairs(starting_items) do
      inventory:add_item(item)
      if i <= NUM_STARTING_CITIZENS then
         radiant.entities.pickup_item(final_citizens[i], item)
      end
   end

   -- kickstarter pets
   if game_options.starting_pets then
       for i, pet_uri in ipairs (game_options.starting_pets) do
          local x_offset = -6 + i * 3;
          self:_place_pet(pop, pet_uri, camp_x-x_offset, camp_z-6, { facing = facing })
       end
   end

   -- Add starting gold
   local starting_gold = game_options.starting_gold
   if (starting_gold > 0) then
      local inventory = stonehearth.inventory:get_inventory(player_id)
      inventory:add_gold(starting_gold)
   end

   stonehearth.terrain:set_fow_enabled(player_id, true)

   return {random_town_name = random_town_name}
end

return GameCreationService
