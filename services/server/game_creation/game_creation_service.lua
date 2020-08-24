local constants = require 'constants'
local rng = _radiant.math.get_default_rng()
local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
local BlueprintGenerator = require 'stonehearth.services.server.world_generation.blueprint_generator'

local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2

local validator = radiant.validator
local log = radiant.log.create_logger('world_generation')
local NUM_STARTING_CITIZENS = constants.game_creation.num_starting_citizens
local GENDERS = constants.population.base_genders
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

GameCreationService = class()

function GameCreationService:initialize()
   self._sv = self.__saved_variables:get_data()
   self._kingdoms = radiant.resources.load_json('stonehearth:playable_kingdom_index')

   if not self._sv.initialized then
      self._sv.game_mode = "stonehearth:game_mode:normal"
      self._sv.initialized = true
      self._sv.game_parent_version_uuid = ''
      self._sv.game_version_uuid = ''
      self._sv.game_id = ''
      self._sv.game_creation_time = ''
      self._sv.created_on_product_version = _radiant.sim.get_product_version_string()
      self._sv._custom_game_data = nil
   else
      if self._sv.game_id == nil then
         -- We need to initialize these variables because they don't exist in this save game. AH! -yshan
         self._sv.game_id = _radiant.sim.generate_uuid()
         self._sv.game_version_uuid = _radiant.sim.generate_uuid()
         self._sv.game_parent_version_uuid = ''
         self._sv.game_creation_time = ''
         self._sv.created_on_product_version = 'unknown'
      end
   end

   if self._sv.game_mode then
      self._game_mode_json = radiant.resources.load_json(self._sv.game_mode)
   end
end

function GameCreationService:restore()
   self._sv.game_parent_version_uuid = self._sv.game_version_uuid
   self._sv.game_version_uuid = _radiant.sim.generate_uuid()

   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
      stonehearth.analytics:on_game_started(self._sv.game_id, self._sv.game_parent_version_uuid)
      self._game_loaded_listener = nil
   end)
   self.__saved_variables:mark_changed()
end

function GameCreationService:sign_in_command(session, response)
   return {
      product_version_string = _radiant.sim.get_product_version_string(),
      current_save_version   = _radiant.sim.get_current_save_version(),
      min_supported_save_version = _radiant.sim.get_min_supported_save_version(),
   }
end

function GameCreationService:get_playable_kingdoms(session, response)
   return {
      kingdoms = self._kingdoms
   }
end

function GameCreationService:get_game_mode()
   return self._sv.game_mode
end

function GameCreationService:set_game_mode(game_mode_uri)
   if self._sv._game_mode_initialized then
      log:error('Trying to set game mode to %s when it has already been set to %s by host', game_mode_uri, self._sv.game_mode)
      return
   end

   self._sv.game_mode = game_mode_uri
   self._game_mode_json = radiant.resources.load_json(self._sv.game_mode)
   self._sv._game_mode_initialized = true
   radiant.events.trigger_async(self, 'stonehearth:game_mode_changed')
end

function GameCreationService:get_game_mode_json()
   return self._game_mode_json
end

function GameCreationService:get_game_analytics_data()
   local analytics_data = {
      game_id = self._sv.game_id,
      game_version_uuid = self._sv.game_version_uuid,
      game_parent_version_uuid = self._sv.game_parent_version_uuid,
      game_mode = self._sv.game_mode
   }
   return analytics_data
end

function GameCreationService:get_game_id()
   return self._sv.game_id
end

function GameCreationService:get_game_version()
   return self._sv.game_version_uuid
end

--If the kingdom is not yet selected, select it now
function GameCreationService:select_player_kingdom(session, response, kingdom)
   validator.expect_argument_types({'string'}, kingdom)
   validator.expect.string.max_length(kingdom, 256)

   if not stonehearth.player:get_kingdom(session.player_id) then
      stonehearth.player:add_kingdom(session.player_id, kingdom)
   end
   return {}
end

