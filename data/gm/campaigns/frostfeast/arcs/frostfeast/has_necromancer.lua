local Box_O_Vox_has_necromancer = class()

function Box_O_Vox_has_necromancer:start(ctx, info)
	local necromancer_job = stonehearth.job:get_job_info(ctx.player_id, "box_o_vox:jobs:necromancer")
	if necromancer_job and necromancer_job:get_highest_level()>0 then
		return true
	end
	return false
end

return Box_O_Vox_has_necromancer