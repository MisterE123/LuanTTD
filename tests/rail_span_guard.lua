-- A separate bridge/tunnel layer cannot be deleted or replaced by old tools.
local root="mods/bayline/"
local function m(p) return dofile(root..p..".lua") end
local S=m("sim")
local T=m("openttd/terrain")
local s=S.new(1751)
s.corner_grid=T.new(S.W,S.H,function() return 0 end)
for _,t in ipairs(s.tiles) do
  t.terrain,t.h="grass",0;t.wood,t.house,t.site,t.build,t.owner=nil,nil,nil,nil,nil
end
local id=function(x,z) return S.id(x,z or 10) end
local h,b,u=id(5),id(7),id(10)
s.tiles[h].build,s.tiles[h].owner,s.tiles[h].rail_span_id="stock_rail_bridge","A",1
s.rail_bridge_above={[b]=1}
s.rail_tunnel_below={[u]=2}
for _,k in ipairs({h,b,u}) do
  assert(S.rail_span_protected(s,k))
  for _,tool in ipairs({"clear","road","road_station","road_depot"}) do
    local plan,why=S.plan(s,"A",tool,{k})
    assert(not plan and why:find("protected"),tool.." changed a railway layer")
  end
end
assert(not S.rail_span_protected(s,id(4)))
local ok,why=S.landscape(s,"A","raise",7,10)
assert(not ok and why:find("protected"),"Corner change propagated into a reserved span")
assert(not S.road_bridge(s,"A",id(6),id(9),0,true))
local Air=m("airport_network")(S,T,m("openttd/airport_small"))
local field,reason=Air.quote(s,"A",id(6,9))
assert(not field and reason=="AIRPORT_SITE_OCCUPIED")
local Track=m("openttd/rail_track")
local Sea=m("openttd/ship_follow")(Track)
local Ship=m("ship_network")(S,T,Sea,m("openttd/ship_facilities")(Track,Sea))
local Water=m("ship_water_world")(S,Ship,m("openttd/water_construction")(Track,Sea))
assert(not Water.quote(s,"A",b,b,false))
assert(s.tiles[h].rail_span_id==1 and s.rail_bridge_above[b]==1 and s.rail_tunnel_below[u]==2)
print("PASS no road, landscaping, airfield or waterworks quote can overwrite a protected rail span")

-- The actual monthly legacy accounting never retries to price a native
-- paired portal via an undefined legacy tool ID.
s.day=29
S.daily(s)
assert(s.day==30 and #S.company(s,"A").history==1)
print("PASS legacy month close ignores native rail portal tags instead of crashing")
