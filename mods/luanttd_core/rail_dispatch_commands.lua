-- Commands for the isolated flat-track, at-most-two-consists pilot.
return function(api,Run,Track,Signal)
  local Sim,S=api.Sim,api.s
  local facing={west=0,south=1,east=8,north=9}
  local function tile(x,z) return x and z and Sim.id(tonumber(x),tonumber(z)) end
  core.register_chatcommand("pathsignal",{
    params="X Z east|west|north|south [oneway]",
    description="Build a directional stock path signal on your plain straight track",
    func=function(name,args)
      local x,z,d,kind=args:match("^(%d+)%s+(%d+)%s+(%a+)%s*(%a*)$")
      local id=tile(x,z)
      if not id or not facing[d] or (kind~="" and kind~="oneway") then
        return false,"Use /pathsignal X Z east|west|north|south [oneway]."
      end
      local td=facing[d]
      if api.rail_build then
        local p,note=api.rail_build.quote_signal(name,id,Track.exit_side(td),kind=="oneway")
        if not p then return false,note end
        return api.rail_build.build(name,p)
      end
      local ok,text=Run.place_signal(S,name,id,td,kind=="oneway" and Signal.PBS_ONEWAY or Signal.PBS)
      if ok then api.save() end
      return ok,text
    end,
  })
  core.register_chatcommand("raildispatch",{
    params="DEPOT_X DEPOT_Z PLATFORM_X PLATFORM_Z | status | clear",
    description="Dispatch up to two coupled pilot trains on a signalled line",
    func=function(name,args)
      local d=Run.current(S)
      if args=="" or args=="status" then
        if not d or #d.runs==0 or d.owner~=name then return false,"No coupled train ordered yet." end
        local rows={}
        local paid=Sim.rail_paid_status(S)
        if paid then
          rows[#rows+1]=("Train %s · %d/%d aboard · %d delivered · $%d fares"):format(
            d.runs[1].phase,paid.onboard,paid.capacity,paid.delivered,paid.fare)
        end
        for _,t in ipairs(d.runs) do
          rows[#rows+1]=("Train %d: %s → platform #%d"):format(t.id,t.phase,t.station)
        end
        return true,table.concat(rows,"\n")
      elseif args=="clear" then
        local ok,msg=Run.clear(S,name)
        if ok then api.save() end
        return ok,msg
      end
      local x,z,u,v=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local a,b=tile(x,z),tile(u,v)
      if not a or not b then return false,"Use /raildispatch DEPOT_X DEPOT_Z PLATFORM_X PLATFORM_Z." end
      local station=S.tiles[b].rail_station_id
      if not station then return false,"Choose a real Trackworks platform." end
      if not api.trackworks_demo.is_clear() then return false,"Clear the existing survey locomotive first." end
      local ok,msg=Run.start(S,name,a,station)
      if ok then api.save() end
      return ok,msg
    end,
  })
  core.register_chatcommand("railshuttle",{
    params="DEPOT_X DEPOT_Z FIRST_X FIRST_Z SECOND_X SECOND_Z",
    description="Order one coupled train to alternate two platforms",
    func=function(name,args)
      local a,b,c,d,e,f=args:match("^(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)$")
      local depot,one,two=tile(a,b),tile(c,d),tile(e,f)
      if not depot or not one or not two then return false,"Use /help railshuttle for syntax." end
      if not api.trackworks_demo.is_clear() then return false,"Clear the existing survey locomotive first." end
      local ok,msg=Run.start_shuttle(S,name,depot,S.tiles[one].rail_station_id,S.tiles[two].rail_station_id)
      if ok then api.save() end
      return ok,msg
    end,
  })
end
