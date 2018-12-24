local constants = require 'constants'
local Entity = _radiant.om.Entity

local SummonAfterCooldown = class()
SummonAfterCooldown.name = 'summon after cooldown'
SummonAfterCooldown.does = 'stonehearth:combat:attack_after_cooldown'
SummonAfterCooldown.args = {
    target = Entity
}
SummonAfterCooldown.version = 2
SummonAfterCooldown.priority = 1

local ai = stonehearth.ai
return ai:create_compound_action(SummonAfterCooldown)
    :execute('stonehearth:combat:wait_for_global_attack_cooldown')
    :execute('stonehearth:combat:attack', {target = ai.ARGS.target })
    :execute('stonehearth:combat:set_global_attack_cooldown')