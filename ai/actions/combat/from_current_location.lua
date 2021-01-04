local Entity = _radiant.om.Entity

local AttackRangedDartsFromCurrentLocation = radiant.class()

AttackRangedDartsFromCurrentLocation.name = 'attack ranged darts from currrent location'
AttackRangedDartsFromCurrentLocation.does = 'stonehearth:combat:attack'
AttackRangedDartsFromCurrentLocation.args = {
   target = Entity
}
AttackRangedDartsFromCurrentLocation.priority = 0.4
AttackRangedDartsFromCurrentLocation.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(AttackRangedDartsFromCurrentLocation)
   :execute('box_o_vox:combat:check_entity_targetable', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('stonehearth:combat:attack_ranged', {
      target = ai.ARGS.target,
   })
