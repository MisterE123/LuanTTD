do
  local owner="Compound electric QA"
  local Owned,Run=assert(api.rail_owned),assert(api.rail_dispatch_controller)
  local Track=dofile(mod.."/openttd/rail_track.lua")
  local Wire=dofile(mod.."/rail_turnout_wire.lua")(Sim,Track,dofile(mod.."/openttd/rail_wire_mask.lua")(Track))
  local terrain=dofile(mod.."/openttd/terrain.lua")
  local K=dofile(mod.."/openttd/rail_pylon.lua")(Track,dofile(mod.."/openttd/rail_pylon_tables.lua"))
  local P=dofile(mod.."/rail_edge_pylon.lua")(Sim,Track,K,{
    tile=function(at)return terrain.tile(S.corner_grid,Sim.xy(at)) end},Wire)
  local function supports(id,level,profile)
    local x,z=Sim.xy(id)
    local q=P.at(S,id,S.tiles[id])
    assert(P.is_distributed(q),q)
    if profile then assert(q==profile,q) end
    for slot,d in ipairs({{1,0,2},{0,1,2},{1,1,2},{0,0,3}}) do
      local node=P.distributed[slot][P.decode(q,slot)]
      local got=core.get_node({x=2*x+d[1],y=(level or 0)+d[3],z=2*z+d[2]}).name
      assert(got==(node and "luanttd_core:"..node or "air"),("Tile %d at slot %d: %s"):format(id,slot,got))
    end
  end
  local at=Sim.id
  local depot,corner=at(4,10),at(16,10)
  local function installed(id,mask,level)
    local x,z=Sim.xy(id)
    assert(Wire.at(S,id,S.tiles[id])==mask,"Source junction contact mask")
    local wire=core.get_node({x=2*x,y=(level or 0)+2,z=2*z}).name
    assert(wire=="luanttd_core:rail_compound_contact_"..mask,wire)
    supports(id,level)
  end
  local function stamp()
    local saved=S.rail_compound_native
    if not saved then
      for i in ipairs(S.corner_grid.levels) do S.corner_grid.levels[i]=0 end
      for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
      local line={}
      local function rail(id,bits)
        local t=S.tiles[id]
        t.build,t.rail_tracks,t.owner="stock_rail",bits,owner
        line[#line+1]=id
      end
      for x=4,15 do rail(at(x,10),1) end
      for z=3,9 do rail(at(16,z),2) end
      rail(corner,63)
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
      local ticket,why=api.electric_quote(owner,line,1)
      assert(ticket,why)
      assert(api.electric_commit(owner,ticket))
      local partial=assert(Wire.at(S,corner,S.tiles[corner]))
      installed(corner,partial)
      assert(partial==4,"Only the two connected ports should stay live")
      rail(at(17,10),1)
      rail(at(16,11),2)
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{at(17,10)},1))))
      local triple=assert(Wire.at(S,corner,S.tiles[corner]))
      installed(corner,triple)
      assert(triple~=partial and triple~=63 and Track.tracks_overlap(triple),"Three ports need a compound surviving contact mesh")
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{at(16,11)},1))))
      installed(corner,63)
      local isolated,diamond=at(20,17),at(22,17)
      rail(isolated,25);rail(diamond,3)
      local founded=at(21,15)
      local terrain=dofile(mod.."/openttd/terrain.lua")
      assert(terrain.apply(S.corner_grid,assert(terrain.plan(S.corner_grid,21,15,5,true))))
      local slope,base=terrain.tile(S.corner_grid,21,15)
      assert(slope==5 and base==0 and Track.foundation(slope,25)=="leveled")
      rail(founded,25)
      local fork_price=Sim.company(S,owner).cash
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{isolated,diamond,founded},1))))
      local charge=fork_price-Sim.company(S,owner).cash
      assert(charge==544,"Expected stock per-piece conversion price")
      installed(isolated,25);installed(diamond,3);installed(founded,25,1)
      local second,adjacent,spur,far=at(30,31),at(31,31),at(31,30),at(32,31)
      rail(second,6);rail(adjacent,3);rail(spur,2);rail(far,1)
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{second,adjacent,spur},1))))
      supports(second,0,2122)
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{far},1))))
      supports(second,0,2170) -- repaint via the ordinary committed far conversion
      local train=assert(Owned.commit(S,owner,assert(Owned.quote(S,owner,depot,{23,27}))))
      local ok,note=Owned.start(S,owner,train.id,a,b)
      assert(ok,note)
      for _=1,55 do
        Sim.daily(S)
        local service=assert(Sim.rail_paid_status(S,train.id))
        if service.loading and service.onboard>0 then
          S.rail_compound_native={id=train.id,a=a,b=b,isolated=isolated,diamond=diamond,founded=founded}
          api.save()
          core.log("action",("RAIL_COMPOUND_NATIVE_SAVED contacts=4,%d,63 fare_source=%d price=%d")
            :format(triple,service.onboard,charge))
          if core.settings:get_bool("luanttd_qa_compound_photo",false) then
            for _=1,65 do
              Sim.daily(S)
              local run=assert(Run.current_paid(S,train.id))
              if run.consist.parts[1].tile==corner then break end
            end
            local run=assert(Run.current_paid(S,train.id))
            assert(run.consist.parts[1].tile==corner,"Expected a real electric consist in the junction frame")
            S.speed=0
            core.register_on_joinplayer(function(viewer)
              core.after(2,function()
                if not viewer:get_pos() then return end
                if not api.lighting.is_always_day() then api.lighting.toggle(viewer) end
                local cam={x=37.4,y=5.25,z=26.6}
                local eye={x=cam.x,y=cam.y+1.625,z=cam.z}
                local target={x=32.5,y=1.14,z=20.3}
                local d=vector.direction(eye,target)
                viewer:set_pos(cam);viewer:set_look_horizontal(core.dir_to_yaw(d));viewer:set_look_vertical(-math.asin(d.y))
                if api.cinematic then api.cinematic.toggle(viewer) end
                core.log("action","RAIL_COMPOUND_NATIVE_ART_READY")
              end)
            end)
            return
          end
          core.request_shutdown("Saved a paid train loading before the compound junction",false,0)
          return
        end
      end
      error("Train never boarded paying passengers")
    end
    installed(corner,63);installed(saved.isolated,25);installed(saved.diamond,3);installed(saved.founded,25,1)
    supports(at(30,31),0,2170)
    local seen,arrived
    for _=1,100 do
      Sim.daily(S)
      assert(Run.current_paid(S,saved.id))
      for f=0,74 do
        local id=Sim.rail_paid_pose(S,1,f/74,saved.id,true)
        if id==corner then seen=true end
      end
      if seen and Sim.company(S,owner).revenue>0 then arrived=true;break end
    end
    assert(seen and arrived,"Bought SH30 did not traverse and earn a fare after reopening")
    core.log("action","RAIL_COMPOUND_NATIVE_PASS paid SH30 on six-piece junction; isolated triple/diamond persist")
    core.request_shutdown("Verified stock compound wiring and owned service",false,0)
  end
  core.after(0,function()
    core.emerge_area({x=0,y=-1,z=2},{x=65,y=5,z=64},function(_,_,n)
      if n==0 then core.after(0,stamp) end
    end)
  end)
end
