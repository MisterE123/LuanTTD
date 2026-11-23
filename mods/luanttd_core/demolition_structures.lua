-- Existing whole-structure demolition routines, shared across both owners.
return function(api,aquatic_remove,dollars)
local S,Sim=api.s,api.Sim
return function(n,id,preview)
  local t=S.tiles[id]
  local function span_ids(s)
    local ids={s.start}
    for _,i in ipairs(s.middle) do ids[#ids+1]=i end
    ids[#ids+1]=s["end"]
    return ids
  end
  if t.road_bridge_id and api.structure_tools then
    local ok,msg,changed,level=Sim.remove_wood_bridge(S,n,id,preview)
    if preview then
      return true,ok and span_ids(changed) or nil,ok and ("Dismantle this entire road bridge  |  "..dollars(msg)) or msg
    end
    return true,ok and changed or nil,msg,level
  elseif t.road_tunnel_id and api.structure_tools then
    if preview then
      local span=S.stock_road_tunnels and S.stock_road_tunnels[t.road_tunnel_id]
      if not span or span.owner~=n then return true,nil,"Select your own road tunnel." end
      return true,{span.start,span["end"]},"Request demolition of both road tunnel portals."
    end
    local ok,msg,changed=Sim.remove_road_tunnel(S,n,id)
    return true,ok and changed or nil,msg
  elseif t.rail_span_id and api.rail_spans then
    if preview then
      local span=api.rail_spans.by_portal(S,id)
      if not span or span.owner~=n then return true,nil,"Select your own rail bridge or tunnel." end
      return true,span_ids(span),"Request demolition of the entire rail "..span.kind.."."
    end
    local ok,msg,changed,level=api.rail_spans.clear(S,n,id)
    return true,ok and changed or nil,msg,level
  elseif t.airfield and api.airfield then
    local changed,price,level=api.airfield.network.remove(S,n,id,preview,api.airfield.busy)
    return true,changed,changed and ("Dismantle airfield  |  "..dollars(price)) or api.airfield.reason(price),level
  elseif t.ship and api.shipyard then
    if t.ship.kind~="buoy" and api.shipyard.busy() then return true,nil,"An active vessel protects these harbor facilities." end
    local changed,price=aquatic_remove(n,id,preview)
    return true,changed,changed and ("Dismantle water structure  |  "..dollars(price)) or api.shipyard.reason(price)
  end
end
end
