-- Verify asset availability and chosen world-wire coordinates against the
-- real Harbor Valley wooden-rail quote, not a fake span/height fixture.
local mod="mods/bayline/"
local function load(p) return dofile(mod..p..".lua") end
local Art=load("rail_bridge_catenary_art")
local Plain=load("rail_catenary_art")
local function check_file(o)
  assert(o and o.offset==1)
  for dir,f in pairs({models=o.mesh,textures=o.texture}) do
    local h=assert(io.open(mod..dir.."/"..f,"rb"));h:close()
  end
  return o
end
local function near(a,b) return math.abs(assert(a)-assert(b))<1e-9 end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Slope,Track=load("openttd/slope"),load("openttd/rail_track")
local H=load("openttd/rail_height")(Track,Slope)
local Q=load("openttd/rail_construction")(Track,load("openttd/rail_signals")(Track),H)
local Site=load("openttd/rail_span_site")
local B=load("openttd/rail_bridge")(load("openttd/road_bridge")(Slope),Q,Site)
local U=load("openttd/rail_tunnel")(load("openttd/road_tunnel"),Q,Site,Track)
local W=load("rail_span_world")(Sim,Terrain,H,B,U,Track)
local s=Sim.new(1751)
load("town_layout")(Sim,s)
local old=load("terrain_preview")(Sim,Terrain,s)
s.corner_grid=load("harbor_valley_seed")(Sim,Terrain,s,old)
s.rail_span_enabled=true
local q=assert(W.quote_bridge(s,"Bridge art QA",Sim.id(21,15),Sim.id(27,15)))
assert(q.bridge_type==0 and q.deck==2 and q.axis==0 and #q.middle==5)
assert(q.head.inside_direction==2 and q.tail.inside_direction==0)
for _,head in ipairs({q.head,q.tail}) do
  assert(not head.flat_ramp and head.base==1)
  local d=head.inside_direction
  local o=check_file(Art.overlay("head_ramp",d))
  assert(o.pole and not o.rigid_contact_qualified)
  assert(near(Art.wire_edge("head_ramp",d,(d+2)%4,q.deck),Plain.wire_edge(1,0,d,head.base)))
  assert(near(Art.wire_edge("head_ramp",d,d,q.deck),Art.wire_edge("span",q.axis,d,q.deck)))
  assert(near(Art.wire_edge("head_ramp",d,d,q.deck),3.398))
  assert(near(Art.wire_edge("head_ramp",d,(d+2)%4,q.deck),2.398))
end
for i,id in ipairs(q.middle) do
  local x,z=Sim.xy(id)
  assert(x==21+i and z==15)
  assert(s.tiles[id].terrain==(i>=2 and i<=4 and "water" or "grass"))
  local o=check_file(Art.overlay("span",q.axis,i,#q.middle))
  assert(o.pole==(i%2==1) and o.rigid_contact_qualified)
end
for d=0,3 do
  assert(check_file(Art.overlay("head_flat",d)).rigid_contact_qualified)
  assert(not check_file(Art.overlay("head_ramp",d)).rigid_contact_qualified)
  assert(not Art.wire_edge("head_ramp",d,(d+1)%4,2))
end
for a=0,1 do
  for i=1,4 do
    local o=check_file(Art.overlay("span",a,i,4))
    assert(o.pole==(i~=2) and o.rigid_contact_qualified)
  end
end
assert(not Art.overlay("tunnel",0) and not Art.overlay("span",2,1,2))
assert(not Art.overlay("span",1,0,2) and not Art.overlay("span",1,2,1))
assert(not Art.overlay("head_flat",4) and not Art.wire_edge("span",0,1,2))
print("WOOD_BRIDGE_CATENARY_SELECTOR_PASS: actual (21,15)–(27,15) has two low wire edges 2.398 rising to deck wire 3.398; rigid contact flat only")
