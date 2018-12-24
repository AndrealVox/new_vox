local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('summon')

local SummonComponent = class()

function SummonComponent:initialize()
    self._owner = nil
    self._type = nil
end

function SummonComponent:create()
    local mob = self._entity:add_component('mob')
    mob:set_has_free_will(true)
    self._mob = mob
    
    local attr_component = self._entity:add_component("stonehearth:attributes")
    attr_component:set_attribute(self._entity, 'body', 5)
    attr_component:set_attribute(self._entity, 'spirit', 5)
end

function SummonComponent:set_owner(summoner)
    --does nothing atm
end
function SummonComponent:set_type(summon_type)
    --does nothing atm
end
function SummonComponent:destroy()
end

function SummonComponent:start()
    radiant.events.trigger_async(self._entity, 'box_o_vox:combat:summon_cast')
    if not radiant.entities.has_buff(self._entity, 'box_o_vox:data:buffs:summon_timer') then
        radiant.entities.add_buff(self._entity, 'box_o_vox:data:buffs:summon_timer')
    end
end