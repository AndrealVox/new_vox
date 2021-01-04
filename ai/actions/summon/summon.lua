local Entity = _radiant.om.Entity

local SummonSomething = class()

SummonSomething.name = 'attack ranged'
SummonSomething.does = 'stonehearth:combat:attack_ranged'
SummonSomething.args = {
target = Entity
}
SummonSomething.version = 2
SummonSomething.priority = 10
SummonSomething.weight = 1

function SummonSomething:start_thinking(ai, entity, args)
	-- refetch every start_thinking as the set of actions may have changed
	self._attack_types = stonehearth.combat:get_combat_actions(entity, 'stonehearth:combat:ranged_attacks')

	self:_choose_attack_action(ai, entity, args)
end

function SummonSomething:_choose_attack_action(ai, entity, args)
	self._attack_info = stonehearth.combat:choose_attack_action(entity, self._attack_types)

	if self._attack_info then
		ai:set_think_output()
		return
	end

	-- choose_attack_action might have complex logic, so just wait 1 second and try again
	-- instead of trying to guess which coolodowns to track
	self._think_timer = stonehearth.combat:set_timer("SummonSomething waiting for cooldown", 1000, function()
		self._think_timer = nil
		self:_choose_attack_action(ai, entity, args)
		end)
end

function SummonSomething:stop_thinking(ai, entity, args)
	if self._think_timer then
		self._think_timer:destroy()
		self._think_timer = nil
	end

	self._attack_types = nil
end

function SummonSomething:run(ai, entity, args)
	local target = args.target

	ai:set_status_text_key('box_o_vox:ai.actions.status_text.summoning', { target = target })

	if radiant.entities.is_standing_on_ladder(entity) then
		-- We generally want to prohibit combat on ladders. This case is particularly unfair,
		-- because the ranged unit can attack, but melee units can't find an adjacent to retaliate.
		ai:abort('Cannot attack attack while standing on ladder')
	end

	-- Look at target enemy.
	radiant.entities.turn_to_face(entity, target)

	-- Start a cooldown.
	stonehearth.combat:start_cooldown(entity, self._attack_info)

	-- the target might die when we attack them, so unprotect now!
	ai:unprotect_argument(target)

	local spirit_walker_controller = entity:get_component('stonehearth:job'):get_curr_job_controller()
	spirit_walker_controller[self._attack_info.name](spirit_walker_controller, self._attack_info.active_frame, target)

	-- Show some particles effects.
	radiant.effects.run_effect(entity, "box_o_vox:data:effects:summon_necronomicon")
	-- Play the animation found in the json.
	ai:execute('stonehearth:run_effect', { effect = self._attack_info.effect })
end

function SummonSomething:stop(ai, entity, args)
	self._attack_info = nil
end

return SummonSomething