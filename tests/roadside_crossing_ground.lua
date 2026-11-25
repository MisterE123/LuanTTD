local root="mods/luanttd_core/"
local function get(n) return dofile(root..n..".lua") end
local Ground=get("openttd/road_crossing_ground")
local Details=get("openttd/roadside_details")
local Sim,Terrain,Track=get("sim"),get("openttd/terrain"),get("openttd/rail_track")
local Crossing=get("openttd/level_crossing")(Track)
local W=get("level_crossing_world")(Sim,Terrain,Crossing,Track)
local P=get("campaign_terrain_projection")
local nodes={}
local function register(n,tiles,def)
  assert(not nodes[n],"duplicate node registration: "..n)
  nodes[n]={tiles=tiles,def=def};return n
end
local V=get("roadside_temperate_view")({},Sim,{},nil,register,function(n)return n end,Details,Track,function(n)return n end,function()return {}end)
assert(Ground.temperate(nil)=="barren")
assert(Ground.temperate("barren")=="barren" and Ground.temperate("grass")=="grass")
for _,state in ipairs({"paved","street_lights","trees","grass_works","paved_works"}) do
  assert(Ground.temperate(state)=="paved")
end
assert(V.tram_ground({roadside="grass"},0,"none")=="pure_tram_grass")
assert(V.tram_ground({},0,"leveled")=="pure_tram_barren_retaining")
assert(V.tram_ground({roadside="barren"},3,"none")=="pure_tram_barren_normal_3")
assert(V.tram_ground({roadworks="grass",roadside="paved"},12,"leveled")=="pure_tram_grass_foundation_12")
assert(V.tram_ground({roadworks="paved",roadside="grass"},12,"none")==nil)
assert(V.tram_ground({roadside="trees"},0,"none")==nil)
assert(nodes.pure_tram_grass_normal_3.def.mesh=="bl_land_3.obj")
assert(nodes.pure_tram_barren_foundation_6.def.mesh=="bl_road_grade_foundation_6.obj")
local s=Sim.new(1751)
s.stock_generated_profile={}
s.level_crossing_enabled=true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
local owner="Aspect Company"
Sim.company(s,owner)
local id=Sim.id(6,7)
s.tiles[id]={build="road",terrain="grass",road_bits=10,owner=owner,h=0,variant=1,roadside="paved",stock_roadside_town=9}
local ctx={vehicles_at=function()return {}end,reserved=function()return false end}
assert(W.commit(s,owner,assert(W.quote(s,owner,id,{kind="rail",track=1},ctx)),ctx))
local t=s.tiles[id]
assert(t.roadside=="barren" and t.stock_roadside_town==nil and t.level_crossing.barred)
t.roadside="trees"
local ground=P.tile(t)
assert(ground.level_crossing.rail_axis==1 and ground.roadside=="trees" and Ground.temperate(ground.roadside)=="paved")
assert(W.commit(s,owner,assert(W.quote(s,owner,id,{kind="tram",pieces=10,tramtype=1},ctx)),ctx))
assert(t.roadside=="trees")
local q=assert(W.rail_remove_quote(s,owner,id,ctx))
W.rail_remove_apply(s,q)
assert(not t.level_crossing and t.tram and t.roadside=="barren")
print("PASS RC1 crossing surface reset and projections; pure-tram grass/barren/paved variants and stock grades")

-- Both normal build directions must accept exactly the pin's seven
-- VALID_LEVEL_CROSSING_SLOPES. Source slopes 15 and invalid steep values
-- cannot occur in a shared-corner tile, so exercise only actual shapes.
local Runtime=get("level_crossing_runtime")(Sim,W)
local normal={tile=function()end,adjacent=function()end}
local accepted={[0]=true,[5]=true,[7]=true,[10]=true,[11]=true,[13]=true,[14]=true}
s.road_economy,s.road_stock_clock=true,true
local function height(bit,mask)
  local v=math.floor(mask/bit)%2
  if mask>=16 then
    local highest=({[23]=2,[27]=1,[29]=8,[30]=4})[mask]
    if highest==bit then v=2 end
  end
  return v
end
for _,mask in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,23,27,29,30}) do
  local x,z=Sim.xy(id)
  local width=s.corner_grid.width+1
  local at=(z-1)*width+x
  local cells=s.corner_grid.levels
  cells[at],cells[at+1],cells[at+width],cells[at+width+1]=height(8,mask),height(1,mask),height(4,mask),height(2,mask)
  assert(Terrain.tile(s.corner_grid,x,z)==mask)
  for _,kind in ipairs({"rail","road"}) do
    s.tiles[id]=kind=="rail" and {build="road",terrain="grass",owner=owner,road_bits=10} or
      {build="stock_rail",terrain="grass",owner=owner,rail_tracks=2}
    local request=kind=="rail" and {kind=kind,track=1} or {kind=kind,pieces=10}
    local q,why=Runtime.quote(s,owner,id,request,normal)
    assert((not not q)==(not not accepted[mask]),kind.." "..mask..": "..tostring(why))
    if q then
      assert(q.crossing.top==(mask==0 and 0 or 1))
      assert(q.crossing.foundation==(mask==0 and "none" or "flattened"))
      assert(q.price==(kind=="rail" and 100 or 190))
    else assert(why=="LAND_SLOPED_IN_WRONG_DIRECTION",why) end
  end
end
print("PASS ordinary road and rail crossing quotes use every legal RC1 crossing slope and no other")

-- Autoslope can reshape the dirt under a crossing without changing the
-- travel deck, clearing its infrastructure, or spending money on quote.
local x,z=Sim.xy(id)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u,v)
  if u==x and v==z then return 0 end
  return 1
end)
s.tiles[id]={build="road",owner=owner,terrain="grass",road_bits=10,h=0,variant=0}
local cquote=assert(Runtime.quote(s,owner,id,{kind="rail",track=1},normal))
assert(Runtime.commit(s,owner,cquote,normal))
Sim.mount_crossings(s,Runtime,function()return normal end)
local record=s.tiles[id].level_crossing
assert(record.top==1 and record.slope==7 and record.foundation=="flattened")
record.reserved,record.barred=true,true
local cash=Sim.company(s,owner).cash
local rev=s.corner_grid.revision
local ok,price=Sim.landscape(s,owner,"raise",x,z,nil,nil,false,true)
assert(ok and price==500)
assert(Sim.company(s,owner).cash==cash and s.corner_grid.revision==rev and record.slope==7)
assert(Sim.landscape(s,owner,"raise",x,z))
assert(record==s.tiles[id].level_crossing and record.slope==0 and record.foundation=="none" and record.top==1)
assert(Sim.road_center_z(s,id)==8 and Runtime.rail_board(s,normal).stock_height(id,0,0)==8)
assert(record.reserved and record.barred and Sim.company(s,owner).cash==cash-500)
assert(Sim.landscape(s,owner,"lower",x,z))
assert(record.slope==7 and record.foundation=="flattened" and s.tiles[id].h==0)
assert(record.top==1 and record.reserved and record.barred and Sim.company(s,owner).cash==cash-1000)
local s_rev,s_top=s.corner_grid.revision,s.topology
local permit,msg=Sim.landscape(s,owner,"raise",x,z+1)
assert(not permit and msg:find("Keep the crossing deck",1,true))
s.stock_road_town_policy={autoslope=false}
assert(not Sim.landscape(s,owner,"raise",x,z))
assert(s.corner_grid.revision==s_rev and s.topology==s_top and Sim.company(s,owner).cash==cash-1000)
print("PASS priced stock autoslope changes dirt under a reserved crossing without moving either way or its reservation")
