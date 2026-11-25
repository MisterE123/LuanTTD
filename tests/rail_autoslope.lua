local root="mods/luanttd_core/openttd/"
local function get(n)return dofile(root..n..".lua")end
local Track=get("rail_track")
local R=get("rail_autoslope")(Track,get("slope"))
local q=assert(R.quote(1,7,0,0,1))
assert(q.price==250 and not q.barren)
assert(not R.quote(1,7,0,0,2))
assert(not R.quote(1,7,0,0,1,{autoslope=false}))
for _,x in ipairs({{4,2,1},{8,8,3},{16,4,2},{32,1,0}}) do
  local row=assert(R.quote(x[1],0,1,x[2],1,{autoslope=false}))
  assert(row.price==0 and row.barren and row.free_corner==x[3])
end
assert(not R.quote(4,0,1,2,1,{half_water=true}))
print("PASS dry RC1 plain rail quote: retained straight surface, four free corners, and wet guard")

local Sim=dofile("mods/luanttd_core/sim.lua")
local Terrain,Height=get("terrain"),get("rail_height")(Track,get("slope"))
local Parts=dofile("mods/luanttd_core/packed_campaign.lua")
local owner="Survey Company"
local x,z=8,9
local id=Sim.id(x,z)
local function world(bits,notch,ground)
  local s=Sim.new(1751)
  for idx in pairs(s.tiles) do s.tiles[idx]={terrain="grass",h=1,variant=0} end
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(u,v)
    return notch and u==x and v==z and 0 or 1
  end)
  local t={terrain="grass",h=notch and 0 or 1,variant=0,build="stock_rail",
    owner=owner,rail_tracks=bits,rail_ground=ground or 1}
  s.tiles[id]=t
  return s,t,Sim.company(s,owner)
end
do
  local s,t,c=world(1,true)
  local cash=c.cash
  local ok,price,receipt=Sim.landscape(s,owner,"raise",x,z,nil,nil,false,"footprint")
  assert(ok and price==500 and #receipt.corners==1 and c.cash==cash and t.rail_ground==1)
  assert(Terrain.corner(s.corner_grid,x,z)==0)
  assert(Sim.landscape(s,owner,"raise",x,z) and c.cash==cash-500 and t.rail_ground==1)
  local shape,base=Terrain.tile(s.corner_grid,x,z)
  assert(Height.profile({kind="rail",trackbits=1},base,shape).base_level==1)
  assert(not Sim.landscape(s,owner,"raise",x,z) and c.cash==cash-500)
end
local selection={{4,1,1},{8,0,0},{16,0,1},{32,1,0}}
for _,case in ipairs(selection) do
  local s,t,c=world(case[1])
  local u,v=x+case[2],z+case[3]
  local cash=c.cash
  s.stock_road_town_policy={autoslope=false}
  local ok,price=Sim.landscape(s,owner,"raise",u,v,nil,nil,false,true)
  assert(ok and price==250 and t.rail_ground==1 and c.cash==cash)
  assert(Sim.landscape(s,owner,"raise",u,v,u+1,v))
  assert(t.rail_tracks==case[1] and t.rail_ground==0)
  local restored=Parts.decode(Parts.encode(s)).tiles[id]
  assert(restored.rail_tracks==case[1] and restored.rail_ground==0)
end
do
  local s,t,c=world(4,false,13)
  local cash=c.cash
  assert(not Sim.landscape(s,owner,"raise",x+1,z+1))
  assert(c.cash==cash and t.rail_ground==13 and Terrain.corner(s.corner_grid,x+1,z+1)==1)
end
do
  local s,t,c=world(4)
  t.rail_type=1
  local cash=c.cash
  local ok,error=Sim.landscape(s,owner,"raise",x+1,z+1)
  assert(not ok and error:find("only on ordinary rail",1,true))
  assert(cash==c.cash and t.rail_ground==1 and t.rail_type==1)
end
print("PASS authoritative dry rail preview, commit, drag, rejected reshape and checkpoint")
