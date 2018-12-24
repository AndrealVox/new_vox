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
function ClericClass:activate()
    CraftingJob.activate(self)
   CombatJob.activate(self)

   if self._sv.is_current_class then
      self:_register_with_town()
   end

   self.__saved_variables:mark_changed()
end

-- Call when it's time to promote someone to this class
function ClericClass:promote(json_path)
   CombatJob.promote(self, json_path)
   CraftingJob.promote(self, json_path)
   self._sv.max_num_attended_hearthlings = self._job_json.initial_num_attended_hearthlings or 2
   if self._sv.max_num_attended_hearthlings > 0 then
      self:_register_with_town()
   end
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
   CombatJob._remove_listeners(self)
   if self._on_heal_entity_listener then
      self._on_heal_entity_listener:destroy()
      self._on_heal_entity_listener = nil
   end
   if self._on_heal_entity_in_combat_listener then
      self._on_heal_entity_in_combat_listener:destroy()
      self._on_heal_entity_in_combat_listener = nil
   end
end

function ClericClass:_on_healed_entity(args)
   self:_add_exp('heal_entity')
end

function ClericClass:_on_healed_entity_in_combat(args)
   self:_add_exp('heal_entity_in_combat')
end

-- Get xp reward using key. Xp rewards table specified in cleric description file
function ClericClass:_add_exp(key)
   local exp = self._xp_rewards[key]
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