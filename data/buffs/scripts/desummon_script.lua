local DestroyEntityOnExpire = class()

function DestroyEntityOnExpire:on_buff_removed(entity, buff)
   if buff and buff:is_duration_expired() then
      radiant.entities.destroy_entity(entity)
   end
end

return DestroyEntityOnExpire
