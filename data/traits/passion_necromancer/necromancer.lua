local Necromancer = class()

local log = radiant.log.create_logger('vox')
function Necromancer:initialize()
   self._sv._entity = nil
   self._sv._uri = nil
   self._sv._parent = nil
end

function Necromancer:create(entity, uri, parent, args)
   self._sv._entity = entity
   self._sv._uri = uri
   self._sv._parent = parent
end

function Necromancer:activate()
   local json = radiant.resources.load_json(self._sv._uri)
   local population = stonehearth.population:get_population(self._sv._entity:get_player_id())
   
   self._job_changed_listener = radiant.events.listen(self._sv._entity, 'stonehearth:job_changed', self, self._adjust_thought)

   self.pop_listener = radiant.events.listen_once(population, 'stonehearth:population:citizen_count_changed', function()
      if not self._sv._entity:get_component('stonehearth:unit_info')._sv._made_necromancer then
         local options = {}
         options.dont_drop_talisman = true
         options.skip_visual_effects = true
         self._sv._entity:get_component('stonehearth:job'):promote_to('box_o_vox:jobs:necromancer', options)
         self._sv._entity:get_component('stonehearth:unit_info')._sv._made_necromancer = true
      end
   end)
   
end

function Necromancer:post_activate()
   self:_load_and_display_and_adjust()
end

function Necromancer:destroy()
   self._sv._entity:get_component('stonehearth:equipment'):equip_item('box_o_vox:jobs:worker:boxling_outfit')
   self.pop_listener:destroy()
   if self._job_changed_listener then
      self._job_changed_listener:destroy()
      self._job_changed_listener = nil
   end

   radiant.entities.remove_thought(self._sv._entity, 'stonehearth:thoughts:traits:loves_their_job')
end

function Necromancer:_load_data()
   local json = radiant.resources.load_json(self._sv._uri)
   self._passion_job_uri = json.data.job_uri
end

function Necromancer:_set_job_display()
   local json = radiant.resources.load_json(self._passion_job_uri)
   self._sv._parent:add_i18n_data('passion_job', json.display_name)
end

function Necromancer:_load_and_display_and_adjust()
   self:_load_data()
   self:_set_job_display()
   self:_adjust_thought()
end

function Necromancer:_adjust_thought()
   -- grab the job component
   local job_component = self._sv._entity:get_component('stonehearth:job')
   local job_uri = job_component and job_component:get_job_uri()

   if not job_uri or not self._passion_job_uri then
      return
   end

   if self._passion_job_uri == job_uri then
      radiant.entities.add_thought(self._sv._entity, 'stonehearth:thoughts:traits:loves_their_job')
   else
      radiant.entities.remove_thought(self._sv._entity, 'stonehearth:thoughts:traits:loves_their_job')
   end
end

return Necromancer
