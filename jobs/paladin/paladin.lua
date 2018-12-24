local PaladinClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
radiant.mixin(PaladinClass, CombatJob)
return PaladinClass
