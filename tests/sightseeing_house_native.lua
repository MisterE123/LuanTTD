return function(api)
  local S,R,Sim=api.s,api.render,api.Sim
  local Terrain=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  S.speed=0
  S.corner_grid.levels=Terrain.new(Sim.W,Sim.H,function()return 1 end).levels
  S.stock_small_airports={[1]={origin=Sim.id(9,11),layout="country"}}
  local dirty={}
  for z=9,16 do for x=2,17 do
    local id=Sim.id(x,z)
    local t={terrain="grass",h=1,variant=0}
    S.tiles[id]=t;dirty[#dirty+1]=id
    if x>=9 and x<=12 and z>=11 and z<=13 then t.airfield={airport=1,x=x-9,z=z-11,layout="country"} end
    if x==7 and z>=12 and z<=14 then
      t.house=true
      t.source_house={id=0x19,completed=true}
    end
  end end
  local start,roof
  local function shell(p) return assert(p:get_attach()):get_pos() end
  core.register_chatcommand("house_qa",{func=function(n,state)
    local p=assert(core.get_player_by_name(n))
    local q=shell(p)
    if state=="ground" then
      assert(q.x>14 and q.x<17 and q.y<roof,"The plane drove into the house or stopped too early. "..core.pos_to_string(q))
      core.log("action","DEPARTURE_HOUSE_GROUND: "..core.pos_to_string(q))
    elseif state=="reset" then
      assert(math.abs(q.x-start.x)<.05 and math.abs(q.y-start.y)<.05,"E did not return to runway: "..core.pos_to_string(q))
      core.log("action","DEPARTURE_RESET: "..core.pos_to_string(q))
    elseif state=="air" then
      assert(q.x<13.3 and q.y>roof-.05,"Takeoff stalled at houses at the end of the runway: "..core.pos_to_string(q))
      core.log("action","DEPARTURE_PASS: "..core.pos_to_string(q))
    end
    return true
  end})
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="WalkQA" then return end
    core.emerge_area({x=2,y=-1,z=14},{x=38,y=13,z=36},function(_,_,left)
      if left~=0 then return end
      core.after(.4,function()
        R.update(dirty)
        local id=Sim.id(7,13)
        for x=13.6,15.4,.1 do
          local y,known=R.flight_house_top(id,S.tiles[id],x,26.5)
          assert(known,"Stock cottage must use its real collision geometry")
          if y then roof=math.max(roof or 0,y) end
        end
        assert(roof and roof>2 and roof<3,"Fixture centerline must intersect the real cottage roofs")
        p:set_pos({x=26,y=4,z=27})
        p:set_clouds({density=0})
        local ok,why=api.sightseeing_plane.board(p,Sim.id(9,11))
        assert(ok,why)
        start=shell(p)
        core.log("action","DEPARTURE_READY: "..core.pos_to_string(start).." cottage roof "..roof)
      end)
    end)
  end)
end
