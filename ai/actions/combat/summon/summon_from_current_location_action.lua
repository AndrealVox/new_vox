local Entity = _radiant.om.Entity

local SummonFromCurrentLocation = class()

SummonFromCurrentLocation.name = 'summon from current location'
SummonFromCurrentLocation.does = 'stonehearth:combat:attack'
SummonFromCurrentLocation.args = {
   target = Entity
}
SummonFromCurrentLocation.version = 2
SummonFromCurrentLocation.priority = 4
SummonFromCurrentLocation.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(SummonFromCurrentLocation)
   :execute('stonehearth:combat:check_entity_targetable', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('box_o_vox:combat:execute_summon', {
      target = ai.ARGS.target,
   })
