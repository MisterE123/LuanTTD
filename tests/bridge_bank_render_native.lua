-- Road bridge across real, opposed coastal slopes in the production renderer.
local terrain=dofile(mod.."/openttd/terrain.lua")
local track=dofile(mod.."/openttd/rail_track.lua")
local water=dofile(mod.."/openttd/ship_follow.lua")(track)
local facilities=dofile(mod.."/openttd/ship_facilities.lua")(track,water)
local port=dofile(mod.."/ship_network.lua")(Sim,terrain,water,facilities)
local lo,hi,z,modern,rail,dry,aqua=11,17,14,18,22,26,24
local function id(x,a) return assert(Sim.id(x,a)) end
local new=terrain.new(Sim.W,Sim.H,function(x,row)
  -- A bend in the coast next to the timber abutment exposes its
  -- side, unlike a perfectly straight coast where the bank hides it.
  if row==z-1 and x==lo or row==z+2 and x==hi+1 then return 0 end
  return (x<=lo or x>=hi+1) and 1 or 0
end)
S.corner_grid.levels=new.levels
local dirty={}
local field_x=math.floor((lo+hi)/2)
S.stock_farm_fields={}
local field_rows={[dry]=true,[rail]=true,[aqua]=true}
for a=1,Sim.H do for x=1,Sim.W do
  local k=id(x,a)
  local slope,h=terrain.tile(S.corner_grid,x,a)
  local sea=x>=lo and x<=hi and a~=dry and not (x==field_x and field_rows[a])
  S.tiles[k]={terrain=sea and "water" or "grass",variant=(x+a)%4,h=h,
    water_class=sea and "sea" or nil,coastal_water=sea and slope~=0 or nil}
  if x==field_x and field_rows[a] then
    S.stock_farm_fields[k]={kind="clear",ground="field",base=h,slope=slope,variant=4,
      counter=7,fences={[0]=3,[1]=3,[2]=3,[3]=3}}
  end
  if x>=lo-5 and x<=hi+5 and a>=z-7 and a<=dry+2 then dirty[#dirty+1]=k end
end end
S.speed=0
local owner="PierQA"
Sim.company(S,owner).cash=200000
local before=table.concat(S.corner_grid.levels,",")
local buoy_x=field_x+1
for _,row in ipairs({z,rail}) do assert(port.build(S,owner,"buoy",id(buoy_x,row))) end
for _,build in ipairs({{z,0},{modern,2},{dry,0}}) do
  local yes,note,_,deck=Sim.road_bridge(S,owner,id(lo,build[1]),id(hi,build[1]),build[2])
  assert(yes,note);assert(deck==1)
  assert(not S.tiles[id(lo,build[1])].coastal_water and not S.tiles[id(hi,build[1])].coastal_water)
end
local quote,why=api.rail_spans.quote_bridge(S,owner,id(lo,rail),id(hi,rail))
assert(quote,why)
assert(quote.site_cost==80)
assert(api.rail_spans.commit(S,owner,quote))
assert(not S.tiles[id(lo,rail)].coastal_water and not S.tiles[id(hi,rail)].coastal_water)
assert(api.aqueduct.build(S,owner,id(lo,aqua),id(hi,aqua)))
assert(port.build(S,owner,"buoy",id(buoy_x,aqua)))
assert(table.concat(S.corner_grid.levels,",")==before,"Construction altered neighboring corners")
api.render.raise_bound(1)
local ready=false
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  local first,last={x=2*(lo-5),y=-1,z=2*(z-7)},{x=2*(hi+5),y=6,z=2*(dry+3)}
  core.emerge_area(first,last,function(_,_,left)
    if left~=0 then return end
    api.render.update(dirty)
    local function node(x,y,a,dx,dz)
      return core.get_node({x=x*2+dx,y=y,z=a*2+dz}).name
    end
    for _,mode in ipairs({{z,"road_bridge_wood"},{modern,"road_bridge_girder"},{rail,"rail_bridge_wood"},{dry,"road_bridge_wood"}}) do
      local zg,stem=mode[1],mode[2]
      for _,x in ipairs({lo,hi}) do
        local deck=node(x,1,zg,0,0)
        assert(deck:find("stock_"..stem.."_head_flat",1,true),deck)
        local want=zg==dry and "bridge_bank_" or "bridge_shore_"
        local shape=node(x,1,zg,1,0)
        assert(shape:find(want,1,true),shape)
        for dx=0,1 do for dz=0,1 do
          local support=node(x,0,zg,dx,dz)
          assert(zg==dry and support=="luanttd_core:slope_fill_open" or
            zg~=dry and support:find("ocean_top",1,true),support)
        end end
      end
    end
    for _,row in ipairs({{dry,"road_bridge_wood"},{rail,"rail_bridge_wood"},{aqua,"aqueduct"}}) do
      local a,stock=row[1],row[2]
      assert(node(field_x,1,a,0,0):find(stock,1,true),node(field_x,1,a,0,0))
      local shifted=node(field_x,1,a,1,0)
      assert(shifted=="luanttd_core:farm_ground_0_4_shifted",shifted)
      local def=assert(core.registered_nodes[shifted])
      assert(def.mesh=="bl_farm_land_0_shifted.obj" and def.walkable)
    end
    for _,mode in ipairs({{z,"road_bridge_wood"},{rail,"rail_bridge_wood"},{aqua,"aqueduct"}}) do
      local row,mesh=mode[1],mode[2]
      local anchor=node(buoy_x,1,row,0,0)
      local buoy=node(buoy_x,1,row,1,0)
      assert(anchor:find(mesh,1,true),anchor)
      assert(buoy=="luanttd_core:ship_buoy_under",buoy)
      assert(core.registered_nodes[buoy].mesh=="bl_ship_buoy_under.obj")
    end
    assert(port.remove(S,owner,id(buoy_x,z)))
    api.render.update({id(buoy_x,z)})
    assert(node(buoy_x,1,z,0,0):find("road_bridge_wood",1,true))
    assert(node(buoy_x,1,z,1,0)~="luanttd_core:ship_buoy_under")
    assert(port.build(S,owner,"buoy",id(buoy_x,z)))
    api.render.update({id(buoy_x,z)})
    assert(node(buoy_x,1,z,1,0)=="luanttd_core:ship_buoy_under")
    core.log("action","BRIDGE_WATER_FACILITIES_NATIVE_READY visible shifted buoys and independent decks, interactive scene retained")
    core.log("action","BRIDGE_FARM_FIELDS_NATIVE_READY three decks and living crop ground coexist")
    assert(node((lo+hi)/2,0,z,0,0):find("ocean_top",1,true),"true water under the span must remain")
    assert(node(lo,0,z+1,0,0):find("ocean_top",1,true),"unbuilt adjacent coast must keep genuine sea")
    local inside=id(lo+1,dry)
    S.tiles[inside].terrain,S.tiles[inside].water_class="water","sea"
    api.render.update({inside})
    assert(node(lo,1,dry,1,0):find("bridge_shore_",1,true),"changing inward neighbor must repaint the head")
    S.tiles[inside].terrain,S.tiles[inside].water_class="grass",nil
    api.render.update({inside})
    assert(node(lo,1,dry,1,0):find("bridge_bank_",1,true))
    p:override_day_night_ratio(.92)
    ready=true
    core.log("action","BRIDGE_BANK_NATIVE_READY coastal timber, girder and rail heads match stock shore; dry control, deck, terrain and adjacent sea preserved")
  end)
end)
local old
core.register_globalstep(function()
  if not ready then return end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local mode=f:read("*l");f:close()
  local p=core.get_player_by_name(owner)
  if not p or old==mode or not ({left_bank=true,right_bank=true,modern=true,rail=true,upper=true,fields=true,buoy=true})[mode] then return end
  old=mode
  local x=mode=="right_bank" and hi or lo
  local zg=mode=="modern" and modern or mode=="rail" and rail or z
  local d=x==lo and 1 or -1
  local from={x=x*2+d*4.1,y=.54,z=zg*2-4.7}
  if mode=="upper" then from={x=x*2+d*2.1,y=3.0,z=zg*2-3.9} end
  local to={x=x*2+.5,y=1.17,z=zg*2+.5}
  if mode=="fields" then
    from={x=field_x*2+2.2,y=1.5,z=aqua*2-2.5}
    to={x=field_x*2,y=1.1,z=aqua*2}
  end
  if mode=="buoy" then
    from={x=buoy_x*2+1.7,y=-.78,z=aqua*2-3.2}
    to={x=buoy_x*2+.35,y=.93,z=aqua*2+.52}
  end
  local dx,dy,dz=to.x-from.x,to.y-from.y-1.625,to.z-from.z
  p:set_pos(from)
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  p:hud_set_flags({hotbar=false,crosshair=false})
  core.log("action","BRIDGE_BANK_NATIVE_VIEW "..mode)
end)
