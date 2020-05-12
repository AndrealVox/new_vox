local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local RaycastLib = require 'stonehearth.ai.lib.raycast_lib'
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local SandstormWeather = class()

local STORMICLE_COUNT = 62
local STORMICLE_SPACING = 10
local STORMICLE_SPEED_PER_STEP = 2
local STORMICLE_DESCENT_PER_STEP = 1
local ENDPOINT_EDGE_MARGIN = 0.3
local DELAY_BEFORE_START = '0h+2h'
local DELAY_BEFORE_DESTROY = '20m'  -- Up to how long it takes particles to disperse after all stormicles stop emitting.
local MOVE_UPDATE_INTERVAL = '30s'
local STORMICLE_ENTITY = 'box_o_vox:weather:enchanted_mist:mist'
local MAX_STEP_HEIGHT = 50
local IMPACT_HEIGHT = 5
local CROP_DESTROY_CHANCE = 0   -- Per step while colliding. Affected by MOVE_UPDATE_INTERVAL. Lame, but good enough for now.

function SandstormWeather:initialize()
   self._sv._stormicles = {}
   self._sv._stormicles_active = {}
   self._sv._start_location = nil
   self._sv._total_displacement = nil
   self._sv._t = nil
   self._sv._start_timer = nil
   self._sv._end_timer = nil
   self._sv._move_interval = nil
   self._impact_search_cube = Cube3(Point3.zero):inflated(Point3(STORMICLE_SPACING / 2, IMPACT_HEIGHT, STORMICLE_SPACING / 2))
end

function SandstormWeather:restore()
   for i, stormicle in pairs(self._sv._stormicles) do
      if not self._sv._stormicles_active[i] then
         local effect_list = stormicle:get_component('effect_list')
         effect_list:remove_effect(select(2, effect_list:first_effect()))
      end
   end
end

function SandstormWeather:start()
   self._sv._start_timer = stonehearth.calendar:set_persistent_timer('sandstorm start', DELAY_BEFORE_START, radiant.bind(self, '_start_sandstorm'))
end

function SandstormWeather:stop()
   if self._sv._start_timer then
      -- Not started yet? Don't start.
      self._sv._start_timer:destroy()
      self._sv._start_timer = nil
   else
      -- Next update will clean everything up.
      for i, stormicle in pairs(self._sv._stormicles) do
         if self._sv._stormicles_active[i] then
            local effect_list = stormicle:get_component('effect_list')
            effect_list:remove_effect(select(2, effect_list:first_effect()))
         end
      end
      self._sv._stormicles_active = {}
   end
end

function SandstormWeather:_start_sandstorm()
   self._sv._start_timer:destroy()
   self._sv._start_timer = nil
   self._sv._t = 0

   -- Select start and end locations.
   local terrain_bounds = stonehearth.terrain:get_bounds()
   local min_x = terrain_bounds.min.x
   local max_x = terrain_bounds.max.x
   local start_x = rng:get_int(min_x, max_x - ENDPOINT_EDGE_MARGIN * (max_x - min_x))
   local end_x = rng:get_int(min_x + ENDPOINT_EDGE_MARGIN * (max_x - min_x), max_x)
   self._sv._start_location = Point3(start_x, 0, terrain_bounds.min.z)
   self._sv._total_displacement = Point3(end_x, 0, terrain_bounds.max.z) - self._sv._start_location
   
   self:_spawn_missing_stormicles()
   self._sv._move_interval = stonehearth.calendar:set_persistent_interval('sandstorm update', MOVE_UPDATE_INTERVAL, radiant.bind(self, '_update'))
end

function SandstormWeather:_update()
   self._sv._t = self._sv._t + STORMICLE_SPEED_PER_STEP / self._sv._total_displacement:length()
   -- t can go beyond 1, since the center of the storm may have reached the target,
   -- but one of the sides is still on the map. Wait for all stormicles to die.
   self:_spawn_missing_stormicles()
   self:_move_stormicles()
   self:_apply_stormicle_damage()
   if not next(self._sv._stormicles_active) then
      -- All stormicles have left the map. There may still be particles hanging around so give them a moment to disperse.
      self._sv._start_location = nil
      self._sv._total_displacement = nil
      self._sv._t = nil
      self._sv._move_interval:destroy()
      self._sv._move_interval = nil
      self._sv._end_timer = stonehearth.calendar:set_persistent_timer('sandstorm end', DELAY_BEFORE_DESTROY, radiant.bind(self, '_end_sandstorm'))
   end
end

