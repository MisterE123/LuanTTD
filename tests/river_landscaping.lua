-- Real LuanTTD terrain commands and water clock. No generated river auto-remake.
local function m(n) return dofile("mods/luanttd_core/"..n..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local F=m("openttd/water_flood")
local W=m("water_flood_world")(Sim,T,F)
local function interior(heights)
  local s=Sim.new(1751)
  s.corner_grid=T.new(Sim.W,Sim.H,heights,{freeform_edges=true})
  for i in ipairs(s.tiles) do
    local x,z=Sim.xy(i)
    local _,h=T.tile(s.corner_grid,x,z)
    s.tiles[i]={terrain="grass",variant=0,h=h}
  end
  s.sites,s.stations,s.fleet={},{},{}
  s.road_economy,s.road_stock_house_supply=true,true
  Sim.mount_coastal_flood(s)
  return s,Sim.company(s,"River Tester")
end
local function water(s,x,z,kind,byte)
  local id=Sim.id(x,z)
  local t=s.tiles[id]
  t.terrain,t.water_class,t.stock_river_bits="water",kind,byte
  return id,t
end
local function fingers(s,company,mode,x,z,charge,changed_corners)
  local before=s.corner_grid.revision
  local cash=company.cash
  local ok,price,quote=Sim.landscape(s,"River Tester",mode,x,z,nil,nil,nil,"footprint")
  assert(ok and price==charge,tostring(price))
  assert(#quote.corners==changed_corners)
  assert(before==s.corner_grid.revision and cash==company.cash)
  local built,msg,dirty=Sim.landscape(s,"River Tester",mode,x,z)
  assert(built,msg)
  assert(company.cash==cash-charge and #dirty==#quote.tiles)
  return dirty
end
local function refuse(s,c,mode,x,z,u,v)
  local before,cash,topology,quota=s.corner_grid.revision,c.cash,s.topology,c.clear_limit
  for _,quote in ipairs{"footprint",false} do
    local ok,why=Sim.landscape(s,"River Tester",mode,x,z,u,v,false,quote)
    assert(not ok and why:find("remove the river",1,true),tostring(why))
    assert(s.corner_grid.revision==before and c.cash==cash and s.topology==topology and c.clear_limit==quota)
  end
end
local s,c=interior(function(x) return x>=15 and 2 or 1 end)
for x=9,17 do water(s,x,12,"river",x*10) end
local function cell(x) return s.tiles[Sim.id(x,12)] end
local function wet(x) assert(cell(x).water_class=="river" and cell(x).stock_river_bits==x*10) end
-- Touching the next row, but not the river corner, remains ordinary work.
fingers(s,c,"lower",10,11,250,1)
refuse(s,c,"lower",12,12)
refuse(s,c,"raise",12,12)
refuse(s,c,"lower",12,12,12,12)
refuse(s,c,"lower",14,12)
for x=9,17 do wet(x) end
-- A multi-corner drag still completes eligible corners in the same
-- gesture; rejected approaches do not consume cash or clear river.
local cash=c.cash
local ok,price,plan=Sim.landscape(s,"River Tester","raise",6,12,10,12,false,"footprint")
assert(ok and #plan.corners==3 and price==750,tostring(price))
assert(Sim.landscape(s,"River Tester","raise",6,12,10,12))
assert(c.cash==cash-750 and T.corner(s.corner_grid,8,12)==2 and T.corner(s.corner_grid,9,12)==1)
for x=9,17 do wet(x) end
assert(T.tile(s.corner_grid,14,12)==3 and T.tile(s.corner_grid,15,12)==0)

-- The only river is beyond the initial four affected tiles. OpenTTD's
-- recursive grade propagation still reaches it and rejects the command.
local recursive,cc=interior(function(x) return x>=15 and 2 or 1 end)
local at,far=water(recursive,15,12,"river",150)
refuse(recursive,cc,"lower",14,12)
assert(far.water_class=="river" and far.stock_river_bits==150)
local t={id=1,tile=Sim.id(18,10),kind="town",name="River town"}
recursive.sites[1]=t
local before,topology=cc.cash,recursive.topology
local q,cost=Sim.plan(recursive,"River Tester","clear",{at,at})
assert(q and cost==10000 and #q==1 and not cc.stock_town_authority_ratings)
assert(Sim.build(recursive,"River Tester","clear",{at,at}))
assert(cc.cash==before-10000 and recursive.topology==topology+1)
assert(cc.stock_town_authority_ratings[1]==300)
assert(not far.water_class and not far.stock_river_bits)
local dirty=fingers(recursive,cc,"lower",14,12,500,2)
local reached
for _,id in ipairs(dirty) do if id==at then reached=true end end
assert(reached,"The previously rejected corner did affect the far tile")
recursive.sites[1]=nil -- the synthetic council is not a full generated town
for _=1,5 do Sim.daily(recursive) end
assert(not far.water_class and not far.stock_river_bits)

-- Separate sea flooding remains possible after explicit river removal;
-- it produces sea/shore water, not a regenerated river.
s,c=interior()
local erase,cut=water(s,11,12,"river",113)
water(s,12,12,"sea")
local _,still=water(s,11,13,"river",249)
refuse(s,c,"raise",11,12)
assert(Sim.clear_water(s,"River Tester",erase))
fingers(s,c,"raise",11,12,250,1)
assert(cut.terrain=="grass" and not cut.stock_river_bits)
assert(W.visit(s,11,13)==0 and still.stock_river_bits==249)
assert(W.visit(s,12,12)>0)
assert(cut.terrain=="water" and cut.coastal_water and cut.water_class=="sea" and not cut.stock_river_bits)
assert(still.water_class=="river" and still.stock_river_bits==249)
assert(F.behaviour({kind="river",slope=0,base=0})=="none")
assert(F.behaviour({kind="river",slope=3,base=1})=="none")
print("PASS RC1 river terraforming: nearby edit, flat/slope/recursive refusal, atomic quote, explicit demolition, town rating, separate flood")
