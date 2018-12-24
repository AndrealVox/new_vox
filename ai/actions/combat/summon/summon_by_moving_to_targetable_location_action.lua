local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3

local SummonByMovingToTargetableLocation = class()

SummonByMovingToTargetableLocation.name = 'summon by moving to targetable location'
SummonByMovingToTargetableLocation.does = 'stonehearth:combat:attack'
SummonByMovingToTargetableLocation.args = {
   target = Entity
}
SummonByMovingToTargetableLocation.version = 2
SummonByMovingToTargetableLocation.priority = 3
SummonByMovingToTargetableLocation.weight = 1

local ai = stonehearth.ai

return ai:create_compound_action(SummonByMovingToTargetableLocation)
   :execute('stonehearth:combat:abort_on_leash_changed')
   :execute('stonehearth:combat:move_to_targetable_location', {
      target = ai.ARGS.target
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('box_o_vox:combat:execute_summon', {
      target = ai.ARGS.target,
   })
