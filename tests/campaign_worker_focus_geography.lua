-- Only the native QA fixture places this housing geometry. All roads,
-- purchases, traffic, station supply, payment and recovery are real.
return function(core,s,Sim,mod)
  local T=dofile(mod.."/openttd/terrain.lua")
  local x,z
  for zz=8,Sim.H-8 do
    for xx=8,Sim.W-21 do
      local flat,base=true,nil
      for v=zz-3,zz+3 do for u=xx,xx+11 do
        local id=Sim.id(u,v)
        local t=s.tiles[id]
        local mask,h=T.tile(s.corner_grid,u,v)
        -- Fields use a separate occupancy index and may look like bare ground.
        if mask~=0 or base and base~=h or not t or t.build or t.site or t.house or t.owner
          or t.stock_industry or t.stock_landmark or t.stock_void or t.terrain=="water"
          or s.stock_farm_fields and s.stock_farm_fields[id] then flat=false end
        base=h
      end end
      if flat then x,z=xx,zz;break end
    end
    if x then break end
  end
  assert(x,"no empty rectangle for the isolated focus test's stock town housing")
  local next_id=#s.sites+1
  for stop=1,2 do
    local id=next_id+stop-1
    local center=x+(stop==1 and 2 or 8)
    local place=Sim.id(center,z+2)
    s.sites[id]={id=id,kind="town",name=stop==1 and "Window Vale" or "Return Cross",
      tile=place,population=450,stock={},produced={},received={},service=0}
    for dx=0,1 do for _,dz in ipairs({-2,-1,1,2}) do
      local tile=s.tiles[Sim.id(center+dx,z+dz)]
      tile.wood=nil
      tile.house=true
      tile.source_house={id=4,town=id,completed=true}
    end end
  end
  for i=0,10 do s.tiles[Sim.id(x+i,z)].wood=nil end
  -- A closed route lets stock road vehicles return without depending on
  -- endpoint reversal in this focus/recovery test.
  for i=1,10 do s.tiles[Sim.id(x+i,z+3)].wood=nil end
  for dz=1,2 do
    s.tiles[Sim.id(x+1,z+dz)].wood=nil
    s.tiles[Sim.id(x+10,z+dz)].wood=nil
  end
  -- Keep the depot off the main axis so the two dead ends remain
  -- ordinary pavement. This specifically does not test non-order depot entry.
  for dz=-3,-1 do s.tiles[Sim.id(x+1,z+dz)].wood=nil end
  if core.settings:get_bool("luanttd_native_municipal_road",false) then
    local town=s.sites[next_id].id
    for ix=x+4,x+6 do
      local t=s.tiles[Sim.id(ix,z+1)]
      t.build,t.road_bits,t.road_town,t.wood="road",10,town,nil
    end
  end
  local fields={Sim.id(x+1,z-3),Sim.id(x+1,z),Sim.id(x+10,z),Sim.id(x+2,z),Sim.id(x+8,z),
    Sim.id(x+1,z+3),Sim.id(x+10,z+3),Sim.id(x,z),Sim.id(x+1,z-2)}
  assert(core.safe_file_write(core.get_worldpath().."/native-focus-layout",table.concat(fields,"\n")))
end
