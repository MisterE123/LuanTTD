do
  local owner="Paired electrification QA"
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
  local depot,pair=at(4,10),at(16,10)
  local group={x=32,y=2,z=20}
  local function expect(mask,node)
    assert(Wire.at(S,pair,S.tiles[pair])==mask)
    assert(api.render.rail_dual(pair,12)=="12_2_0",api.render.rail_dual(pair,12))
    assert(core.get_node(group).name=="luanttd_core:"..node,core.get_node(group).name)
    supports(pair)
  end
  local function verify()
    local saved=S.rail_pair_native
    if not saved then
      for i in ipairs(S.corner_grid.levels) do S.corner_grid.levels[i]=0 end
      for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
      local line={}
      local function rail(x,z,bits)
        local id=at(x,z)
        local t=S.tiles[id]
        t.build,t.rail_tracks,t.owner="stock_rail",bits,owner
        line[#line+1]=id
      end
      for x=4,15 do rail(x,10,1) end
      rail(16,10,12)
      rail(16,9,8) -- actual north-going diagonal handoff
      rail(17,9,4)
      for z=3,8 do rail(17,z,2) end
      Sim.company(S,owner)
      assert(api.trackworks.depot(S,owner,depot,Track.SW))
      assert(api.trackworks.station(S,owner,at(7,10),at(8,10)))
      assert(api.trackworks.station(S,owner,at(17,4),at(17,5)))
      local a,b=S.tiles[at(7,10)].rail_station_id,S.tiles[at(17,4)].rail_station_id
      S.sites[1].tile,S.sites[2].tile=at(7,12),at(19,4)
      for x=5,10 do for z=11,14 do
        S.tiles[at(x,z)].house,S.tiles[at(x,z)].parcel=true,"shop"
      end end
      for x=18,21 do for z=3,7 do
        S.tiles[at(x,z)].house,S.tiles[at(x,z)].parcel=true,"shop"
      end end
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,line,1))))
      expect(4,"rail_pair_single_4_2")
      rail(17,10,1);rail(16,11,2)
      local before=Sim.company(S,owner).cash
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{at(17,10),at(16,11)},1))))
      assert(before-Sim.company(S,owner).cash==136)
      expect(12,"rail_pair_contact_12_2_0")
      local complement=at(22,16)
      rail(22,16,48)
      assert(api.electric_commit(owner,assert(api.electric_quote(owner,{complement},1))))
      assert(core.get_node({x=44,y=2,z=32}).name=="luanttd_core:rail_compound_contact_48")
      local train=assert(Owned.commit(S,owner,assert(Owned.quote(S,owner,depot,{23,27}))))
      local ok,reason=Owned.start(S,owner,train.id,a,b);assert(ok,reason)
      for _=1,65 do
        Sim.daily(S)
        local q=assert(Sim.rail_paid_status(S,train.id))
        if q.loading and q.onboard>0 then
          S.rail_pair_native={id=train.id}
          api.save()
          core.log("action","RAIL_PAIR_WIRE_NATIVE_SAVED wire=4->12 native diagonal=12_2_0")
          if core.settings:get_bool("luanttd_qa_pair_photo",false) then
            for _=1,90 do
              Sim.daily(S)
              local r=assert(Run.current_paid(S,train.id))
              if r.consist.parts[1].tile==pair then break end
            end
            assert(Run.current_paid(S,train.id).consist.parts[1].tile==pair,"Train did not reach native curve photo")
            S.speed=0
            core.register_on_joinplayer(function(viewer)
              core.after(2,function()
                if not viewer:get_pos() then return end
                if not api.lighting.is_always_day() then api.lighting.toggle(viewer) end
                local cam={x=37.4,y=3.6,z=23.8}
                local d=vector.direction({x=cam.x,y=cam.y+1.625,z=cam.z},{x=32.4,y=1.0,z=20.8})
                viewer:set_pos(cam);viewer:set_look_horizontal(core.dir_to_yaw(d));viewer:set_look_vertical(-math.asin(d.y))
                api.cinematic.toggle(viewer)
                core.log("action","RAIL_PAIR_WIRE_NATIVE_ART_READY")
              end)
            end)
            return
          end
          core.request_shutdown("Saved paid train about to cross the independent diagonal",false,0)
          return
        end
      end
      error("The owned train never boarded paying passengers")
    end
    expect(12,"rail_pair_contact_12_2_0")
    local seen,arrived=false,false
    for _=1,100 do
      Sim.daily(S)
      assert(Run.current_paid(S,saved.id))
      for f=0,74 do if Sim.rail_paid_pose(S,1,f/74,saved.id,true)==pair then seen=true end end
      if seen and Sim.company(S,owner).revenue>0 then arrived=true;break end
    end
    assert(seen and arrived,"The paid SH30 did not take the visual diagonal after restart")
    core.log("action","RAIL_PAIR_WIRE_NATIVE_PASS paid SH30 diagonals keep paired visual rail and wire after reopen")
    core.request_shutdown("Verified paired diagonal service",false,0)
  end
  core.after(0,function()
    core.emerge_area({x=0,y=-1,z=2},{x=48,y=5,z=38},function(_,_,n)
      if n==0 then core.after(0,verify) end
    end)
  end)
end
