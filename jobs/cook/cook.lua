local CraftingJob = require 'jobs.crafting_job'

local CookClass = class()
radiant.mixin(CookClass, CraftingJob)

return CookClass
