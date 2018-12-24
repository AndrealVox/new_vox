local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('combat')

local ExecuteSummon = class()

ExecuteSummon.name = 'execute summon'
ExecuteSummon.does = 'box_o_vox:combat:execute_summon'
ExecuteSummon.args = {
    target = Entity
}
ExecuteSummon.version = 2
ExecuteSummon.priority = 1
ExecuteSummon.weight = 1

function ExecuteSummon:start_thinking(ai, entity, args)
    local weapon = stonehearth.combat:get_main_weapon(entity)
    
    if not weapon or not weapon:is_valid() then
        return
    end
    
    self._weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
    
    self._summon_types = stonehearth.combat:get_combat_actions(entity, 'box_o_vox:combat:summon_spells')
    
    if not next(self._summon_types) then
        -- no summon types
        log:error('no summon types')
        return
    end
    
    local equipment_data = stonehearth.combat:get_equipment_data(entity, 'box_o_vox:summon_data')
    -- get summon uri from an equipped skill or the main weapon
    self._summon_uri = equipment_data and equipment_data.summon_uri or
                        self._weapon_data and self._weapon_data.summon_uri
    
    self:_choose_summon_action(ai, entity, args)
end

function ExecuteSummon:_choose_summon_action(ai, entity, args)
    
    self._summon_info = stonehearth.combat:choose_attack_action(entity, self._summon_types)
    
    if self._summon_info then
        ai:set_think_output()
        return true
    end
    
    self._think_timer = stonehearth.combat:set_timer("ExecuteSummon waiting for cooldown", 1000,
    function()
        self._think_timer = nil
        self:_choose_summon_action(ai, entity, args)
        end)
end

function ExecuteSummon:stop_thinking(ai, entity, args)
    if self._think_timer then
        self._think_timer:destroy()
        self._think_timer = nil
    end
    
    self._summon_types = nil
end

function ExecuteSummon:run(ai, entity, args)
    local target = args.target
    ai:set_status_text_key('box_o_vox:ai.actino.status_text.summoning', {target = target})
    log:error('wow it made it here')
    if radiant.entities.is_standing_on_ladder(entity) then
        ai:abort('Cannot summon while standing on ladder')
    end
    
    local weapon = stonehearth.combat:get_main_weapon(entity)
    if not weapon or not weapon:is_valid() then
        log:warning('%s no longer has valid weapon')
        ai:abort('summoner no longer has a valid weapon')
    end
    
    if not stonehearth.combat:in_range(entity, args.target, weapon) then
        ai:abort('Target no longer in range of cast')
        return
    end
    
    radiant.entities.turn_to_face(entity, target)
    
    stonehearth.combat:start_cooldown(entity, self._summon_info)
    stonehearth.combat:set_assisting(entity, true)
    
    ai:unprotect_argument(target)
    
    local summon_cast_time = self._summon_info.time_to_impact
    self._in_progress_summon = radiant.effects.run_effect(entity,'stonehearth:effects:firepit_effect:green')
    
    self._summon_impact_timer = stonehearth.combat:set_timer("Enemy in sight do Summon", summon_cast_time,
    function()
        if not entity:is_valid() or not target:is_valid() then
            return
        end
        
        self:destroy_summon_effect()
        
        self:_summon(entity, target, self._weapon_data)
        end)
    
    ai:execute('stonehearth:run_effect', {effect = self._summon_info.effect})
end

function ExecuteSummon:stop(ai, entity, args)
    if self._summon_impact_timer then
        self._summon_impact_timer:destroy()
        self._summon_impact_timer = nil
    end
    self:destroy_summon_effect()
    self._heal_info = nil
    stonehearth.combat:set_assisting(entity, false)
end

function ExecuteSummon:destroy_summon_effect()
    if self._in_progress_summon then
        self._in_progress_summon:stop()
        self._in_progress_summon = nil
    end
end

function ExecuteSummon:_summon(summoner, target, weapon_data)
    if not target:is_valid() then
        return
    end
    local summon = self:_create_summon(summoner, target, self._summon_uri)
    
    local summon_info = self._summon_info
    
    
    local destroy_trace
    destroy_trace = radiant.events.listen(summon, 'radiant:entity:pre_destroy', function()
        if summon:is_valid() then
            --radiant.effects.run_effect(summon, 'stonehearth:effects:firepit_effect:green')
        end
        
        if destroy_trace then
            destroy_trace:destroy()
            destroy_trace = nil
        end
    end)
end

function ExecuteSummon:_create_summon(summoner, target, summon_uri)
    summon_uri = summon_uri or 'box_o_vox:entities:summon:skeleton' -- default summon is skeleton
    local json = radiant.resources.load_json(summon_uri, true, true)
    local npc_player_id = 'summon'
    local origin = radiant.entities.get_world_grid_location(summoner)
    local summon_vector = self:_get_world_location(summoner, target)
    local summon_info = {
        tuning = json.tuning,
        from_population = {
            location = Point3(0,0,0)+summon_vector,
            role = json.role
        }
    }
    local population = stonehearth.population:get_population(npc_player_id)
    radiant.assert(population, 'population does not exist', npc_player_id)
    local summons = game_master_lib.create_citizens(population, summon_info, origin)
    
    for _, summon in pairs(summons) do
        radiant.entities.set_player_id(summon, 'player_1') 
        radiant.entities.add_buff(summon,'box_o_vox:data:buffs:summon_timer')
    local SUMMON_TIME = '1h'
    stonehearth.calendar:set_timer('despawn summon', SUMMON_TIME, function()
         if radiant.entities.exists(summon) then
            radiant.entities.destroy_entity(summon)
         end
      end)
        --radiant.effects.run_effect(summon, 'stonehearth:effects:firepit_effect:green')
    end
    return summons
end

function ExecuteSummon:_get_world_location(summoner, target)
    local summoner_location = radiant.entities.get_location(summoner)
    log:error('%s sum_loc', summoner_location)
    local target_location = radiant.entities.get_location(target)
    log:error('%s tar_loc', target_location)
    local vector = target_location - summoner_location
    log:error('%s vector', vector)
    local distance = vector:length()
    vector = vector/2
    log:error('%s divide vector', vector)
    return vector
end
    
return ExecuteSummon