function GameCreationService:create_new_world(num_tiles_x, num_tiles_y, seed, biome_src)
   local seed = radiant.util.get_config('world_generation.seed', seed)
   local generation_method = radiant.util.get_config('world_generation.method', 'default')
   local wgs = stonehearth.world_generation
   local blueprint
   local tile_margin

   log:info('using biome %s', biome_src)

   wgs:create_new_game(seed, biome_src, true)

   -- Temporary merge code. The javascript client may eventually hold state about the original dimensions.
   if generation_method == 'tiny' then
      tile_margin = 0
      blueprint = wgs.blueprint_generator:get_empty_blueprint(2, 2) -- (2,2) is minimum size
   else
      -- generate extra tiles along the edge of the map so that we still have a full N x N set of tiles if we embark on the edge
      tile_margin = self:_get_world_generation_radius()
      num_tiles_x = num_tiles_x + 2*tile_margin
      num_tiles_y = num_tiles_y + 2*tile_margin
      blueprint = wgs.blueprint_generator:get_empty_blueprint(num_tiles_x, num_tiles_y)
   end

   wgs:set_blueprint(blueprint)

   return self:_get_overview_map(tile_margin)
end

function GameCreationService:new_game_command(session, response, num_tiles_x, num_tiles_y, seed, options, starting_data)
   validator.expect_argument_types({'number', 'number', 'number', 'table', 'table'}, num_tiles_x, num_tiles_y, seed, options, starting_data)
   validator.expect.num.positive(num_tiles_x)
   validator.expect.num.positive(num_tiles_y)
   validator.expect.table.fields({'biome_src'}, options)

   --if no kingdom has been set for the player yet, set it to ascendancy
   if not stonehearth.player:get_kingdom(session.player_id) then
      stonehearth.player:add_kingdom(session.player_id, "stonehearth:kingdoms:ascendancy")
   end

   local pop = stonehearth.population:get_population(session.player_id)
   pop:set_game_options(options)

   self._starting_data = starting_data

   local overview_map = self:create_new_world(num_tiles_x, num_tiles_y, seed, options.biome_src)
   self.__saved_variables:mark_changed()

   return overview_map
end

function GameCreationService:is_world_created()
   return self._sv.game_id ~= ''
end

function GameCreationService:is_world_generated_command(session, response)
   local generated = self:is_world_created()
   response:resolve({ already_generated = generated })
end

function GameCreationService:on_world_generation_complete()
   -- The game starts after world generation finishes!
   self._sv.game_id = _radiant.sim.generate_uuid()
   self._sv.game_creation_time = stonehearth.analytics:get_formatted_universal_time()
   self._sv.game_version_uuid = self._sv.game_id

   stonehearth.analytics:on_game_started(self._sv.game_id, self._sv.game_version_uuid, self._starting_data)
   _radiant.sim.start_game()

   radiant.events.trigger(self, 'stonehearth:world_generation_complete')
end

-- options should have fields: seed, width, height, game_mode, biome_src
function GameCreationService:build_world(config_options)
   local options = radiant.resources.load_json('stonehearth:game_creation:default_options')

   if config_options then
      for key, _ in pairs(options) do
         if config_options[key] then
            options[key] = config_options[key]
         end
      end
   end

   local seed = options.seed
   local x = options.x
   local y = options.y
   local width = options.width
   local height = options.height

   local game_modes_index = radiant.resources.load_json('stonehearth:game_mode:index').game_modes
   local game_mode = game_modes_index[options.game_mode]

   local biomes_index = radiant.resources.load_json('stonehearth:biome:index').biomes
   local biome = biomes_index[options.biome_src]

   self:set_game_mode(game_mode)
   local world = self:create_new_world(width, height, seed, biome)
   self:generate_start_location(x, y, world.map_info)
end

function GameCreationService:get_reembark_specs_command(session, response)
   local specs = radiant.mods.enum_objects('reembarkation')
   local result = {}
   for _, name in ipairs(specs) do
      result[name] = radiant.mods.read_object('reembarkation/' .. name)
   end
   response:resolve({ result = result })
end

