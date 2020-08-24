box_o_vox = {
   constants = require 'constants'
}
function box_o_vox:_on_biome_set(e)
	if e.biome_uri ~= "box_o_vox:biome:boxland" then
		return
	end
    
    local CustomHeightMapRenderer = require('services.server.world_generation.custom_height_map_renderer')
    local HeightMapRenderer = radiant.mods.require('stonehearth.services.server.world_generation.height_map_renderer')
    radiant.mixin(HeightMapRenderer, CustomHeightMapRenderer)
end

radiant.events.listen_once(radiant, 'stonehearth:biome_set', box_o_vox, box_o_vox._on_biome_set)

return box_o_vox