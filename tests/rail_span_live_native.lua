-- Appended only to an isolated QA copy's init.lua. Exercise actual native
-- mount, construction, mapgen, mesh registration and span dispatch.
core.after(0,function()
  local W=assert(api.rail_spans)
  assert(api.rail_span_tools)
  local g=S.corner_grid
  for z=1,g.depth+1 do
    for x=1,g.width+1 do
      g.levels[(z-1)*(g.width+1)+x]=x>=14 and x<=18 and 5 or (x==7 or x==8) and 3 or 4
    end
  end
  local function id(x,z)return Sim.id(x,z or 10) end
  local owner="QA"
  for x=1,27 do
    local i=id(x)
    local _,h=api.terrain.tile(i)
    S.tiles[i]={h=h,terrain="grass",variant=1}
  end
  for _,x in ipairs({2,3,4,10,11,12,19,20,21,22,23,24}) do
    local t=S.tiles[id(x)];t.owner=owner;t.rail_tracks=1;t.build="stock_rail"
  end
  assert(api.trackworks.depot(S,owner,id(2),2))
  assert(api.trackworks.station(S,owner,id(22),id(24)))
  local station=S.tiles[id(22)].rail_station_id
  local q=assert(W.quote_bridge(S,owner,id(5),id(9)))
  local ok,why,changed,deck=W.commit(S,owner,q)
  assert(ok,why);api.render.raise_bound(deck)
  local tunnel=assert(W.quote_tunnel(S,owner,id(13)))
  assert(W.commit(S,owner,tunnel))
  -- Recorded stock portals form readonly conversion records even in the
  -- real native world; there is no active electric span/tool mount yet.
  local types=dofile(core.get_modpath("luanttd_core").."/openttd/rail_types.lua")
  local geom=dofile(core.get_modpath("luanttd_core").."/openttd/terrain.lua")
  local track=dofile(core.get_modpath("luanttd_core").."/openttd/rail_track.lua")
  local Wire=dofile(core.get_modpath("luanttd_core").."/rail_electrification_world.lua")(Sim,geom,track,types,W)
  local ctx={availability=function() return 3 end,span_art_ready=function() return true end}
  local quote_board={tile=function(at) return W.electric_record(S,at) end}
  local untouched=S.companies[owner].cash
  for _,sample in ipairs({{id(5),id(9),340,"bridge"},{id(13),id(18),408,"tunnel"}}) do
    local a,b,price,kind=unpack(sample)
    assert(W.electric_record(S,a).kind==kind and W.electric_record(S,b).other==a)
    for _,selection in ipairs({{a},{b},{a,b},{b,a}}) do
      local quote=assert(types.quote_convert(quote_board,selection,1,{owner=owner,available=3}))
      assert(quote.cost==price and #quote.updates==2)
    end
    assert(S.companies[owner].cash==untouched and W.electric_record(S,a).railtype==0)
    local copy=assert(core.deserialize(core.serialize(S),true))
    local offer=assert(Wire.quote(copy,owner,{b},1,ctx))
    local applied,debit,footprint=Wire.commit(copy,owner,offer,ctx)
    assert(applied and debit==price and #footprint==price/68 and copy.companies[owner].cash==untouched-price)
    local saved=assert(core.deserialize(core.serialize(copy),true))
    assert(W.electric_record(saved,a).railtype==1 and W.electric_record(saved,b).railtype==1)
    assert(saved.tiles[a].rail_type==nil and saved.tiles[b].rail_type==nil and S.companies[owner].cash==untouched)
  end
  core.emerge_area({x=8,y=1,z=20},{x=39,y=6,z=21},function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      api.render.update(changed)
      api.render.update({id(13),id(18)})
      local expected={
        {{x=10,y=5,z=20},"rail_bridge_wood_head_ramp_2"},
        {{x=14,y=5,z=20},"rail_bridge_wood_span_0"},
        {{x=14,y=4,z=20},"rail_bridge_wood_pier_0"},
        {{x=18,y=5,z=20},"rail_bridge_wood_head_ramp_0"},
        {{x=26,y=5,z=20},"rail_tunnel_portal_2"},
        {{x=36,y=5,z=20},"rail_tunnel_portal_0"},
      }
      local modpath=core.get_modpath("luanttd_core")
      for _,r in ipairs(expected) do
        local name="luanttd_core:stock_"..r[2]
        assert(core.get_node(r[1]).name==name,core.pos_to_string(r[1]).." expected "..name.."; got "..core.get_node(r[1]).name)
        local def=assert(core.registered_nodes[name])
        assert(def.drawtype=="mesh" and def.mesh=="bl_"..r[2]..".obj")
        local mesh=assert(io.open(modpath.."/models/"..def.mesh,"r"))
        mesh:close()
      end
      assert(api.rail_bridge_wire_art,"the native bridge art family is missing")
      local wired,payment,area=Wire.commit(S,owner,assert(Wire.quote(S,owner,{id(5)},1,ctx)),ctx)
      assert(wired and payment==340 and #area==5)
      api.render.update(area)
      local cables={"head_ramp_2","span_0_1","span_0_0","span_0_1","head_ramp_0"}
      local deck_nodes={"head_ramp_2","span_0","span_0","span_0","head_ramp_0"}
      for n=1,#cables do
        local x=8+2*n
        local name="luanttd_core:stock_rail_bridge_catenary_"..cables[n]
        local node=core.get_node({x=x,y=6,z=20})
        assert(node.name==name,node.name.." not "..name)
        assert(core.registered_nodes[name].mesh=="bl_rail_bridge_catenary_"..cables[n]..".obj")
        assert(core.get_node({x=x,y=5,z=20}).name=="luanttd_core:stock_rail_bridge_wood_"..deck_nodes[n])
      end
      local profile=dofile(core.get_modpath("luanttd_core").."/rail_bridge_wire_profile.lua")(
        Sim,W,api.rail_bridge_wire_art,track,function(at) local _,h=api.terrain.tile(at);return h end)
      local approach=S.tiles[id(4)]
      approach.rail_type=1
      local rows,axis,side=profile(S,id(5),8,false)
      assert(#rows==3 and axis=="x" and side==20.5)
      assert(rows[2][1]==9.5 and rows[2][3]==11.5)
      assert(math.abs(rows[2][2]-5.398)<1e-8 and math.abs(rows[2][4]-6.398)<1e-8)
      assert(not profile(S,id(7),8,false)) -- never infer upper wire for an unrelated lower-layer actor.
      assert(#profile(S,id(7),8,true)==3)
      approach.rail_type=nil
      local reverted,fee,affected=Wire.commit(S,owner,assert(Wire.quote(S,owner,{id(9)},0,ctx)),ctx)
      assert(reverted and fee==60 and #affected==5)
      api.render.update(affected)
      for n=1,#cables do
        assert(core.get_node({x=8+2*n,y=6,z=20}).name=="air")
      end
      local ok,note= W.start(S,owner,id(2),station)
      assert(ok,note)
      local Run=assert(api.rail_dispatch_controller)
      local flags={}
      for _=1,3000 do
        local events=Run.tick(S)
        local d=Run.current(S)
        assert(not d.failure,d.failure)
        for _,e in ipairs(events) do flags[e.kind]=true end
        if flags.arrived then break end
      end
      assert(flags.span_exited and flags.span_released and flags.tunnel_hidden and flags.tunnel_revealed and flags.arrived)
      core.log("action","RAIL_SPAN_LIVE_NATIVE_PASS")
      core.request_shutdown("Isolated rail span QA complete",false,0)
    end)
  end)
end)
