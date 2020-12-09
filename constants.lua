local constants = require 'stonehearth.constants'

local constants_json = radiant.resources.load_json('stonehearth:data:constants')
if not constants then
    if constants_json.constants then
        constants = constants_json.constants
    end
end

return constants
