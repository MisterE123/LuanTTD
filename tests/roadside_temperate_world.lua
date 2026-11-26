local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain=load("sim"),load("openttd/terrain")
local Board,Details=load("openttd/roadside_temperate"),load("openttd/roadside_details")
local Q=load("campaign_terrain_projection")
local W=load("road_reconstruction_world")(Sim,Terrain,{zone=function(t)return t.zone end},
  load("openttd/road_reconstruction"),load("openttd/road_slope"),
  load("openttd/rail_track"),load("openttd/slope"),Board)
local s=Sim.new(11)
local id=Sim.id(8,8)
local town_a={id=1,kind="town",tile=Sim.id(7,8),zone=4}
local town_b={id=2,kind="town",tile=Sim.id(20,8),zone=3}
s.stock_generated_profile={version=1}
s.sites={town_a,town_b}
s.stock_town_growth={towns={town_a,town_b}}
local t={terrain="grass",build="road",owner="Builder",road_bits=5}
s.tiles[id]=t
local revision=s.topology
assert(W.decorate(s,8,8)=="paved")
assert(W.decorate(s,8,8)=="street_lights")
assert(not W.decorate(s,8,8) and s.topology==revision)
assert(t.stock_roadside_town==1 and #s.changed==2 and Q.tile(t).roadside=="street_lights")
t.roadworks="paved";town_a.zone=3
assert(not W.decorate(s,8,8) and t.roadside=="street_lights")
t.roadworks=nil
assert(W.decorate(s,8,8)=="barren" and W.decorate(s,8,8)=="trees")
t.build="road_depot";t.roadside=nil
assert(not W.decorate(s,8,8) and not t.roadside)
-- Source details are based on the road OR tram mask, but two road
-- pieces are required independently of tram cables.
assert(#Details.points("street_lights",5,5,false,3,5)==2)
assert(#Details.points("trees",5,5,false,3,6)==4)
assert(not Details.points("trees",5,5,false,3,5))
assert(not Details.points("trees",5,5,"paved",3,12))
assert(not Details.points("street_lights",4,5,false,3,12))
print("PASS ordinary stock roadside staging, roadwork priority, bridge clearance and worker appearance projection")

-- Each native foundation is a single mesh buffer. A sheet modifier or
-- multiple independent tiles repeats the main image on the sidewall.
local defs={}
local function reg(name,tiles,def) defs[name]={tiles=tiles,def=def};return name end
local V=load("roadside_temperate_view")(s,Sim,Terrain,function() return 3,1 end,reg,function(name)return name end,
  Details,load("openttd/rail_track"),function(n)return "bl_"..n..".png" end,function()return {} end)
for _,class in ipairs({"paved","barren","grass"}) do
  for _,grade in ipairs({3,6,9,12}) do
    local tile={roadside=class}
    local name=class=="grass" and V.tram_ground(tile,grade,"x") or V.grade(tile,grade,"x")
    local d=assert(defs[name])
    assert(#d.tiles==1 and d.def.mesh=="bl_road_grade_foundation_"..grade..".obj")
    local f=assert(io.open(m.."textures/"..d.tiles[1],"rb"))
    assert(f:read(24):sub(17)==string.char(0,0,0,64,0,0,0,32))
    f:close()
  end
end
print("PASS roadside asphalt/paving and tram incline foundations share one correctly formatted 2-cell atlas")

local clock,paint=.5,true
local def,added,removed={},{},0
local light_state={tiles={[3]={roadside="street_lights"},[4]={roadside="street_lights"}}}
local C={
  get_timeofday=function()return clock end,
  get_node_or_nil=function() if paint then return {name="lamp"} end end,
  register_entity=function(name,v)def[name]=v.initial_properties end,
  add_entity=function(p,name)
    assert(def[name] and not def[name].pointable and not def[name].static_save)
    local ref={get_pos=function()return p end,remove=function()p=nil;removed=removed+1 end}
    added[#added+1]={ref=ref,name=name,pos=p}
    return ref
  end,
}
local lights=load("street_light_view")(C,{W=4,H=1,id=function(x)return x end},function(t,i)
  if not t.roadworks then return "lamp",4,i==3 and 0 or 3,{{1,8,0}} end
end)
local close={{x=6,y=5,z=3}}
lights.step(.5,light_state,close);assert(#added==0)
clock=.05
lights.step(.5,light_state,close);assert(#added==3)
assert(added[1].name:match("cone$") and added[2].name:match("pool$") and added[3].name:match("grade$"))
assert(math.abs(added[1].pos.y-5.429)<1e-8 and math.abs(added[2].pos.y-4.516)<1e-8)
lights.step(.5,light_state,close);assert(#added==3 and removed==0)
paint=false; lights.step(.5,light_state,close);assert(removed==3)
paint=true;lights.step(.5,light_state,close);assert(#added==6)
light_state.tiles[3].roadworks=true;lights.step(.5,light_state,close);assert(removed==5)
clock=.5;lights.step(.01,light_state,close);assert(removed==6)
print("PASS night lamp cones and flat-only pools track real painted geometry, reuse entities and clear on work sites or daylight")
