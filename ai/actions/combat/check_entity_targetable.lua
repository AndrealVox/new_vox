local Entity = _radiant.om.Entity

local CheckEntityTargetableDarts = radiant.class()

CheckEntityTargetableDarts.name = 'check entity targetable'
CheckEntityTargetableDarts.does = 'box_o_vox:combat:check_entity_targetable'
CheckEntityTargetableDarts.args = {
   target = Entity
}
CheckEntityTargetableDarts.priority = 0

function CheckEntityTargetableDarts:start_thinking(ai, entity, args)
   self._ready = false
   self._is_thinking = true
   
   self._delay_start_timer = radiant.on_game_loop_once('ChaseEntityUntilTargetable start_thinking', function()
         local update_think_output = function()
               self:_update_think_output(ai, entity, args)
            end

         update_think_output()

         self._leash_changed_trace = radiant.events.listen(entity, 'stonehearth:combat_state:leash_changed', update_think_output)

         if not self._ready and radiant.entities.exists_in_world(args.target) then
            self._target_location_trace = radiant.entities.trace_grid_location(args.target, 'move to targetable location')
                                             :on_changed(update_think_output)
         end
      end)
end

function CheckEntityTargetableDarts:_update_think_output(ai, entity, args)
   if not self._is_thinking then
      return
   end

   local clear_think_output = function()
         if self._ready then
            ai:clear_think_output()
            self._ready = false
         end
      end

   local weapon = radiant.entities.get_equipped_item(entity, 'darts_slot')
   if not weapon or not weapon:is_valid() then
      clear_think_output()
      return
   end

   if not args.target then
      clear_think_output()
      return
   end

   -- Don't target/attack if we (not the target) are outside the leash
   if stonehearth.combat:is_entity_outside_leash(entity) then
      clear_think_output()
      return
   end

   if radiant.entities.is_entity_suspended(args.target) then
      clear_think_output()
      return
   end

   if not stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
      clear_think_output()
      return
   end

   if radiant.entities.is_standing_on_ladder(entity) then
      -- We generally want to prohibit combat on ladders. This case is particularly unfair,
      -- because the ranged unit can attack, but melee units can't find an adjacent to retaliate.
      clear_think_output()
      return
   end

   if not self._ready then
      self._ready = true
      ai:set_think_output()
   end
end

function CheckEntityTargetableDarts:stop_thinking(ai, entity, args)
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

return CheckEntityTargetableDarts