function SandstormWeather:_spawn_missing_stormicles()
   local terrain_bounds = stonehearth.terrain:get_bounds()
   local center_location = self._sv._start_location + self._sv._total_displacement * self._sv._t
   local right_vector = self._sv._total_displacement:cross(Point3(0, 1, 0))
   right_vector:normalize()

   for i = -STORMICLE_COUNT / 2, STORMICLE_COUNT / 2 do
      if not self._sv._stormicles[i] then
         local location = center_location + right_vector * STORMICLE_SPACING * i

         if terrain_bounds:contains(location) then
            location = radiant.terrain.get_point_on_terrain(location)

            local stormicle = radiant.entities.create_entity(STORMICLE_ENTITY)
            local facing = math.atan2(-self._sv._total_displacement.z, self._sv._total_displacement.x) - math.atan2(1, 0)
            if facing < 0 then
               facing = facing + 2 * math.pi
            end
            radiant.terrain.place_entity_at_exact_location(stormicle, location, { facing = facing * 180 / math.pi })

            self._sv._stormicles[i] = stormicle
            self._sv._stormicles_active[i] = true
         end
      end
   end
end

function SandstormWeather:_move_stormicles()
   local terrain_bounds = stonehearth.terrain:get_bounds()
   local center_location = self._sv._start_location + self._sv._total_displacement * self._sv._t
   local right_vector = self._sv._total_displacement:cross(Point3(0, 1, 0))
   right_vector:normalize()
   
   for i = -STORMICLE_COUNT / 2, STORMICLE_COUNT / 2 do
      if self._sv._stormicles[i] and self._sv._stormicles_active[i] then
         local location = center_location + right_vector * STORMICLE_SPACING * i
         
         if terrain_bounds:contains(location) then
            local old_location = radiant.entities.get_world_location(self._sv._stormicles[i])
            location.y = old_location.y

            if RaycastLib.is_sight_blocked_by_terrain_or_building(old_location, location) then
               -- Can't go straight forward.
               -- Can we ascend?
               local upward_location = Point3(location)
               upward_location.y = upward_location.y + MAX_STEP_HEIGHT
               local valid_upward_location
               _physics:walk_line(location, upward_location, function(point)
                     if RaycastLib.is_terrain_or_building(point) then
                        return false
                     else
                        valid_upward_location = point
                        return true
                     end
                  end, 0)
               location = valid_upward_location
            else
               -- We can go straight forward!
               -- Should we be descending too?
               local downward_location = Point3(location)
               downward_location.y = downward_location.y - STORMICLE_DESCENT_PER_STEP
               if not RaycastLib.is_sight_blocked_by_terrain_or_building(location, downward_location) then
                  location = downward_location
               end
            end
         else
            location = nil
         end

         if location then
            radiant.entities.move_to(self._sv._stormicles[i], location)
         else
            -- End of the line. Keep alive, but don't move/damage, and stop emitting new particles.
            self._sv._stormicles_active[i] = nil  -- not false, so the table is empty when none are active
            local effect_list = self._sv._stormicles[i]:get_component('effect_list')
            effect_list:remove_effect(select(2, effect_list:first_effect()))
         end
      end
   end
end

function SandstormWeather:_apply_stormicle_damage()
   for i, stormicle in pairs(self._sv._stormicles) do
      if stormicle and self._sv._stormicles_active[i] then
         local search_cube = self._impact_search_cube:translated(radiant.entities.get_world_location(stormicle))
         for _, item in pairs(radiant.terrain.get_entities_in_cube(search_cube)) do
            self:_apply_stormicle_damage_to(item)
         end
      end
   end
end

function SandstormWeather:_apply_stormicle_damage_to(item)
   local expendables = item:get_component('stonehearth:expendable_resources')
   local target_type = radiant.entities.get_entity_data(item, 'stonehearth:target_type')
   if expendables and expendables:get_max_value('health') and target_type and target_type.target_type == 'mob' then
      radiant.entities.add_buff(item, 'box_o_vox:buffs:weather:hit_by_enchanted_mist')
      return
   end

   if item:get_component('stonehearth:crop') then
      if rng:get_real(0, 0) <= CROP_DESTROY_CHANCE then
         radiant.entities.kill_entity(item)
      end
      return
   end
end

function SandstormWeather:_end_sandstorm()
   for _, stormicle in pairs(self._sv._stormicles) do
      radiant.entities.kill_entity(stormicle)
   end
   self._sv._end_timer = nil
end

function SandstormWeather:destroy()
   for _, stormicle in pairs(self._sv._stormicles) do
      radiant.entities.kill_entity(stormicle)
   end
   self._sv._stormicles = {}
   self._sv._stormicles_active = {}
   self._sv._start_location = nil
   self._sv._total_displacement = nil
   self._sv._t = nil
   
   if self._sv._start_timer then
      self._sv._start_timer:destroy()
      self._sv._start_timer = nil
   end
   if self._sv._end_timer then
      self._sv._end_timer:destroy()
      self._sv._end_timer = nil
   end
   if self._sv._move_interval then
      self._sv._move_interval:destroy()
      self._sv._move_interval = nil
   end
end

return SandstormWeather
