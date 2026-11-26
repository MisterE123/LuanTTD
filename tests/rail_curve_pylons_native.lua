do
  local owner="Curved electric QA"
  local Owned,Run=assert(api.rail_owned),assert(api.rail_dispatch_controller)
  local Track=dofile(mod.."/openttd/rail_track.lua")
  local P=dofile(mod.."/openttd/rail_pylon.lua")(Track,dofile(mod.."/openttd/rail_pylon_tables.lua"))
  local W=dofile(mod.."/rail_edge_pylon.lua")(Sim,Track,P,api.terrain)
  local at=Sim.id
  local depot,corner=at(4,10),at(16,10)
  local function stamp()
    local saved=S.rail_curve_native
    if not saved then
      local g=assert(S.corner_grid)
      for i in ipairs(g.levels) do g.levels[i]=0 end
      for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
      local line={}
      local function rail(id,bits)
        local t=S.tiles[id]
        t.build,t.rail_tracks,t.owner="stock_rail",bits,owner
        line[#line+1]=id
      end
      for x=4,15 do rail(at(x,10),1) end
      rail(corner,4)
      for z=3,9 do rail(at(16,z),2) end
      Sim.company(S,owner)
      assert(api.trackworks.depot(S,owner,depot,Track.SW))
      assert(api.trackworks.station(S,owner,at(7,10),at(8,10)))
      assert(api.trackworks.station(S,owner,at(16,4),at(16,5)))
      local a,b=S.tiles[at(7,10)].rail_station_id,S.tiles[at(16,4)].rail_station_id
      S.sites[1].tile,S.sites[2].tile=at(7,12),at(18,4)
      for x=5,10 do for z=11,14 do
        local t=S.tiles[at(x,z)];t.house,t.parcel,t.variant=true,"shop",2
      end end
      for x=17,20 do for z=3,7 do
        local t=S.tiles[at(x,z)];t.house,t.parcel,t.variant=true,"shop",2
      end end
      local gap=at(16,9)
      table.remove(line,#line)
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,line,1))))
      api.render.update({corner})
      local stale=assert(W.at(S,corner,S.tiles[corner]))
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{gap},1))))
      api.render.update({corner})
      local joint=assert(W.at(S,corner,S.tiles[corner]))
      assert(stale~=joint,"Source edge support must react to branch energizing")
      local row=W.poles[1][joint%33]
      local col=W.poles[2][math.floor(joint/33)]
      assert(row or col,"The stock curve must have at least one pylon")
      if row then assert(core.get_node({x=33,y=2,z=20}).name=="luanttd_core:"..row) end
      if col then assert(core.get_node({x=32,y=2,z=21}).name=="luanttd_core:"..col) end
      local bus=assert(Owned.commit(S,owner,assert(Owned.quote(S,owner,depot,{23,27}))))
      local ok,why=Owned.start(S,owner,bus.id,a,b)
      assert(ok,why)
      for _=1,55 do
        Sim.daily(S)
        local service=assert(Sim.rail_paid_status(S,bus.id))
        if service.loading and service.onboard>0 then
          S.rail_curve_native={id=bus.id,a=a,b=b,pylon=joint,row=row,col=col}
          api.save()
          core.log("action","RAIL_CURVED_PYLON_NATIVE_SAVED")
          core.request_shutdown("Saved native SH30 passengers before taking the electrified corner",false,0)
          return
        end
      end
      error("The owned train never boarded paying passengers")
    end
    assert(saved.pylon==W.at(S,corner,S.tiles[corner]))
    if saved.row then assert(core.get_node({x=33,y=2,z=20}).name=="luanttd_core:"..saved.row) end
    if saved.col then assert(core.get_node({x=32,y=2,z=21}).name=="luanttd_core:"..saved.col) end
    local seen,arrived
    for _=1,100 do
      Sim.daily(S)
      local run=assert(Run.current_paid(S,saved.id))
      for f=0,74 do
        local id=Sim.rail_paid_pose(S,1,f/74,saved.id,true)
        if id==corner then seen=true end
      end
      if seen and Sim.company(S,owner).revenue>0 then arrived=true;break end
    end
    assert(seen and arrived,"Bought SH30 did not traverse the curved catenary and deliver after reopening")
    core.log("action","RAIL_CURVED_PYLON_NATIVE_PASS exact curve edge art and actual paid SH30 fare after save")
    core.request_shutdown("Reopened native powered curve and verified passenger service",false,0)
  end
  core.after(0,function()
    core.emerge_area({x=0,y=-1,z=2},{x=46,y=5,z=37},function(_,_,n)
      if n==0 then core.after(0,stamp) end
    end)
  end)
end
