local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
local SimplexNoise = require 'stonehearth.lib.math.simplex_noise'
local FilterFns = require 'stonehearth.services.server.world_generation.filter.filter_fns'
local water_shallow = 'water_1'
local water_deep = 'water_2'
local CustomLandscaper = class()

local Astar = require 'services.server.world_generation.astar'
local noise_height_map = {} --this noise is to mess with the astar to avoid straight rivers
local log = radiant.log.create_logger('meu_log')


function CustomLandscaper:mark_water_bodies(elevation_map, feature_map)
	local mod_name = stonehearth.world_generation:get_biome_alias()
	--mod_name is the mod that has the current biome
	local colon_pos = string.find (mod_name, ":", 1, true) or -1
	mod_name = "mark_water_bodies_" .. string.sub (mod_name, 1, colon_pos-1)
	if self[mod_name]~=nil then
		self[mod_name](self, elevation_map, feature_map)
	else
		self:mark_water_bodies_original(elevation_map, feature_map)
	end
end

function CustomLandscaper:mark_water_bodies_original(elevation_map, feature_map)
	local rng = self._rng
	local biome = self._biome
	local config = self._landscape_info.water.noise_map_settings
	local modifier_map, density_map = self:_get_filter_buffers(feature_map.width, feature_map.height)
	--fill modifier map to push water bodies away from terrain type boundaries
	local modifier_fn = function (i,j)
		if self:_is_flat(elevation_map, i, j, 1) then
			return 0
		else
			return -1*config.range
		end
	end
	--use density map as buffer for smoothing filter
	density_map:fill(modifier_fn)
	FilterFns.filter_2D_0125(modifier_map, density_map, modifier_map.width, modifier_map.height, 10)
	--mark water bodies on feature map using density map and simplex noise
	local old_feature_map = Array2D(feature_map.width, feature_map.height)
	for j=1, feature_map.height do
		for i=1, feature_map.width do
			local occupied = feature_map:get(i, j) ~= nil
			if not occupied then
				local elevation = elevation_map:get(i, j)
				local terrain_type = biome:get_terrain_type(elevation)
				local value = SimplexNoise.proportional_simplex_noise(config.octaves,config.persistence_ratio, config.bandlimit,config.mean[terrain_type],config.range,config.aspect_ratio, self._seed,i,j)
				value = value + modifier_map:get(i,j)
				if value > 0 then
					local old_value = feature_map:get(i, j)
					old_feature_map:set(i, j, old_value)
					feature_map:set(i, j, water_shallow)
				end
			end
		end
	end
	self:_remove_juts(feature_map)
	self:_remove_ponds(feature_map, old_feature_map)
	self:_fix_tile_aligned_water_boundaries(feature_map, old_feature_map)
	self:_add_deep_water(feature_map)
end

function CustomLandscaper:mark_water_bodies_box_o_vox(elevation_map, feature_map)
	local rng = self._rng
	local biome = self._biome

	noise_height_map.width = feature_map.width
	noise_height_map.height = feature_map.height
	for j=1, feature_map.height do
		for i=1, feature_map.width do
			local elevation = elevation_map:get(i, j)
			local terrain_type = biome:get_terrain_type(elevation)

			local offset = (j-1)*feature_map.width+i
			--creates and set the points
			noise_height_map[offset] = {}
			noise_height_map[offset].x = i
			noise_height_map[offset].y = j
			noise_height_map[offset].plains = terrain_type == "plains"
			if terrain_type == "plains" then
				noise_height_map[offset].noise = rng:get_int(1,100)
			else
				noise_height_map[offset].noise = 10000
			end
		end
	end
	self:_smooth_random()
	self:_add_rivers(feature_map)
end

function CustomLandscaper:_smooth_random()
	--temp heightmap
	local smooth_height_map = Array2D(noise_height_map.width, noise_height_map.height)
	for j=2, noise_height_map.height-1 do
		for i=2, noise_height_map.width-1 do
			local smooth = 0
			--sum all points in the 3x3 grid (the center twice, heavy weight center)
			for smooth_y=j-1, j+1 do
				for smooth_x=i-1, i+1 do
					local offset = (smooth_y-1)*noise_height_map.width+smooth_x
					smooth = smooth + noise_height_map[offset].noise
					if smooth_y == j and smooth_x == i then
						--center is doubled
						smooth = smooth + noise_height_map[offset].noise
					end
				end
			end
			smooth = smooth / 10
			smooth_height_map:set(i, j, smooth)
		end
	end
	for j=2, noise_height_map.height-1 do
		for i=2, noise_height_map.width-1 do
			local offset = (j-1)*noise_height_map.width+i
			--apply the smoothed points from the temp heightmap back to the main heightmap
			noise_height_map[offset].noise = smooth_height_map:get(i,j)
		end
	end
end

function CustomLandscaper:_add_rivers(feature_map)
	local x,y,offset,x2,y2,offset2 --random start and end points
	local distance
	for rivers=1, 6 do
		repeat
			--start point
			x = self._rng:get_int(1, feature_map.width)
			y = self._rng:get_int(1, feature_map.height)
			offset = (y-1)*feature_map.width+x
		until
			noise_height_map[offset].plains and
			--picks only when near the border
			((x<feature_map.width*0.2 or x>feature_map.width*0.8) or
			(y<feature_map.height*0.2 or y>feature_map.height*0.8))

		repeat
			--end point
			x2 = self._rng:get_int(1, feature_map.width)
			y2 = self._rng:get_int(1, feature_map.height)
			offset2 = (y2-1)*feature_map.width+x2

			--avoid getting 2 points close to each other
			distance = math.sqrt( (x2-x)*(x2-x)+(y2-y)*(y2-y) )
			-- log:error('River %d. Trying end point', rivers)
		until
			distance>(feature_map.height/2) and
			noise_height_map[offset2].plains and
			((x2<feature_map.width*0.2 or x2>feature_map.width*0.8) or
			(y2<feature_map.height*0.2 or y2>feature_map.height*0.8))

		self:draw_river(noise_height_map[offset], noise_height_map[offset2], feature_map, rivers)
	end
end

function CustomLandscaper:draw_river(start,goal,feature_map, size)
	local path = Astar.path ( start, goal, noise_height_map, true )

	if not path then
		log:error('Error. No valid river path found!')
	else
		for i, node in ipairs ( path ) do
			if size%2 == 0 then --wide and deep rivers
				feature_map:set(node.x, node.y, water_deep)
				self:add_shallow_neighbors(node.x, node.y, feature_map)
			else --narrow and shallow rivers
				if feature_map:get(node.x, node.y) ~= water_deep then
					feature_map:set(node.x, node.y, water_shallow)
				end
			end
			self:sink_noise(node.x, node.y)
		end
	end
end

function CustomLandscaper:add_shallow_neighbors(x,y, feature_map)
	for j=y-1, y+1 do
		for i=x-1, x+1 do
			local feature_name = feature_map:get(i, j)
			if feature_map:in_bounds(i,j) and (not self:is_water_feature(feature_name)) and self:is_plains(i,j)  then
				feature_map:set(i, j, water_shallow)
				self:sink_noise(i,j)
			end
		end
	end
end

function CustomLandscaper:is_plains(x,y)
	local offset = (y-1)*noise_height_map.width+x
	return noise_height_map[offset].plains
end

function CustomLandscaper:sink_noise(x,y)
	local offset = (y-1)*noise_height_map.width+x
	--sink the "noise", so next rivers are "attracted" to these points (converging rivers)
	noise_height_map[offset].noise = noise_height_map[offset].noise /2
end

return CustomLandscaper