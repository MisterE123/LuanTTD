local p="mods/bayline/"
local function m(n) return dofile(p..n..".lua") end
local S,T=m("sim"),m("openttd/terrain")
local function value(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function sample(freeform)
  local s=S.new(1751)
  for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=0,variant=0} end
  s.sites,s.fleet,s.stations={},{},{}
  s.road_economy,s.road_stock_house_supply=true,true
  s.corner_grid=T.new(S.W,S.H,function(x,z)
    return (x==8 and z==8 or x==11 and (z==8 or z==9)) and 1 or 0
  end,{freeform_edges=freeform})
  return s
end
local s=sample(true)
local function put(w,x,z,kind,who)
  local id=S.id(x,z)
  local t=w.tiles[id]
  t.terrain,t.water_class,t.owner="water",kind,who
  if kind=="canal" then t.build,t.stock_canal="canal",true end
  if kind=="coast" then t.coastal_water,t.water_class=true,"sea" end
  return id,t
end
local a,sea=put(s,5,5,"sea","water")
local b,river=put(s,6,5,"river")
river.stock_river_bits=109
local lone,shallow=put(s,8,8,"coast","other")
local edge,dry=put(s,10,8,"coast","other")
local C=S.company(s,"A")
local function clear(ids,price)
  local q,cost=S.plan(s,"A","clear",ids)
  assert(q,cost);value(cost,price)
  local money,topology= C.cash,s.topology
  local ok,note,changed=S.build(s,"A","clear",ids)
  assert(ok,note);value(C.cash,money-price);value(s.topology,topology+1)
  for i,id in ipairs(changed) do value(s.tiles[id].terrain,"grass");value(changed[i],q[i].id) end
end
clear({a,b,b,lone,edge},30040)
assert(not river.stock_river_bits and not sea.owner and not shallow.coastal_water and not dry.coastal_water)
assert(T.corner(s.corner_grid,8,8)==1,"Direct clear changes water type, not corner heights")

local canal,water=put(s,15,15,"canal","A")
C.water_infrastructure=1
local ok,why=S.landscape(s,"A","raise",15,15)
assert(not ok and why:find("canal",1,true))
local denied,note=S.build(s,"B","clear",{canal})
assert(not denied and note:find("owns",1,true))
clear({canal},5000)
assert(not water.stock_canal and not water.build and not water.water_class)
value(C.water_infrastructure,0)
assert(S.landscape(s,"A","raise",15,15),"Canal demolition unlocks the ordinary terrain edit")

-- Passive flooding is independent of stock road economy, and so is the
-- legality of clearing the water in a real terrain command.
assert(not s.stock_coastal_flood)
local wet,t=put(s,21,21,"sea","none")
local near=(put(s,22,22,"river"))
local quoted,price=S.landscape(s,"A","raise",21,21,nil,nil,nil,true)
assert(quoted);value(price,10250)
assert(S.landscape(s,"A","raise",21,21))
value(t.terrain,"grass");value(s.tiles[near].terrain,"water")

do
  local room=sample(false)
  local border=put(room,S.W-1,10,"sea")
  local legal=put(room,S.W-2,10,"sea")
  local north=put(room,1,10,"river")
  for _,id in ipairs{border,north} do
    local yes,why=S.build(room,"A","clear",{id})
    assert(not yes and why:find("edge",1,true))
  end
  assert(S.build(room,"A","clear",{legal}))
end

-- Dirtied MP_VOID stores a height but is not billed or converted to
-- ordinary ground. Clicking it with the Bulldozer stays forbidden.
local inland,inside=put(s,2,5,"sea")
local border,outer=put(s,1,5,"sea")
outer.stock_void=true
local void_yes,void_note=S.build(s,"A","clear",{border})
assert(not void_yes and void_note:find("playable",1,true))
local qyes,qcost=S.landscape(s,"A","raise",2,5,nil,nil,nil,true)
assert(qyes);value(qcost,10250)
assert(S.landscape(s,"A","raise",2,5))
assert(outer.stock_void and outer.terrain=="water" and inside.terrain=="grass")
assert(T.corner(s.corner_grid,2,5)==1)

-- Keep actual simulated vessel/current-route and infrastructure guards
-- while permitting unrelated water elsewhere. No global active-run veto.
local occupied=put(s,24,23,"sea")
local reserved=put(s,25,23,"sea")
local elsewhere=put(s,27,23,"sea")
local layered=put(s,28,23,"sea")
s.stock_coal_ship_run={vehicle={tile=occupied,path={{tile=occupied},{tile=reserved}},path_index=2}}
s.aqueduct_above={[layered]=1}
for _,id in ipairs{occupied,reserved,layered} do
  local money=C.cash
  local ok,msg=S.build(s,"A","clear",{id})
  assert(not ok and (msg:find("vessel",1,true) or msg:find("structure",1,true)))
  value(C.cash,money);value(s.tiles[id].terrain,"water")
end
clear({elsewhere},10000)
print("PASS ordinary water Bulldozer and Raise: stock prices, ownership/no-flood opt-out, exact border/void, vessel route and protected layers")
