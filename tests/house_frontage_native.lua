-- Executed inside the real campaign in a disposable native Luanti world.
return function(api)
  local Sim,S=api.Sim,api.s
  local fixtures={
    {x=22,z=22,d=1,name="scenery_house_0",f=2,dx=1,dz=1},
    {x=28,z=22,d=2,name="scenery_house_1",f=1,dx=0,dz=1},
    {x=22,z=27,d=3,name="scenery_house_2",f=0,dx=0,dz=0},
    {x=28,z=27,d=4,name="scenery_house_3",f=3,dx=1,dz=0},
    {x=34,z=22,d=2,name="town_shop",f=1,dx=0,dz=1},
    {x=34,z=27,d=4,name="town_green",f=0,dx=0,dz=0},
    {x=22,z=32,d=2,name="house_build_stage_2",f=3,dx=1,dz=0},
    {x=28,z=32,d=1,name="town_market",f=0,dx=0,dz=0},
  }
  S.speed=0
  for k in ipairs(S.corner_grid.levels) do S.corner_grid.levels[k]=2 end
  for z=1,Sim.H do for x=1,Sim.W do
    S.tiles[Sim.id(x,z)]={terrain="grass",variant=(3*x+z)%4,h=2}
  end end
  for i,q in ipairs(fixtures) do
    q.id=assert(Sim.id(q.x,q.z))
    local t=S.tiles[q.id]
    t.house,t.variant=true,(i-1)%4
    t.parcel=q.name:match("^town_(.+)")
    if i==7 then t.source_house={town_growth=true,completed=false,stage=2,render_variant=2} end
    q.road=Sim.adjacent(q.id,q.d)
    local r=S.tiles[q.road]
    r.build,r.road_bits,r.road_town="road",(q.d==1 or q.d==3) and 10 or 5,1
  end
  local function verify(q)
    for dz=0,1 do for dx=0,1 do
      local p={x=2*q.x+dx,y=3,z=2*q.z+dz}
      local n=core.get_node(p)
      if dx==q.dx and dz==q.dz then
        assert(n.name=="luanttd_core:"..q.name and n.param2==q.f,
          table.concat({q.name,n.name,n.param2,q.f,dx,dz}," / "))
        if q.name~="town_green" and q.name~="town_market" then
          local f=core.facedir_to_dir(n.param2)
          local sign=q.name:find("house_build",1,true) and -1 or 1
          assert(f.x*sign==Sim.dir[q.d][1] and f.z*sign==Sim.dir[q.d][2])
        end
      else
        assert(n.name=="air" and n.param2==0,n.name.." / "..n.param2)
      end
    end end
  end
  local ready,pending=false,false
  core.register_on_joinplayer(function()
    if pending then return end
    pending=true
    core.emerge_area({x=39,y=0,z=39},{x=73,y=9,z=69},function(_,why,left)
      assert(why~=core.EMERGE_CANCELLED and why~=core.EMERGE_ERRORED)
      if left~=0 then return end
      core.after(0,function()
        for _,q in ipairs(fixtures) do verify(q) end
        -- Refresh an already-awake old parcel after a road change, then
        -- restore it for the real view. The renderer must remove old anchor.
        local q=fixtures[1]
        local w=Sim.adjacent(q.id,4)
        S.tiles[q.road].build=nil
        S.tiles[w].build="road"
        S.tiles[w].road_bits=5
        api.render.update({q.road,w})
        q.d,q.f,q.dx,q.dz=4,3,1,0
        verify(q)
        S.tiles[q.road].build="road"
        S.tiles[w].build=nil
        api.render.update({q.road,w})
        q.d,q.f,q.dx,q.dz=1,2,1,1
        verify(q)
        -- Snapshot construction completes with opposite source-OBJ front,
        -- under the same physical street direction and centered parcel.
        local st=fixtures[7]
        S.tiles[st.id].source_house.completed=true
        api.render.update({st.id})
        st.name,st.f,st.dx,st.dz="scenery_house_2",1,0,1
        verify(st)
        S.tiles[st.id].source_house.completed=false
        api.render.update({st.id})
        st.name,st.f,st.dx,st.dz="house_build_stage_2",3,1,0
        verify(st)
        ready=true
        core.log("action","HOUSE_FRONTAGE_NATIVE_OK all four facade directions + VM param2 + live road and stage refresh")
      end)
    end)
  end)
  core.register_chatcommand("frontage",{
    params="case number",
    func=function(name,arg)
      local p=core.get_player_by_name(name)
      local q=fixtures[tonumber(arg)]
      if not ready or not p or not q then return false,"Fixture not ready" end
      local dx,dz=unpack(Sim.dir[q.d])
      local x,z=q.x*2+.5,q.z*2+.5
      local at={x=x,y=2.85,z=z}
      local from={x=x+dx*3.4-dz*.22,y=2.71,z=z+dz*3.4+dx*.22}
      p:set_pos(from)
      local v={x=at.x-from.x,y=at.y-from.y-1.47,z=at.z-from.z}
      p:set_look_horizontal(math.atan2(-v.x,v.z))
      p:set_look_vertical(math.atan2(-v.y,math.sqrt(v.x*v.x+v.z*v.z)))
      return true
    end,
  })
end
