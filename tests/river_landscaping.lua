-- Real LuanTTD terrain commands and water clock. No generated river auto-remake.
local function m(n) return dofile("mods/bayline/"..n..".lua") end
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
local s,c=interior(function(x) return x>=15 and 2 or 1 end)
for x=9,17 do water(s,x,12,"river",x*10) end
local function cell(x) return s.tiles[Sim.id(x,12)] end
local function wet(x) assert(cell(x).water_class=="river" and cell(x).stock_river_bits==x*10) end
local function dry(x) assert(cell(x).terrain=="grass" and not cell(x).water_class and not cell(x).stock_river_bits) end
-- A corner on the adjoining strip changes only its own four tiles.
fingers(s,c,"lower",10,11,250,1)
for x=9,17 do wet(x) end
-- Sharing a corner with an otherwise flat river changes exactly two river tiles.
fingers(s,c,"lower",12,12,20250,1)
for _,x in ipairs{9,10,13,14,15,16,17} do wet(x) end
dry(11);dry(12)
assert(T.tile(s.corner_grid,14,12)==3 and T.tile(s.corner_grid,15,12)==0)
-- Lowering a corner beside the inclined reach also propagates into an
-- adjacent high corner, which clears a third tile outside the initial four.
local dirty=fingers(s,c,"lower",14,12,30500,2)
local touched={}
for _,id in ipairs(dirty) do touched[id]=true end
assert(touched[Sim.id(15,12)])
dry(13);dry(14);dry(15)
wet(10);wet(16)
-- Raising back to the old local corner height does not re-create the stream.
fingers(s,c,"raise",14,12,250,1)
for _=1,5 do Sim.daily(s) end
for x=11,15 do dry(x) end
wet(10);wet(16)
assert(F.behaviour({kind="river",slope=0,base=0})=="none")
assert(F.behaviour({kind="river",slope=3,base=1})=="none")

-- A qualifying sea-level neighbor can flood a freshly erased river, but
-- the resulting water is stock coast/sea; the river class never regrows.
s,c=interior()
local _,cut=water(s,11,12,"river",113)
water(s,12,12,"sea")
local _,still=water(s,11,13,"river",249)
fingers(s,c,"raise",11,12,10250,1)
assert(cut.terrain=="grass" and not cut.stock_river_bits)
assert(W.visit(s,11,13)==0 and still.stock_river_bits==249)
assert(W.visit(s,12,12)>0)
assert(cut.terrain=="water" and cut.coastal_water and cut.water_class=="sea" and not cut.stock_river_bits)
assert(still.water_class=="river" and still.stock_river_bits==249)
print("PASS river landscaping: untouched adjacent, flat pair erased, inclined and propagated erase, no river refill, sea-only refill")
