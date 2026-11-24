-- Bind the same demolition choices to the simulation owner, with no
-- formspec, renderer, engine object or secondary persistence.
return function(Sim,mod,R)
  local s,net=R.world,R.network
  local api={s=s,Sim=Sim,structure_tools=true,trackworks=net.lab,rail_spans=net.spans,
    rail_build=R.rail and R.rail.build}
  if R.tram then api.tram={network=R.tram.net,busy=R.tram.busy,busy_probe=R.tram.busy_probe} end
  local aquatic_remove
  if R.water then
    local w=R.water
    api.shipyard={reason=function(msg) return msg end,busy=w.busy}
    local aqueduct,works=w.aqueduct,w.works
    aquatic_remove=function(owner,id,quote)
      local t=s.tiles[id]
      if t.ship and t.ship.aqueduct then return aqueduct.remove(s,owner,id,quote) end
      if t.ship and t.ship.kind=="lock" then return works.remove_lock(s,owner,id,quote) end
      if not t.ship and t.stock_canal then return works.remove(s,owner,id,quote) end
      return w.network.remove(s,owner,id,nil,quote)
    end
  end
  if R.air then
    local a=R.air
    api.airfield={network=a.network,reason=function(msg) return msg end,busy=function(id)
      if a.owned.owns_hangar(s,id) then return true end
      for _,run in ipairs(a.run.all(s)) do if a.run.uses_airfield(run,id) then return true end end
      return false
    end}
  end
  if R.rail and R.rail.wire then
    api.electric_quote=R.rail.wire.quote
    api.electric_commit=R.rail.wire.commit
  end
  local function dollars(amount)
    local n=math.abs(math.floor(amount))
    return (amount<0 and "-$" or "$")..tostring(n):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
  end
  local structure=dofile(mod.."/demolition_structures.lua")(api,aquatic_remove,dollars)
  return dofile(mod.."/demolition_layer_choices.lua")(api,structure)
end
