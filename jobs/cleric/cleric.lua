local ClericClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
local CraftingJob = require 'stonehearth.jobs.crafting_job'
radiant.mixin(ClericClass, CombatJob)
radiant.mixin(ClericClass, CraftingJob)

--- Public functions, required for all classes

function ClericClass:initialize()
    CraftingJob.initialize(self)
   CombatJob.initialize(self)
   self._sv.max_num_attended_hearthlings = 2
end

--Always do these things
function ClericClass:create(entity)
    CraftingJob.create(self, entity)
    CombatJob.create(self, entity)
end

function ClericClass:restore()
   if self._sv.is_current_class then
      self:_register_with_town()
   end
end

function ClericClass:promote(json_path, options)
   CraftingJob.promote(self, json_path, options)
    CombatJob.promote(self, json_path, options)
   self._sv.max_num_attended_hearthlings = self._job_json.initial_num_attended_hearthlings or 2
   if self._sv.max_num_attended_hearthlings > 0 then
      self:_register_with_town()
   end
   self.__saved_variables:mark_changed()
end

function ClericClass:increase_attended_hearthlings(args)
   self._sv.max_num_attended_hearthlings = args.max_num_attended_hearthlings
   self:_register_with_town() -- re-register with the town because number of max attended hearthlings is increased
   self.__saved_variables:mark_changed()
end

function ClericClass:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_medic(self._sv._entity, self._sv.max_num_attended_hearthlings)
   end
end

-- Called when destroying this entity, we should alo remove ourselves
function ClericClass:_unregister_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_medic(self._sv._entity)
   end
end

function ClericClass:_create_listeners()
   CombatJob._create_listeners(self)
   CraftingJob._create_listeners(self)
   self._on_heal_entity_listener = radiant.events.listen(self._sv._entity, 'stonehearth:healer:healed_entity', self, self._on_healed_entity)
   self._on_heal_entity_in_combat_listener = radiant.events.listen(self._sv._entity, 'stonehearth:healer:healed_entity_in_combat', self, self._on_healed_entity_in_combat)
end

function ClericClass:_remove_listeners()
    
   CraftingJob._remove_listeners(self)
   if self._on_heal_entity_listener then
      self._on_heal_entity_listener:destroy()
      self._on_heal_entity_listener = nil
   end
   CombatJob._remove_listeners(self)
   if self._on_heal_entity_in_combat_listener then
      self._on_heal_entity_in_combat_listener:destroy()
      self._on_heal_entity_in_combat_listener = nil
   end
end

function ClericClass:_on_healed_entity(args)
   local exp = self._xp_rewards['heal_entity']
   if exp then
      self._job_component:add_exp(exp)
   end
end

function ClericClass:_on_healed_entity_in_combat(args)
   local exp = self._xp_rewards['heal_entity_in_combat']
   if exp then
      self._job_component:add_exp(exp)
   end
end

-- Call when it's time to demote
function ClericClass:demote()
   self:_unregister_with_town()
   CombatJob.demote(self)
   CraftingJob.demote(self)
end

-- Called when destroying this entity
-- Note we could get destroyed without being demoted
-- So remove ourselves from town just in case
function ClericClass:destroy()
   if self._sv.is_current_class then
      self:_unregister_with_town()
   end

   CombatJob.destroy(self)
   CraftingJob.destroy(self)
end

return ClericClass