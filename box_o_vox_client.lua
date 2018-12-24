box_o_vox = {
   constants = require 'constants'
}

local player_service_trace = nil

local function check_override_ui(players, player_id)
   -- Load ui mod
   if not player_id then
      player_id = _radiant.client.get_player_id()
   end
   
   local client_player = players[player_id]
   if client_player then
      if client_player.kingdom == "box_o_vox:server:population:data:kingdoms:boxling" then
         -- hot load rayyas children ui mod
         _radiant.res.apply_manifest("/box_o_vox/ui/manifest.json")
      end
   end
end

local function trace_player_service()
   _radiant.call('stonehearth:get_service', 'player')
      :done(function(r)
         local player_service = r.result
         check_override_ui(player_service:get_data().players)
         player_service_trace = player_service:trace('box o vox ui change')
               :on_changed(function(o)
                     check_override_ui(player_service:get_data().players)
                  end)
         end)
end

radiant.events.listen(box_o_vox, 'radiant:init', function()
   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
         trace_player_service()
      end)
   end)

function box_o_vox:_on_init()
    local CustomPortraitRendererService = require('services.client.portrait_renderer.portrait_renderer_service')
    local PortraitRendererService = radiant.mods.require('stonehearth.services.client.portrait_renderer.portrait_renderer_service')
    radiant.mixin(PortraitRendererService, CustomPortraitRendererService)
    
end

radiant.events.listen_once(radiant,'radiant:client:server_ready', box_o_vox, box_o_vox._on_init)

return box_o_vox