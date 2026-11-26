return function(api)
  local S,R,Sim=api.s,api.render,api.Sim
  local Terrain=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  S.speed=0
  S.corner_grid.levels=Terrain.new(Sim.W,Sim.H,function(x)return x<=6 and 2 or 1 end).levels
  S.stock_small_airports={[1]={origin=Sim.id(9,11),layout="country"}}
  local dirty={}
  for z=8,16 do for x=3,17 do
    local id=Sim.id(x,z)
    local t={terrain="grass",h=x<=5 and 2 or 1,variant=0}
    S.tiles[id]=t;dirty[#dirty+1]=id
    if x>=9 and x<=12 and z>=11 and z<=13 then t.airfield={airport=1,x=x-9,z=z-11,layout="country"} end
    if x==4 and z==13 then t.wood=true end
  end end
  local start,blocked
  local function pilot(n) return assert(core.get_player_by_name(n)) end
  local function shell(p) return assert(p:get_attach()):get_pos() end
  core.register_chatcommand("taxi_qa",{func=function(n,state)
    local p=pilot(n)
    local q=shell(p)
    if state=="passed" then
      assert(q.x>9.80 and q.x<10.50 and q.y>2.55,
        ("Expected plane at the treeline after climbing the whole grass grade: %s"):format(core.pos_to_string(q)))
      blocked=q.x
      core.log("action","TAXI_PASSED: "..core.pos_to_string(q))
    elseif state=="reverse" then
      assert(blocked and q.x>blocked+.28,"Reverse did not free the aircraft: "..core.pos_to_string(q))
      assert(q.x<start.x-2,"Reverse unexpectedly reset to the runway")
      core.log("action","TAXI_NATIVE_PASS: "..core.pos_to_string(q))
    end
    return true
  end})
  core.register_on_joinplayer(function(p)
    if p:get_player_name()~="WalkQA" then return end
    core.emerge_area({x=3,y=-1,z=14},{x=35,y=8,z=36},function(_,_,left)
      if left~=0 then return end
      core.after(.4,function()
        R.update(dirty)
        p:set_pos({x=26,y=4,z=27})
        p:set_clouds({density=0})
        local ok,why=api.sightseeing_plane.board(p,Sim.id(9,11))
        assert(ok,why)
        start=shell(p)
        core.log("action","TAXI_NATIVE_READY: "..core.pos_to_string(start))
      end)
    end)
  end)
end
