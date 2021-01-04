local CombatJob = require 'stonehearth.jobs.combat_job'
local CraftingJob = require 'stonehearth.jobs.crafting_job'
local SummonerClass = class()
radiant.mixin(SummonerClass, CombatJob)
radiant.mixin(SummonerClass, CraftingJob)
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local rng = _radiant.math.get_default_rng()

function SummonerClass:initialize()
   CraftingJob.initialize(self)
   CombatJob.initialize(self)
   self._sv.max_num_workers = {}
end

function SummonerClass:promote(json_path)
   CombatJob.promote(self, json_path)
   CraftingJob.promote(self, json_path)
   self._sv.max_num_workers = { workers = 0 }
   self.__saved_variables:mark_changed()
end

function SummonerClass:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_workers)
   end
end

function SummonerClass:_create_listeners()
	CombatJob._create_listeners(self)
	CraftingJob._create_listeners(self)
	self.summons = radiant.resources.load_json(self._job_json.summons)
end

function SummonerClass:_remove_spirit_listener()
	if self.spirit_listener then
		self.spirit_listener:destroy()
		self.spirit_listener = nil
	end
end

function SummonerClass:_remove_listeners()
	CombatJob._remove_listeners(self)
	CraftingJob._remove_listeners(self)
	self:_remove_spirit_listener()
end

function SummonerClass:_on_summon(args)
   self:_add_exp('summon')
   print('no exp dude')
end

-- Get xp reward using key. Xp rewards table specified in necromancer description file
function SummonerClass:_add_exp(key)
   local exp = self._xp_rewards[key]
   if exp then
      self._job_component:add_exp(exp)
      print("exp = "..exp)
   end
end

function SummonerClass:get_menacing_enemy_list_ascending(all_entities)
	--return a list of enemies in order of low to high menace
	local enemies = {}
	local not_menacing = {}
	for _, enemy in pairs(all_entities) do
		local is_hostile = stonehearth.player:are_entities_hostile(enemy, self._sv._entity)
		if is_hostile and radiant.entities.has_free_will(enemy) then
			if radiant.entities.get_attribute(enemy, "menace")>1 then
				table.insert(enemies, enemy)
			else
				table.insert(not_menacing, enemy)
			end
		end
	end
	table.sort(enemies, function(a, b)
		return radiant.entities.get_attribute(a, "menace") < radiant.entities.get_attribute(b, "menace")
	end)
	if #enemies < 1 then
		--no menacing enemies? ok, grab the rest
		enemies = not_menacing
	end
	return enemies
end

function SummonerClass:summon_bone_wolf(delay)
	local uris, amount = self:get_summons_uris("summon_bone_wolf")
	self:summon_animals(delay, uris, amount)
end

function SummonerClass:summon_zombie(delay)
	local uris, amount = self:get_summons_uris("summon_zombie")
	self:summon_animals(delay, uris, amount)
end

function SummonerClass:summon_golem(delay)
	local uris, amount = self:get_summons_uris("summon_golem")
	self:summon_animals(delay, uris, amount)
end

function SummonerClass:summon_zilla(delay)
	local uris, amount = self:get_summons_uris("summon_zilla")
	self:summon_animals(delay, uris, amount)
end

function SummonerClass:summon_necro(delay)
	local uris, amount = self:get_summons_uris("summon_necro")
	self:summon_animals(delay, uris, amount)
end

function SummonerClass:summon_skeleton(delay)
	local uris, amount = self:get_summons_uris("summon_skeleton")
	self:summon_animals(delay, uris, amount)
end

function SummonerClass:get_summons_uris(category)
	local uris = {}
	local amount = self.summons[category].quantity
	for entity, active in pairs(self.summons[category].entities) do
		if active then
			table.insert(uris, entity)
		end
	end
	return uris, amount
end

function SummonerClass:summon_animals(delay, uris, amount, has_attributes)
	for i=1, amount do
		local uri = uris and uris[rng:get_int(1,#uris)]
		local offset = (0.1*i+1) - (0.1*amount)/2
		local summoning_delay = (delay * 33.3 * offset)
		stonehearth.combat:set_timer("SummonerClass summoning_delay: "..i, summoning_delay, function()
			self:create_animal(uri, has_attributes)
		end)
	end
end

function SummonerClass:create_animal(url, has_attributes)
	local entity_location = radiant.entities.get_world_location(self._sv._entity)
	local player_id = radiant.entities.get_player_id(self._sv._entity)

	local animal = radiant.entities.create_entity(url, {owner = player_id})
	if not has_attributes then
		self:copy_menace(animal)
	end
	local location = radiant.terrain.find_placement_point(entity_location, 3, 5, self._sv._entity, nil, true)
	radiant.terrain.place_entity_at_exact_location(animal, location)

	radiant.effects.run_effect(animal, "box_o_vox:effects:summon")

	radiant.entities.add_buff(animal, "box_o_vox:buffs:despawn:in_2h")
end

function SummonerClass:copy_menace(animal)
	radiant.entities.set_attribute(animal, "menace", radiant.entities.get_attribute(self._sv._entity, "menace") +1)
	radiant.entities.set_attribute(animal, "courage", radiant.entities.get_attribute(self._sv._entity, "courage") +1)
end

function SummonerClass:increase_max_placeable_workers(perk_json)
   self._sv.max_num_workers = { workers = perk_json.max_num_workers }
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

return SummonerClass