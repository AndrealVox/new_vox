local NecromancerClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
local CraftingJob = require 'stonehearth.jobs.crafting_job'
radiant.mixin(NecromancerClass, CombatJob)
radiant.mixin(NecromancerClass, CraftingJob)

--- Public functions, required for all classes

function NecromancerClass:initialize()
   CraftingJob.initialize(self)
   CombatJob.initialize(self)
   self._sv.max_num_workers = {}
   self._sv.max_num_attended_hearthlings = 2
end

--Always do these things
function NecromancerClass:activate()
   CraftingJob.activate(self)
   CombatJob.activate(self)

   if self._sv.is_current_class then
      self:_register_with_town()
   end

   self.__saved_variables:mark_changed()
end

-- Call when it's time to promote someone to this class
function NecromancerClass:promote(json_path)
   CombatJob.promote(self, json_path)
   CraftingJob.promote(self, json_path)
   self._sv.max_num_workers = { workers = 0 }
   self._sv.max_num_attended_hearthlings = self._job_json.initial_num_attended_hearthlings or 2
   if self._sv.max_num_attended_hearthlings > 0 then
      self:_register_with_town()
   end
   self.__saved_variables:mark_changed()
end

function NecromancerClass:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_workers)
   end
end

-- Called when destroying this entity, we should alo remove ourselves
function NecromancerClass:_unregister_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_medic(self._sv._entity)
   end
end

function NecromancerClass:_create_listeners()
   CombatJob._create_listeners(self)
   CraftingJob._create_listeners(self)
   self._on_summon_listener = radiant.events.listen(self._sv._entity, 'box_o_vox:necromancer:has_summoned', self, self._on_summon)
end

function NecromancerClass:_remove_listeners()
   CraftingJob._remove_listeners(self)
   CombatJob._remove_listeners(self)
   if self._on_summon_listener then
      self._on_summon_listener:destroy()
      self._on_summon_listener = nil
   end
end

function NecromancerClass:_on_summon(args)
   self:_add_exp('summon')
   print('no exp dude')
end

-- Get xp reward using key. Xp rewards table specified in necromancer description file
function NecromancerClass:_add_exp(key)
   local exp = self._xp_rewards[key]
   if exp then
      self._job_component:add_exp(exp)
      print("exp = "..exp)
   end
end

-- Call when it's time to demote
function NecromancerClass:demote()
   self:_unregister_with_town()
   CombatJob.demote(self)
   CraftingJob.demote(self)
end

-- Called when destroying this entity
-- Note we could get destroyed without being demoted
-- So remove ourselves from town just in case
function NecromancerClass:destroy()
   if self._sv.is_current_class then
      self:_unregister_with_town()
   end
   CombatJob.destroy(self)
   CraftingJob.destroy(self)
end

function NecromancerClass:increase_max_placeable_workers(perk_json)
   self._sv.max_num_workers = { workers = perk_json.max_num_workers }
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

return NecromancerClass