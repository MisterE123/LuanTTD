-- Fresh orders use the depot's existing dispatcher. This layer chooses its
-- two destinations; it does not create a new route model or start implicitly.
local R={}
function R.targets(mode,data,unit)
  local first,last={},{}
  local cargo=unit and unit.cargo
  if not unit or unit.unsupported then return first,last,cargo end
  local town_mail=mode=="rail" and (cargo=="mail" or cargo=="mixed")
  for _,r in ipairs(data.targets or {}) do
    if town_mail and not r.cargo or not town_mail and r.cargo==cargo then
      if not cargo or town_mail or r.role=="load" then first[#first+1]=r end
      if not cargo or town_mail or r.role=="unload" then last[#last+1]=r end
    end
  end
  return first,last,cargo
end
function R.find(list,id)
  for i,r in ipairs(list) do if r.id==id then return r,i end end
end
function R.possible(first,last)
  if not first[1] or not last[1] then return false end
  return first[1].id~=last[1].id or first[2]~=nil or last[2]~=nil
end
function R.notice(mode,unit)
  if unit.unsupported then return "Rearrange this train’s wagons in the depot before setting a route." end
  if mode=="ship" and unit.id=="ferry" then return "Build two company docks on the same waterway before starting this ferry." end
  if unit.cargo and unit.cargo~="mail" and unit.cargo~="mixed" then
    return "Build or designate separate loading and delivery stations for this cargo."
  end
  return "Build two compatible company rail stations before starting this train."
end
function R.context(client,p,mode,depot,unit,data,from,to)
  if not unit or unit.copied or not (mode=="rail" or mode=="ship" and unit.id=="ferry") then return end
  local name=p:get_player_name()
  local first,last=R.targets(mode,data,unit)
  local M={first=first,last=last,from=first[from or 0] and first[from].id,
    to=last[to or 0] and last[to].id,notice=R.notice(mode,unit)}
  function M.start(selection,done)
    local a,b=selection.first,selection.second
    if not (a and b and a~=b) then return nil,"Choose two different destinations." end
    local sent,why=client.query({kind="depot",player=name,mode=mode,depot=depot},function(reply)
      if not reply.ok then return done(false,reply.why) end
      local live
      for _,u in ipairs(reply.value.vehicles or {}) do if u.id==unit.id then live=u;break end end
      if not live or live.copied then return done(false,"The selected vehicle changed. Return to the depot and select it again.") end
      local origins,arrivals,cargo=R.targets(mode,reply.value,live)
      if not (R.find(origins,a) and R.find(arrivals,b)) then
        return done(false,"A selected station is no longer available for this vehicle.")
      end
      local c={kind="transport_start",mode=mode,depot=depot,vehicle=unit.id,cargo=cargo,first=a,second=b,
        first_tile=selection.first_tile,second_tile=selection.second_tile,revision=reply.revision}
      local queued,error_=client.query({kind="command",player=name,command=c},
        function(r) done(r.ok,r.why) end)
      if not queued then done(false,error_) end
    end)
    return sent,why
  end
  return M
end
return R
