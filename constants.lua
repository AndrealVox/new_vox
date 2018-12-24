local constants = require 'stonehearth.constants'

local constants_json = radiant.resources.load_json('stonehearth:data:constants')
if not constants then
    if constants_json.constants then
        constants = constants_json.constants
    end
end

constants.food_quality_priorities = {}
constants.food_quality_priorities[constants.food_qualities.UNPALATABLE] = 0
constants.food_quality_priorities[constants.food_qualities.RAW_BLAND] = 1
constants.food_quality_priorities[constants.food_qualities.RAW_AVERAGE] = 2
constants.food_quality_priorities[constants.food_qualities.RAW_TASTY] = 3
constants.food_quality_priorities[constants.food_qualities.TASTY] = 4
constants.food_quality_priorities[constants.food_qualities.COOKED_BLAND] = 5
constants.food_quality_priorities[constants.food_qualities.COOKED_AVERAGE] = 6
constants.food_quality_priorities[constants.food_qualities.COOKED_TASTY] = 7

-- Food Quality to Food Thoughts
constants.food_quality_thoughts = {}
constants.food_quality_thoughts[constants.food_qualities.UNPALATABLE] = { constants.thoughts.food_quality.UNPALATABLE }
constants.food_quality_thoughts[constants.food_qualities.RAW_BLAND] = { constants.thoughts.food_quality.RAW,
                                                                        constants.thoughts.food_quality.BLAND }
constants.food_quality_thoughts[constants.food_qualities.RAW_AVERAGE] = { constants.thoughts.food_quality.RAW }
constants.food_quality_thoughts[constants.food_qualities.RAW_TASTY] = { constants.thoughts.food_quality.RAW,
                                                                        constants.thoughts.food_quality.TASTY }
constants.food_quality_thoughts[constants.food_qualities.TASTY] = { constants.thoughts.food_quality.TASTY }
constants.food_quality_thoughts[constants.food_qualities.COOKED_BLAND] = { constants.thoughts.food_quality.COOKED,
                                                                           constants.thoughts.food_quality.BLAND }
constants.food_quality_thoughts[constants.food_qualities.COOKED_AVERAGE] = { constants.thoughts.food_quality.COOKED }
constants.food_quality_thoughts[constants.food_qualities.COOKED_TASTY] = { constants.thoughts.food_quality.COOKED,
                                                                           constants.thoughts.food_quality.TASTY }

return constants
