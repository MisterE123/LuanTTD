-- One electric streetcar pilot, opt-in. It does not pretend to dispatch
-- paid trips, load passengers, or implement shared-lane fleet arbitration.
return function(Network,Trip,Speed)
  local R={VERSION=1}
  local speed_cap=96 -- Pilot presentation vehicle uses 48 km/h.
  local function compile(s,owner,a,b,td,wants)
    local board=Network.board(s)
    local path,last,cost,frames,trace=Trip.route(board,a,b,
      {owner=owner,tram_arrival_td=td,display_max_speed=speed_cap,cargo="passenger"})
    if not path then return nil,last end
    if not frames then return nil,"ordered_stop_must_differ" end
    for _,id in ipairs(path) do
      if board.tile(id).roadtype~=nil then return nil,"mixed_traffic_not_enabled" end
    end
    if wants then
      local first=frames[1]
      if first[1]~=wants[1] or first[2]~=wants[2] or first[3]~=wants[3] or
          first[4]~=wants[4] then return nil,"seam_discontinuous" end
    end
    return {path=path,last=last,source=a,target=b,cost=cost,frames=frames,trace=trace}
  end
  function R.current(s)
    local p=s.tram_pilot
    return p and p.version==R.VERSION and p or nil
  end
  function R.start(s,owner,depot,first,second)
    if R.current(s) then return nil,"pilot_already_exists" end
    local board=Network.board(s)
    local d,a,b=board.tile(depot),board.tile(first),board.tile(second)
    if not d or d.kind~="depot" or not a or not b or
       a.kind~="drive_stop" or b.kind~="drive_stop" or first==second then
      return nil,"depot_and_two_stops_required"
    end
    local lead,why=compile(s,owner,depot,first)
    if not lead then return nil,why end
    local leg1,msg=compile(s,owner,first,second,lead.last,lead.frames[#lead.frames])
    if not leg1 then return nil,msg end
    local leg2,msg2=compile(s,owner,second,first,leg1.last,leg1.frames[#leg1.frames])
    if not leg2 then return nil,msg2 end
    local loop,msg3=compile(s,owner,first,second,leg2.last,leg2.frames[#leg2.frames])
    if not loop then return nil,msg3 end
    local check,msg4=compile(s,owner,second,first,loop.last,loop.frames[#loop.frames])
    if not check or check.last~=leg2.last or loop.last~=leg1.last then
      return nil,msg4 or "unstable_arrival_orientation"
    end
    local active={version=R.VERSION,owner=owner,legs={lead,leg1,leg2,loop},leg=1,index=1,
      heading=lead.frames[1][3],speed=0,subspeed=0,progress=0,arrivals=0,phase="depot",
      wait=18,ticks=0,steps=0}
    s.tram_pilot=active
    return active
  end
  function R.clear(s,owner)
    local p=R.current(s)
    if not p or p.owner~=owner then return nil,"no_owned_pilot" end
    s.tram_pilot=nil
    return true
  end
  function R.frame(p)
    if not p or p.phase=="depot" then return end
    return p.legs[p.leg].frames[p.index]
  end
  function R.uses(s,id)
    local p=R.current(s)
    if p then
      for _,leg in ipairs(p.legs) do
        for _,tile in ipairs(leg.path) do if tile==id then return true end end
      end
    end
    return false
  end
  function R.advance(s,n,observe)
    local p=R.current(s)
    if not p then return end
    for _=1,n do
      p.ticks=p.ticks+1
      local leg=p.legs[p.leg]
      if p.wait>0 then
        p.wait=p.wait-1
        if p.wait==0 then
          if p.phase~="depot" then
            -- The first trip uses the compiler's approach direction; the
            -- stable loop may return to that platform from the other side.
            local following=({[1]=2,[2]=3,[3]=4,[4]=3})[p.leg]
            p.leg,p.index=following,1
          end
          p.phase,p.speed,p.subspeed,p.progress="running",0,0,0
          p.heading=p.legs[p.leg].frames[1][3]
        end
      else
        Speed.tick(p,speed_cap,false,function(c)
          local f=leg.frames[c.index+1]
          if not f then return false end
          if c.heading~=f[3] then c.heading=f[3];Speed.turn(c) end
          c.index=c.index+1
          c.steps=c.steps+1
          if observe then observe(f,c) end
          if c.index==#leg.frames then
            c.arrivals=c.arrivals+1
            c.phase,c.wait,c.speed,c.subspeed,c.progress="stopped",30,0,0,0
          end
          return true
        end)
        if p.phase=="stopped" then p.progress=0 end
      end
    end
    return p
  end
  return R
end
