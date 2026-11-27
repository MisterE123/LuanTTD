core.set_mapgen_setting("mg_name","singlenode",true)
for _,node in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..node,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local m=assert(core.get_modpath("luanttd_core"))
    local function lib(n) return dofile(m.."/"..n..".lua") end
    assert(bit and bit.band or bit32 and bit32.band,"expected native bit operations")
    local old=lib("old_follow")
    local candidate=lib("openttd/yapf_road_follow")
    for mask=0,0x3fff do
      for td=0,13 do
        assert(old.has_trackdir(mask,td)==candidate.has_trackdir(mask,td))
      end
    end
    for mask=0,15 do
      for d=0,3 do
        for dir=0,3 do
          local tile={kind="road",roadtype=0,tramtype=1,road_bits=mask,tram_bits=mask,disallowed=d}
          for _,tram in ipairs({true,false}) do
            assert(old.origin_trackdirs(tile,tram,dir)==candidate.origin_trackdirs(tile,tram,dir))
          end
        end
      end
    end
    local base_search,new_search=lib("old_search"),lib("openttd/yapf_road_search")
    local version={{old,base_search},{candidate,new_search}}
    local Sim,T=lib("sim"),lib("openttd/terrain")
    local old_sim=lib("old_sim")
    Sim.W,Sim.H,old_sim.W,old_sim.H=128,128,128,128
    local S=Sim.new(1751)
    S.sites={}
    S.corner_grid=T.new(128,128,function() return 1 end)
    for _,t in ipairs(S.tiles) do
      t.terrain,t.h,t.wood,t.site,t.house="grass",1,nil,nil,nil
    end
    local id=Sim.id
    Sim.company(S,"High Street").cash=100000000
    for x=8,120,4 do assert(Sim.build(S,"High Street","road",Sim.line(id(x,8),id(x,120)))) end
    for z=8,120,4 do assert(Sim.build(S,"High Street","road",Sim.line(id(8,z),id(120,z)))) end
    for i=1,16 do
      local a,b=id(13,8+4*i),id(119,120-4*i)
      for _,tile in ipairs({a,b}) do
        S.sites[#S.sites+1]={id=#S.sites+1,name="Bench Town",kind="town",tile=tile,population=220,stock={},produced={},received={}}
        assert(Sim.build(S,"High Street","road_station",{tile}))
      end
    end
    local expect={}
    local function roads(which)
      local f,factory=unpack(version[which])
      local C=lib(which==1 and "old_cost" or "openttd/yapf_road_cost")(f)
      local search=factory(f,C)
      local make_board=lib(which==1 and "old_board" or "road_yapf_board")
      local active_sim=which==1 and old_sim or Sim
      local t,c=core.get_us_time(),os.clock()
      local nodes=0
      for i=1,16 do
        local here,to=id(14,8+4*i),S.tiles[id(119,120-4*i)].station
        local v={tile=here,display_max_speed=112,bus=true,owner="High Street"}
        for k=1,2 do
          -- The live game binds a fresh read-only board for each search.
          local board=make_board(active_sim,S,f)
          local target=C.destination(board,v,{kind="station",station=to})
          local settings={disable_node_optimization=k==2}
          local hit,route,stats=search.find(board,v,here,2^f.direction_trackdir(f.SW),target,settings)
          assert(hit and route)
          local course=search.trace(board,v,target,route,settings)
          local key={route.cost,route.estimate,stats.closed_count,stats.capped and 1 or 0}
          for j,p in ipairs(course) do key[2*j+3],key[2*j+4]=p.tile,p.td end
          local repr=table.concat(key,",")
          local n=2*i+k
          if expect[n] then assert(repr==expect[n],"road node/tie mismatch") else expect[n]=repr end
          nodes=nodes+stats.closed_count
        end
      end
      return 1000*(os.clock()-c),(core.get_us_time()-t)/1000,nodes
    end
    local rows={}
    for passes=1,8 do
      for h=1,#version do
        local v=passes%2==1 and h or #version-h+1
        collectgarbage("collect")
        local cpu,wall,nodes=roads(v)
        rows[#rows+1]={v,passes,cpu,wall,nodes}
      end
    end
    return rows
  end,function(rows)
    for _,r in ipairs(rows) do core.log("action",("YAPF NATIVE version=%d pass=%d cpu=%.3f wall=%.3f closed=%d"):format(unpack(r))) end
    core.request_shutdown("YAPF locality benchmark complete",false,0)
  end))
end)
