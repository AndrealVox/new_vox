local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3

local SummonByPathingToTarget = class()

SummonByPathingToTarget.name = 'summon by pathing to target'
SummonByPathingToTarget.does = 'stonehearth:combat:attack'
SummonByPathingToTarget.args = {
   target = Entity
}
SummonByPathingToTarget.version = 2
SummonByPathingToTarget.priority = 2
SummonByPathingToTarget.weight = 1

local ai = stonehearth.ai

return ai:create_compound_action(SummonByPathingToTarget)
   :execute('stonehearth:combat:abort_on_leash_changed')
   :execute('stonehearth:combat:chase_entity_until_targetable', {
      target = ai.ARGS.target
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('box_o_vox:combat:execute_summon', {
      target = ai.ARGS.target,
   })
