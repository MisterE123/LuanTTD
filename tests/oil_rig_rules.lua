-- SPDX-License-Identifier: GPL-2.0-only
local rig=dofile("mods/luanttd_core/openttd/oil_rig.lua")
local function verify()
  local x,z=14,89
  local stamps,tries={},0
  local function stamp(u,v,def) stamps[u*4096+v]=def end
  local function clear() stamps={} tries=0 end
  local board={width=1024,height=256,freeform=true,industries={},
    tile=function(u,v)
      return stamps[u*4096+v] or {kind="water",water_class="sea",slope=0,base=0}
    end,
    clear=function(u,v,tile) tries=tries+1 return not tile.obstructed end}
  local quoted=assert(rig.quote(board,x,z))
  assert(#quoted.cells==6 and tries==6)
  assert(quoted.width==2 and quoted.height==3 and quoted.cells[2].gfx==24 and quoted.cells[2].z==z+1)
  assert(#rig.water_checks==52)
  -- Every individual stock WaterCheck is necessary; not every cell of
  -- the enclosing rectangle is a WaterCheck. Nothing is written by quote.
  for _,q in ipairs(rig.water_checks) do
    clear(); stamp(x+q[1],z+q[2],{kind="land",slope=0})
    assert(not rig.quote(board,x,z))
    clear(); stamp(x+q[1],z+q[2],{kind="water",slope=1})
    assert(not rig.quote(board,x,z))
  end
  clear(); stamp(x-3,z-2,{kind="land",slope=2})
  stamp(x-4,z,{kind="water",slope=0,vehicle=true,bridge=true})
  assert(rig.quote(board,x,z) and tries==6)
  for _,q in ipairs(rig.cells) do
    for _,f in ipairs({"vehicle","obstructed","bridge"}) do
      clear(); stamp(x+q[1],z+q[2],{kind="water",water_class="sea",slope=0,base=0,[f]=true})
      assert(not rig.quote(board,x,z))
    end
    clear(); stamp(x+q[1],z+q[2],{kind="water",water_class="sea",slope=15,base=0})
    assert(not rig.quote(board,x,z))
  end
  clear(); stamp(x,z,{kind="water",water_class="canal",slope=0,base=1})
  assert(not rig.quote(board,x,z))
  assert(not rig.quote(board,x,z,{editor=true}))
  assert(rig.quote(board,x,z,{editor=true,ignore_industry_restrictions=true}).cells[1].water_class=="canal")
  clear()
  assert(not rig.quote(board,4,z))
  assert(rig.quote(board,5,z))
  assert(rig.quote(board,127,z))
  assert(not rig.quote(board,128,z))
  assert(not rig.quote(board,893,z))
  assert(rig.quote(board,894,z))
  board.industries={{type=4,x=x+14,z=z+14}}
  assert(not rig.quote(board,x,z))
  board.industries[1].z=z+15
  assert(rig.quote(board,x,z))

  assert(rig.weight("random",{year=1959})==0)
  assert(rig.weight("random",{year=1960})==6)
  assert(rig.weight("random",{year=2000,landscape="arctic"})==0)
  assert(rig.weight("random",{year=1960,fund_only=true})==0)
  assert(rig.weight("mapgen",{year=2020})==0)
  assert(rig.acceptance(24,"passenger")==8 and rig.acceptance(25,"mail")==8)
  assert(rig.acceptance(24,"mail")==0 and rig.acceptance(28,"passenger")==0)
  assert(rig.airport.moving[0][1]==31 and rig.airport.depots==0 and not rig.airport.airplanes)
  local anchor={kind="industry",gfx=24,completed=true,industry=105,x=x,z=z,water_class="sea"}
  local other={kind="industry",gfx=24,completed=false,industry=105}
  assert(not rig.completed_station(anchor,other,false))
  assert(rig.completed_station(anchor,other,true).airport=="oilrig")
  other.industry=106; assert(not rig.completed_station(anchor,other,true))
  other.industry=105; other.gfx=25; assert(not rig.completed_station(anchor,other,true))
  assert(rig.station_catchment(105,false)[1]==105 and not rig.station_catchment(105,true))
end
if arg[1]=="dump" then
  for _,t in ipairs(rig.cells) do print(t[1],t[2],t[3]) end
  for _,t in ipairs(rig.water_checks) do print(t[1],t[2],"GFX_WATERTILE_SPECIALCHECK") end
  print("META",rig.spec.id,rig.spec.cost_factor,rig.spec.procurement_probability,rig.spec.map_colour,rig.spec.minimum,
    rig.spec.rates[1],rig.spec.rates[2],table.concat(rig.spec.appearance,","),table.concat(rig.spec.generation,","))
  for i=0,8 do print("MOVE",i,unpack(rig.airport.moving[i])) end
  local fta=dofile("mods/luanttd_core/openttd/airport_oil_rig.lua")
  print("HELIPORT",fta.delta_z,fta.catchment_radius,fta.W,fta.H,unpack(fta.entries,0,3))
  for i=0,8 do for _,r in ipairs(fta.layout[i]) do print("FTA",i,unpack(r)) end end
else
  verify()
  print("PASS RC1 Oil Rig #5: six-cell build plus exact water clearance, isolated quotes, 1960 availability, dock/heliport completion")
end
