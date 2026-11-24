-- Dedicated test streetcar controller, shared by the hotbar and chat.
-- Orders run repeatedly on a dedicated line; no passenger fares.
return function(api,N,Run)
  local Sim,S=api.Sim,api.s
  local errors={
    TRAM_NEEDS_FLAT_CLEARANCE="A tram platform or depot needs flat ground.",
    TRAM_SITE_CLEARANCE="Choose a clear site away from overhead or underground structures.",
    PROTECTED_TILE="The tile is protected or has incompatible infrastructure.",
    VEHICLE_IN_THE_WAY="A vehicle occupies that tile.",
    ALREADY_BUILT="Those tram pieces are already built.",
    no_path="No complete dedicated tram route; continue the one-half track beyond the stop for a reversal.",
    mixed_traffic_not_enabled="The running pilot needs a dedicated line. Street tram and bus arbitration is not enabled.",
    depot_and_two_stops_required="Choose a tram depot and two distinct through stops.",
    terminal_owner="Choose your company's depot and stops.",
    pilot_already_exists="Only one test streetcar can run at once. Clear the current one first.",
    no_owned_pilot="There is no test streetcar for your company.",
  }
  local function why(reason) return errors[reason] or "Tram pilot: "..tostring(reason) end
  local dirs={ne=0,se=1,sw=2,nw=3,west=0,south=1,east=2,north=3}
  local function id(x,z) return x and z and Sim.id(tonumber(x),tonumber(z)) end
  local function busy(tile)
    if Run.uses(S,tile) then return true end
    for _,v in pairs(S.fleet) do if Sim.position(S,v)==tile then return true end end
    return false
  end
  local function start(name,depot,first,second)
    local run,msg=Run.start(S,name,depot,first,second)
    if not run then return false,why(msg) end
    api.save()
    return true,"Test streetcar dispatched between the two stops. It does not carry passengers."
  end
  local function clear(name)
    local ok,msg=Run.clear(S,name)
    if not ok then return false,why(msg) end
    api.save()
    return true,"Test streetcar removed. Your tramway and stops remain."
  end
  local function status(name)
    local p=Run.current(S)
    if not p or p.owner~=name then return false,why("no_owned_pilot") end
    return true,("Test streetcar %s  ·  %d stop visits  ·  %d movement steps"):format(p.phase,p.arrivals,p.steps)
  end
  local function facility(name,tile,kind)
    local t=S.tiles[tile]
    local record=t and t.tram
    return record and record.owner==name and record.kind==kind
  end
  api.tram={network=N,run=Run,busy=busy,reason=why,start=start,clear=clear,status=status,facility=facility}
  local occupancy=dofile(core.get_modpath("luanttd_core").."/tram_occupancy.lua")
  function api.tram.busy_probe() return occupancy(Sim,Run,S) end
  core.register_chatcommand("tramway",{
    params="X Z END_X END_Z | bit X Z MASK | depot X Z east|west|north|south | stop X Z x|z",
    description="Build independent flat electric tram track and facilities",
    func=function(name,params)
      local x,z,u,v=params:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local a,b=id(x,z),id(u,v)
      local kind,ids,detail="road"
      if a and b then ids=Sim.line(a,b)
      else
        local k,c,d,arg=params:match("^(%a+)%s+(%d+)%s+(%d+)%s+(%w+)$")
        a=id(c,d)
        if a then
          ids={a}
          if k=="bit" then detail=tonumber(arg)
          elseif k=="stop" then kind="drive_stop";detail=({x=0,z=1})[arg]
          elseif k=="depot" then kind="depot";detail=dirs[arg] end
        end
        if not detail then return false,"Use /help tramway for track, depot and through-stop syntax." end
      end
      local changed,cost,failed=N.construct(S,name,kind,ids,detail,busy)
      if not changed then
        local suffix=""
        if failed then local i,j=Sim.xy(failed);suffix=(" (%d,%d)"):format(i,j) end
        return false,why(cost)..suffix
      end
      api.render.update(changed);api.save()
      return true,("Tram construction complete: %d tile(s), $%d."):format(#changed,cost)
    end,
  })
  core.register_chatcommand("trampilot",{
    params="DEPOT_X DEPOT_Z FIRST_X FIRST_Z SECOND_X SECOND_Z | status | clear",
    description="Dispatch a single test streetcar on a dedicated line",
    func=function(name,params)
      if params=="" or params=="status" then return status(name) end
      if params=="clear" then return clear(name) end
      local a,b,c,d,e,f=params:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local depot,first,second=id(a,b),id(c,d),id(e,f)
      if not depot or not first or not second then return false,"Use /help trampilot for syntax." end
      return start(name,depot,first,second)
    end,
  })
end
