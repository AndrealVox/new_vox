local Entity = _radiant.om.Entity

local AttackRanged_DartsPathToTarget = radiant.class()

AttackRanged_DartsPathToTarget.name = 'attack ranged darts path to target'
AttackRanged_DartsPathToTarget.does = 'stonehearth:combat:attack'
AttackRanged_DartsPathToTarget.args = {
   target = Entity
}
AttackRanged_DartsPathToTarget.priority = 0.2
AttackRanged_DartsPathToTarget.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(AttackRanged_DartsPathToTarget)
   :execute('stonehearth:combat:abort_on_leash_changed')
   :execute('box_o_vox:combat:chase_entity_until_targetable', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('stonehearth:combat:attack_ranged', {
      target = ai.ARGS.target,
   })
