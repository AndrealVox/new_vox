local Entity = _radiant.om.Entity

local AttackRanged_DartsMoveToLOS = radiant.class()

AttackRanged_DartsMoveToLOS.name = 'attack ranged darts move to targetable location'
AttackRanged_DartsMoveToLOS.does = 'stonehearth:combat:attack'
AttackRanged_DartsMoveToLOS.args = {
   target = Entity
}
AttackRanged_DartsMoveToLOS.priority = 0.3
AttackRanged_DartsMoveToLOS.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(AttackRanged_DartsMoveToLOS)
   :execute('stonehearth:combat:abort_on_leash_changed')
   :execute('box_o_vox:combat:move_to_targetable_location', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('stonehearth:combat:attack_ranged', {
      target = ai.ARGS.target,
   })