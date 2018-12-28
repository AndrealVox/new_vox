local HasPlayerStallCheckScript = class()

function HasPlayerStallCheckScript:start(ctx, data)
   local items = stonehearth.inventory:get_inventory(ctx.player_id):get_all_items()
   for _, item in pairs(items) do
      if item:get_component('stonehearth:player_market_stall') and radiant.entities.exists_in_world(item) then
         return true
      end
   end
   return false
end

return HasPlayerStallCheckScript