-- generate citizens and make a copy of each citizen for each gender
function GameCreationService:generate_citizens_command(session, response, initialize, citizen_locked_options)
   validator.expect_argument_types({'boolean', validator.optional('table')}, initialize, citizen_locked_options)

   local pop = stonehearth.population:get_population(session.player_id)
   citizen_locked_options = citizen_locked_options or {}

   local final_citizens
   if initialize then
      -- create roster entities
      final_citizens = self:_generate_initial_roster(pop)
   else
      -- randomize appearance, stats, gender
      final_citizens = self:_randomize_citizens(pop, citizen_locked_options)
   end

   response:resolve({ citizens = final_citizens })
end

-- generate citizens and make a copy of each citizen for each gender
function GameCreationService:generate_citizens_for_reembark_command(session, response, reembark_spec)
   validator.expect_argument_types({'table'}, reembark_spec)

   local pop = stonehearth.population:get_population(session.player_id)

   for index, citizen_spec in ipairs(reembark_spec.citizens) do
      local gender = citizen_spec.model_variant
      local role_data = { [gender] = { uri = { citizen_spec.uri } } }
      local citizen = pop:create_new_citizen_from_role_data('default', role_data, gender, {
         suppress_traits = true,
         embarking = true,
      })

      -- Set name.
      radiant.entities.set_custom_name(citizen, citizen_spec.name)
      citizen:set_debug_text(citizen_spec.name)

      -- Set attributes.
      local attributes = citizen:add_component('stonehearth:attributes')
      attributes:set_attribute('body', citizen_spec.attributes.body)
      attributes:set_attribute('spirit', citizen_spec.attributes.spirit)
      attributes:set_attribute('mind', citizen_spec.attributes.mind)

      -- Set traits.
      local traits = citizen:add_component('stonehearth:traits')
      for _, trait_uri in ipairs(citizen_spec.traits) do
         traits:add_trait(trait_uri)
      end

      -- Set jobs.
      local job = citizen:get_component('stonehearth:job')
      if citizen_spec.allowed_jobs then
         job:set_allowed_jobs(citizen_spec.allowed_jobs)
      end
      for job_uri, level in pairs(citizen_spec.job_levels) do
         job:promote_to(job_uri, { skip_visual_effects = true, dont_drop_talisman = true })
         for _ = 1, level - 1 do
            job:level_up(true)
         end
      end
      job:promote_to(citizen_spec.current_job, { skip_visual_effects = true, dont_drop_talisman = true })

      -- Set customization.
      local customization = citizen:get_component('stonehearth:customization')
      for subcategory, style in pairs(citizen_spec.customization) do
         customization:change_customization(subcategory, style)
      end

      -- Set item preferences.
      local appeal = citizen:get_component('stonehearth:appeal')
      appeal:set_item_preferences(citizen_spec.item_preferences, citizen_spec.item_preference_discovered_flags)

      -- Set equipment.
      local equipment = citizen:get_component('stonehearth:equipment')
      for _, equipment_uri in ipairs(citizen_spec.equipment) do
         local equipment_entity = radiant.entities.create_entity(equipment_uri, { owner = session.player_id })
         equipment:equip_item(equipment_entity, true)
      end

      -- Replace existing.
      local generated_citizens = pop:get_generated_citizens()
      if index <= #generated_citizens then -- Skip replacement if index is out of bounds
         local citizen_entry = generated_citizens[index]
         citizen_entry.current_gender = gender
         if citizen_entry[gender] then
            radiant.entities.destroy_entity(citizen_entry[gender])
         end
         citizen_entry[gender] = citizen
      end
   end

   local final_citizens = self:_get_final_citizens(pop)

   response:resolve({ citizens = final_citizens, num_reembarked = math.min(#reembark_spec.citizens, NUM_STARTING_CITIZENS) })
end

function GameCreationService:_generate_initial_roster(pop)
   if pop:get_roster_initialized() then
      local generated_citizens = pop:get_generated_citizens()
      for _, citizen_entry in pairs(generated_citizens) do
         for _, citizen in pairs(citizen_entry) do
            if type(citizen) == 'userdata' and radiant.entities.exists(citizen) then
               radiant.entities.destroy_entity(citizen)
            end
         end
      end
      pop:unset_generated_citizens()
   end

   pop:reset_generated_citizens()

   local citizens_by_gender = {}
   -- generate a set of citizens for each gender, so we can swap between genders
   -- and randomize citizens on the embarkation screen without needing to destroy and
   -- recreate all of the citizens each time we want a new starting party. literally overkill
   for _, gender in ipairs(GENDERS) do
      citizens_by_gender[gender] = pop:generate_roster(NUM_STARTING_CITIZENS, {
         gender = gender,
         embarking = true
      })
   end

   for i=1, NUM_STARTING_CITIZENS do
      local citizen_entry = {}
      for gender, citizens in pairs(citizens_by_gender) do
         citizen_entry[gender] = citizens[i]
      end

      -- select a random gender for this citizen
      citizen_entry.current_gender = self:_pick_random_gender()
      pop:set_generated_citizen(i, citizen_entry)
   end
   self.__saved_variables:mark_changed()

   pop:set_roster_initialized(true)
   -- get selected / final citizens for starting party
   return self:_get_final_citizens(pop)
end

function GameCreationService:_randomize_citizens(pop, citizen_locked_options)
   for index, citizen_entry in pairs(pop:get_generated_citizens()) do
      local locked_options = citizen_locked_options[index]
      if not locked_options or not locked_options.frozen then
         self:_regenerate_citizen_stats_and_appearance(index, pop, locked_options)
      end
   end

   return self:_get_final_citizens(pop)
end

-- regenerate a single citizen
function GameCreationService:regenerate_citizen_stats_and_appearance_command(session, response, roster_index, locked_options)
   validator.expect_argument_types({'number', validator.optional('table')}, roster_index, locked_options)
   validator.expect.num.nonnegative(roster_index)

   local index = roster_index + 1 -- convert to 1-based index
   local pop = stonehearth.population:get_population(session.player_id)
   local citizen = self:_regenerate_citizen_stats_and_appearance(index, pop, locked_options)

   response:resolve({ citizen = citizen })
end

function GameCreationService:_regenerate_citizen_stats_and_appearance(index, pop, locked_options)
   local hasLockedCustomizations = false
   if locked_options and locked_options.customizations then
      for customization, isLocked in pairs(locked_options.customizations) do
         if isLocked then
            hasLockedCustomizations = true
            break
         end
      end
   end

   -- if no customization options are locked, randomize the gender of the citizen
   local citizen, gender = self:_select_citizen_at_index(pop, index, { randomize_gender = not hasLockedCustomizations })
   self:_randomize_citizen(citizen, pop, gender, locked_options)
   return citizen
end

function GameCreationService:_randomize_citizen(citizen, pop, gender, locked_options)
   locked_options = locked_options or {}
   if not locked_options.name then
      pop:set_citizen_name(citizen, gender)
   end

   pop:regenerate_stats(citizen, { embarking = true })
   local cc = citizen:get_component('stonehearth:customization')
   cc:regenerate_appearance(locked_options.customizations)
end

function GameCreationService:change_gender_command(session, response, roster_index, target_gender)
   validator.expect_argument_types({'number', 'string'}, roster_index, target_gender)
   validator.expect.num.nonnegative(roster_index)
   validator.expect.string.max_length(target_gender)

   local i = roster_index + 1 -- convert to 1-based index
   local pop = stonehearth.population:get_population(session.player_id)
   local citizen = self:_select_citizen_at_index(pop, i)

   if citizen then

      local pop = stonehearth.population:get_population(session.player_id)
      local citizen_entry = pop:get_generated_citizen(i)
      local new_citizen = citizen_entry[target_gender]
      -- update selected gender
      citizen_entry.current_gender = target_gender
      pop:copy_citizen_stats(citizen, new_citizen)

      -- copy over name
      self:_copy_name(citizen, new_citizen)

      --copy appearance
      stonehearth.customization:copy_appearance(citizen, new_citizen)

      response:resolve({ citizen = new_citizen })
   else
      response:reject('GameCreationService could not find generated citizen at index ' .. i)
   end
end

function GameCreationService:_get_overview_map(tile_margin)
   local wgs = stonehearth.world_generation
   local biome = wgs:get_biome_generation_data()
   local width, height = wgs.overview_map:get_dimensions()
   local map = wgs.overview_map:get_map()

   -- create an inset map so that embarking on the edge of the map will still get a full N x N set of terrain tiles
   local macro_blocks_per_tile = biome:get_tile_size() / biome:get_macro_block_size()
   local macro_block_margin = tile_margin*macro_blocks_per_tile
   local inset_width = width - 2*macro_block_margin
   local inset_height = height - 2*macro_block_margin
   local inset_map = Array2D(inset_width, inset_height)

   Array2D.copy_block(inset_map, map, 1, 1, 1+macro_block_margin, 1+macro_block_margin, inset_width, inset_height)

   local js_map = inset_map:copy_to_nested_arrays()

   local color_map = biome:get_color_map()
   local custom_name_map = biome:get_custom_name_map()

   local result = {
      map = js_map,
      map_info = {
         width = inset_width,
         height = inset_height,
         macro_block_margin = macro_block_margin,
         color_map = color_map,
         custom_name_map = custom_name_map
      }
   }
   return result
end

function GameCreationService:generate_start_location(feature_cell_x, feature_cell_y, map_info)
   local wgs = stonehearth.world_generation

   -- +macro_block_margin to convert from inset coordinates to full coordinates
   feature_cell_x = feature_cell_x + map_info.macro_block_margin
   feature_cell_y = feature_cell_y + map_info.macro_block_margin

   local x, z = wgs.overview_map:get_coords_of_cell_center(feature_cell_x, feature_cell_y)

   -- better place to store this?
   wgs.generation_location = Point3(x, 0, z)

   local radius = self:_get_world_generation_radius()
   local blueprint = wgs:get_blueprint()
   local i, j = wgs:get_tile_index(x, z)

   -- move (i, j) if it is too close to the edge
   -- note, because the map is now generated with an extra margin, this code never executes
   if blueprint.width > 2*radius+1 then
      i = radiant.math.bound(i, 1+radius, blueprint.width-radius)
   end
   if blueprint.height > 2*radius+1 then
      j = radiant.math.bound(j, 1+radius, blueprint.height-radius)
   end

   wgs:generate_tiles(i, j, radius)
end

-- feature_cell_x and feature_cell_y are base 0
function GameCreationService:generate_start_location_command(session, response, feature_cell_x, feature_cell_y, map_info)
   validator.expect_argument_types({'number', 'number', 'table'}, feature_cell_x, feature_cell_y, map_info)
   validator.expect.num.nonnegative(feature_cell_x)
   validator.expect.num.nonnegative(feature_cell_y)
   validator.expect.table.types({
      width = 'number',
      height = 'number',
      macro_block_margin = 'number',
      color_map = 'table',
   }, map_info)

   -- convert features_cell coordinates to base 1
   self:generate_start_location(feature_cell_x+1, feature_cell_y+1, map_info)
   response:resolve({})
end

function GameCreationService:_get_world_generation_radius()
   local generation_method = radiant.util.get_config('world_generation.method', 'default')
   local radius = WORLD_GENERATION_RADII[generation_method] or 2
   return radius
end

-- returns coordinates of embark location
function GameCreationService:embark_command(session, response)
   local scenario_service = stonehearth.scenario
   local wgs = stonehearth.world_generation

   local generation_location = wgs.generation_location or
                               stonehearth.terrain:get_centroid() or
                               Point3(0,0,0)

   local x = generation_location.x
   local z = generation_location.z
   local y = radiant.terrain.get_point_on_terrain(Point3(x, 0, z)).y

   return {
      x = x,
      y = y,
      z = z
   }
end

function GameCreationService:create_camp_command(session, response, pt)
   validator.expect_argument_types({'table'}, pt)
   validator.expect.table.fields({'x', 'y', 'z'}, pt)

   if validator.is_host_player(session) then
      stonehearth.calendar:start()
      stonehearth.hydrology:start()
      stonehearth.mining:start()
   end

   stonehearth.world_generation:set_starting_location(Point2(pt.x, pt.z))

   local facing = 180
   local player_id = session.player_id
   local town = stonehearth.town:get_town(player_id)
   local pop = stonehearth.population:get_population(player_id)
   local random_town_name = town:get_town_name()
   local inventory = stonehearth.inventory:get_inventory(player_id)

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
      {x=camp_x-3, z=camp_z-3},
      {x=camp_x+0, z=camp_z-3},
      {x=camp_x+3, z=camp_z-3},
      {x=camp_x-3, z=camp_z+3},
      {x=camp_x+3, z=camp_z+3},
      {x=camp_x-3, z=camp_z+0},
      {x=camp_x+3, z=camp_z+0},
   }

   if next(pop:get_generated_citizens()) == nil then
      -- for quick start. TODO: make quick start integrate existing starting flow so we don't need to do this
      self:_generate_initial_roster(pop)
   end

   -- get final citizens and destroy gender entity copies
   local final_citizens = self:_get_final_citizens(pop, true)

   local index = 1
   local min_radius = 3
   local max_radius = 7
   local min_y = location.y - max_radius
   for _, citizen in pairs(final_citizens) do
      local citizen_location = citizen_locations[index]
      if not citizen_location then
         citizen_location = radiant.terrain.find_placement_point(location, min_radius, max_radius, citizen, 1, false)
      end
      self:_place_citizen_embark(citizen, citizen_location.x, citizen_location.z, { facing = facing, min_y = min_y })
      index = index + 1
   end

   pop:unset_generated_citizens()

   local town =  stonehearth.town:get_town(player_id)
   town:check_for_combat_job_presence()

   local camp_hearth_uri = pop:get_hearth() or 'stonehearth:decoration:firepit_hearth'
   local hearth = self:_place_item(pop, camp_hearth_uri, camp_x, camp_z+5, { facing = facing, force_iconic = false, min_y = min_y })
   inventory:add_item(hearth)
   town:set_hearth(hearth)

   local starting_resource = stonehearth.player:get_kingdom_starting_resource(player_id) or 'stonehearth:resources:wood:oak_log'
   for i=1,2 do
      local item = pop:create_entity(starting_resource)
      self:try_place_entity_on_terrain(item, camp_x, camp_z, { min_y = min_y })
      inventory:add_item(item)
      if i <= NUM_STARTING_CITIZENS then
         radiant.entities.pickup_item(final_citizens[i], item)
      end
   end

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

      -- Set whether clients can control game speed
      if game_options.game_speed_anarchy_enabled then
         stonehearth.game_speed:set_anarchy_enabled(game_options.game_speed_anarchy_enabled)
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

   -- Handle re-embarkation
   if game_options.reembark_spec then
      -- Add items.
      for _, item_spec in ipairs(game_options.reembark_spec.items) do
         if item_spec.uri == 'stonehearth:loot:gold' then
            inventory:add_gold(stonehearth.constants.reembarkation.gold_per_bag * item_spec.count)
         else
            local uri_exists = radiant.resources.load_json(item_spec.uri, true, false) ~= nil
            if uri_exists then
               local spawned_items = radiant.entities.spawn_items({ [item_spec.uri] =  item_spec.count }, location,
                  MIN_STARTING_ITEM_RADIUS, MAX_STARTING_ITEM_RADIUS, { owner = player_id })
               for _, item in pairs(spawned_items) do
                  if item_spec.item_quality > 1 then
                     item:add_component('stonehearth:item_quality'):initialize_quality(item_spec.item_quality)
                  end
                  inventory:add_item(item)
               end
            end
         end
      end

      -- Unlock recipes.
      for job_uri, recipe_keys in pairs(game_options.reembark_spec.recipes) do
         local job_info = stonehearth.job:get_job_info(player_id, job_uri)
         if job_info then  -- In case it was from a mod.
            for _, recipe_key in ipairs(recipe_keys) do
               if job_uri == 'stonehearth:jobs:farmer' then
                  job_info:manually_unlock_crop(recipe_key, true)
               else
                  job_info:manually_unlock_recipe(recipe_key, true)
               end
            end
         end
      end
   end

   stonehearth.terrain:set_fow_enabled(player_id, true)

   -- save that the camp has been placed
   pop:place_camp()

   return {random_town_name = random_town_name}
end

function GameCreationService:_place_citizen_embark(citizen, x, z, options)
   self:try_place_entity_on_terrain(citizen, x, z, options)
   radiant.events.trigger_async(stonehearth.personality, 'stonehearth:journal_event',
                          {entity = citizen, description = 'person_embarks'})
  radiant.events.trigger_async(citizen, 'stonehearth:embark_event')
end

function GameCreationService:_place_pet(pop, uri, x, z, options)
   local pet = self:_place_item(pop, uri, x, z, options)
   local pet_component = pet:add_component('stonehearth:pet')
   pet_component:convert_to_pet(pop:get_player_id())
   local citizens = pop:get_citizens()
   local citizen_ids = citizens:get_keys()
   local citizen_id = citizen_ids[rng:get_int(1, #citizen_ids)]
   pet_component:set_owner(citizens:get(citizen_id))
end

-- return an array of citizens for our starting roster
-- each citizen entry contains two citizens of two different genders
-- and the 'current_gender' field tells us which one is active / will be included
function GameCreationService:_get_final_citizens(pop, destroy_copies)
   local citizens = {}
   for i, citizen_entry in ipairs(pop:get_generated_citizens()) do
      -- add citizen to final citizens array if the current gender matches
      citizens[i] = citizen_entry[citizen_entry.current_gender]
      if destroy_copies then
         for key, citizen in pairs(citizen_entry) do
            if key ~= 'current_gender' and key ~= citizen_entry.current_gender then
               -- destroy our opposite gender copy
               radiant.entities.destroy_entity(citizen)
            end
         end
      end
   end

   -- Notify that count may have changed so that inventory cap
   -- can be adjusted appropriately
   pop:on_citizen_count_changed()

   return citizens
end

function GameCreationService:_select_citizen_at_index(pop, index, options)
   local generated_citizens = pop:get_generated_citizens()
   local citizen_entry = generated_citizens[index]
   local gender = citizen_entry.current_gender

   -- change to random gender if specified
   if options then
      local previous_gender = gender
      if options.randomize_gender then
         gender = self:_pick_random_gender()
      elseif options.target_gender then
         gender = options.target_gender
      end

      -- if we swapped genders, copy over the name since they represent the same citizen entry
      if gender ~= previous_gender then
         citizen_entry.current_gender = gender
         local previous_citizen = citizen_entry[previous_gender]
         local selected_citizen = citizen_entry[gender]
         self:_copy_name(previous_citizen, selected_citizen)
      end
   end

   return citizen_entry[gender], gender
end

function GameCreationService:_pick_random_gender()
   return radiant.get_random_value(GENDERS, rng)
end

function GameCreationService:_copy_name(citizen, new_citizen)
   local custom_name = radiant.entities.get_custom_name(citizen)
   radiant.entities.set_custom_name(new_citizen, custom_name)
end

function GameCreationService:_place_item(pop, uri, x, z, options)
   local player_id = pop:get_player_id()
   local entity = radiant.entities.create_entity(uri, { owner = player_id })
   self:try_place_entity_on_terrain(entity, x, z, options)
   return entity
end

-- Place entities directly on terrain and let the physics service bump them if there is a collision.
-- This makes it much harder to accidentally place entities on top of trees, bushes, etc.
function GameCreationService:try_place_entity_on_terrain(entity, x, z, options)
   local min_y = 1
   if options then
      min_y = options.min_y or 1
   end
   local location = radiant.terrain.get_point_on_terrain(Point3(x, min_y, z))
   radiant.terrain.place_entity_at_exact_location(entity, location, options)
end

function GameCreationService:get_game_world_options_commands(session, response)
   response:resolve({
      game_mode = self._sv.game_mode,
      biome = stonehearth.world_generation:get_biome_alias(),
   })
end

function GameCreationService:set_custom_game_info_command(session, response, data)
   self._sv._custom_game_data = data
   response:resolve({})
end

function GameCreationService:get_custom_game_info_command(session, response)
   local data = self._sv._custom_game_data or {}
   data.time = stonehearth.calendar:get_converted_elapsed_time()
   response:resolve(data)
end

return GameCreationService
