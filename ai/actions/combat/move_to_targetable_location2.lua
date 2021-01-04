local FollowPath = require 'stonehearth.ai.lib.follow_path'
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local MoveToTargetableLocationForDarts = radiant.class()

MoveToTargetableLocationForDarts.name = 'move to targetable location'
MoveToTargetableLocationForDarts.does = 'box_o_vox:combat:move_to_targetable_location'
MoveToTargetableLocationForDarts.args = {
   target = Entity,
   grid_location_changed_cb = {  -- triggered as the chasing entity changes grid locations
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
MoveToTargetableLocationForDarts.priority = 0

function MoveToTargetableLocationForDarts:start_thinking(ai, entity, args)
   self._ready = false
   self._is_thinking = true
   
   self._delay_start_timer = radiant.on_game_loop_once('GetPrimaryTarget start_thinking', function()
         local update_think_output = function()
               self:_update_think_output(ai, entity, args)
            end

         update_think_output()

         self._leash_changed_trace = radiant.events.listen(entity, 'stonehearth:combat_state:leash_changed', update_think_output)

         if not self._ready then
            self._target_location_trace = radiant.entities.trace_grid_location(args.target, 'move to targetable location')
                                             :on_changed(update_think_output)
         end
      end)
end

function MoveToTargetableLocationForDarts:_update_think_output(ai, entity, args)
   if not self._is_thinking then
      return
   end

   local clear_think_output = function()
         if self._ready then
            self._destination = nil
            ai:clear_think_output()
            self._ready = false
         end
      end

   local weapon = radiant.entities.get_equipped_item(entity, 'darts_slot')
   if not weapon or not weapon:is_valid() then
      clear_think_output()
      return
   end

   -- We only think if the target is not targetable.
   -- This prevents unnecessary pathfinding when we can already shoot the target.
   if stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
      clear_think_output()
      return
   end

   local destination = self:_find_location(entity, args.target)
   if not destination then
      clear_think_output()
      return
   end

   if destination ~= self._destination then
      local grid_location_changed_cb = function()
            local weapon = radiant.entities.get_equipped_item(entity, 'darts_slot')
            if not weapon or not weapon:is_valid() then
               return false
            end

            if stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
               local result = true

               if args.grid_location_changed_cb then
                  result = args.grid_location_changed_cb()
               end

               return result
            end

            return false
         end

      -- Clear think output if we have set it before
      clear_think_output()

      self._destination = destination
      self._ready = true

      ai:set_think_output({
            location = destination,
            grid_location_changed_cb = grid_location_changed_cb,
         })
   end
end

function MoveToTargetableLocationForDarts:stop_thinking(ai, entity, args)
   self._is_thinking = false
   if self._delay_start_timer then
      self._delay_start_timer:destroy()
      self._delay_start_timer = nil
   end
   if self._leash_changed_trace then
      self._leash_changed_trace:destroy()
      self._leash_changed_trace = nil
   end

   if self._target_location_trace then
      self._target_location_trace:destroy()
      self._target_location_trace = nil
   end
end

-- TODO: shoot rays at several angles and perform local search around each end point
function MoveToTargetableLocationForDarts:_find_location(entity, target)
   local weapon = radiant.entities.get_equipped_item(entity, 'darts_slot')
   if not weapon or not weapon:is_valid() then
      return nil
   end

   local range = stonehearth.combat:get_weapon_range(entity, weapon)
   local entity_location = radiant.entities.get_world_grid_location(entity)
   local target_location = radiant.entities.get_world_grid_location(target)
   local end_point = radiant.terrain.get_direct_path_end_point(entity_location, target_location, entity, true)

   local search_cube = self:_get_search_cube(entity)
   local search_point = search_cube:get_closest_point(end_point)
   local candidate_location = _physics:get_standable_point(entity, search_point)

   if self:_in_range_and_has_line_of_sight(entity, target, candidate_location, target_location, range) then
      return candidate_location
   end

   return nil
end

function MoveToTargetableLocationForDarts:_get_search_cube(entity)
   local leash = stonehearth.combat:get_leash_data(entity) or {}

   local center, range = leash.center, leash.range
   if not center then
      center = radiant.entities.get_world_grid_location(entity)
      range = stonehearth.terrain:get_sight_radius()
   end

   -- This is deliberately a planar cube. We'll adjust for terrain later.
   local search_cube = Cube3(center):inflated(Point3(range, 0, range))
   return search_cube
end

-- This code must match the implementation of combat_service:in_range_and_has_line_of_sight()
-- or we risk having ai spins.
function MoveToTargetableLocationForDarts:_in_range_and_has_line_of_sight(attacker, target, attacker_location, target_location, range)
   if attacker_location:distance_to(target_location) <= range then
      if _physics:has_line_of_sight(attacker, target, attacker_location, target_location) then
         return true
      end
   end

   return false
end

local ai = stonehearth.ai
return ai:create_compound_action(MoveToTargetableLocationForDarts)
         :execute('stonehearth:goto_location', {
            reason = 'move to line of sight',
            location = ai.PREV.location,
            grid_location_changed_cb = ai.PREV.grid_location_changed_cb,
         })
