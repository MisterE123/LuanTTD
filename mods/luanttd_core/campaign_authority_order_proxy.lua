-- Bridge the existing vehicle form to a single-owner campaign client.
-- The host passes the engine-authenticated player name into both functions.
return function(client,mode)
  local revision_by_player={}
  local M={}
  if mode=="road" then
    function M.toggle(player,vehicle,done)
      local revision=revision_by_player[player]
      if revision==nil then return nil,"Open the current orders first." end
      return client.query({kind="command",player=player,command={
        kind="road_toggle",vehicle=vehicle,revision=revision,
      }},function(r)
        if r.revision~=nil then revision_by_player[player]=r.revision end
        done(r.ok,r.why)
      end)
    end
  end
  function M.fetch(player,vehicle,done)
    return client.query({kind="orders",player=player,mode=mode,vehicle=vehicle},function(r)
      if r.ok then
        revision_by_player[player]=r.revision
        done(r.value)
      else done(nil,r.why) end
    end)
  end
  function M.submit(player,vehicle,order_revision,operation,row,destination,done)
    local revision=revision_by_player[player]
    if revision==nil then return nil,"Open the current orders first." end
    return client.query({kind="command",player=player,command={
      kind="vehicle_order",mode=mode,vehicle=vehicle,revision=revision,order_revision=order_revision,
      operation=operation,row=row,destination=destination,
    }},function(r)
      if r.revision~=nil then revision_by_player[player]=r.revision end
      done(r.ok,r.why)
    end)
  end
  return M
end
