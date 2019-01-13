local Box_O_Vox_Clouds = class()
local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()
local default_clouds = "box_o_vox:effects:default_clouds"

function Box_O_Vox_Clouds:post_activate()
	self.json = radiant.resources.load_json("box_o_vox:data:weather_based_clouds", true, false)
	if stonehearth.weather and stonehearth.weather:get_current_weather() then
		self:apply_effects()
	end
	self.weather_switch_alarm = stonehearth.calendar:set_interval("changing clouds", "1h+1h", function()
		self:apply_effects()
		end)
end

function Box_O_Vox_Clouds:apply_effects()
	self:destroy_effect()
	if rng:get_int(1,100) <= 2 then
		local current_weather = stonehearth.weather:get_current_weather():get_uri()
		local chosen_clouds = self.json[current_weather] or default_clouds
		self.effect = radiant.effects.run_effect(self._entity, chosen_clouds)
	end
end

function Box_O_Vox_Clouds:destroy_effect()
	if self.effect then
		self.effect:stop()
		self.effect = nil
	end
end

function Box_O_Vox_Clouds:destroy()
	self:destroy_effect()
end

return Box_O_Vox_Clouds