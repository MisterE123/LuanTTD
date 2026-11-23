-- Exact dimensions from RC1 viewport selection plus native platform command.
local path="mods/luanttd_core/"
local function load(f)return dofile(path..f..".lua")end
local Place=load("openttd/rail_station_placement")
assert(Place.default.drag and Place.default.tracks==1 and Place.default.length==5)
local a=Place.bounds(12,14,9,8,Place.default)
assert(a.x==9 and a.z==8 and a.tracks==7 and a.length==4)
local b=Place.bounds(12,14,-8,29,assert(Place.layout(1,true,1,5)))
assert(b.x==1 and b.z==14 and b.w==12 and b.h==12 and b.tracks==12 and b.length==12)
local c=Place.bounds(12,14,0,0,assert(Place.layout(0,false,3,5)))
assert(c.x==12 and c.z==14 and c.w==5 and c.h==3 and c.tracks==3 and c.length==5)
local d=Place.bounds(12,14,0,0,assert(Place.layout(1,false,3,5)))
assert(d.w==3 and d.h==5 and not Place.layout(2,true,1,1) and not Place.layout(0,false,8,1))
local Sim,Track,Slope,Terrain=load("sim"),load("openttd/rail_track"),load("openttd/slope"),load("openttd/terrain")
local F=load("openttd/rail_follow")(Track)
local C=load("openttd/rail_yapf_cost")(Track,F)
local Y=load("openttd/rail_yapf_search")(Track,F,C)
local Sig=load("openttd/rail_signals")(Track)
local Q=load("openttd/rail_construction")(Track,Sig,load("openttd/rail_height")(Track,Slope))
local s=Sim.new(1751)
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
for i=1,#s.tiles do s.tiles[i]={terrain="grass",h=0} end
local function terrain(id)return Terrain.tile(s.corner_grid,Sim.xy(id))end
local Lab=load("trackworks")(Sim,Track,F,Slope,C,Y,terrain)
local called,form,markup
core={get_modpath=function()return "mods/luanttd_core" end,formspec_escape=function(x)return x end,
  show_formspec=function(_,f,m)form,markup=f,m end,close_formspec=function()end}
local api={Sim=Sim,s=s,terrain={tile=terrain},road_first=true,
  render={update=function(ids)called=ids end},save=function()end}
api.rail_build=load("rail_construction_tools")(api,Lab,Track,nil,{
  station_area=function(tiles,axis,tracks,length,o)
    local q,why=Q.station(tiles,axis,tracks,length,o);return q and q.cost,why
  end})
local U=load("ui")(api)
local n="Station QA"
local p={get_player_name=function()return n end}
local cash=Sim.company(s,n)
assert(U.open_station_layout(p) and form=="luanttd_core:station_layout" and markup:find("Drag rectangle",1,true))
assert(U.fields(p,form,{rail_layout_apply=true,rail_axis="2",rail_place="2",rail_count="2",rail_length="3"}))
U.select_tool(p,"rail_platform")
local id=Sim.id(10,15)
local cells,ok,word=U.preview(p,id)
assert(ok and #cells==6 and word:find("2 tracks × 3 tiles",1,true))
assert(not s.stock_rail_stations and cash.cash==100000)
assert(U.begin_station(p,id))
U.end_station(p,Sim.id(20,25)) -- fixed-size placement uses the press tile
local st=s.stock_rail_stations[1]
assert(st and #st.tiles==6 and st.axis==1 and st.area.w==2 and st.area.h==3)
assert(cash.cash<100000 and #called==6)
for _,v in ipairs(st.tiles) do assert(s.tiles[v].rail_tracks==2 and s.tiles[v].rail_station_id==1) end
local bound=Lab.board(s).station_area(1,"station")
assert(bound.tile==id and bound.w==2 and bound.h==3)
U.open_station_layout(p)
assert(U.fields(p,form,{rail_layout_apply=true,rail_axis="1",rail_place="1",rail_count="2",rail_length="3"}))
local start,finish=Sim.id(18,22),Sim.id(15,21)
assert(U.begin_station(p,start));U.end_station(p,finish)
local two=s.stock_rail_stations[2]
assert(two.area.w==4 and two.area.h==2 and two.tiles[1]==finish and two.axis==0)
local prior=cash.cash
assert(U.begin_station(p,start));U.end_station(p,finish)
assert(cash.cash==prior and not s.stock_rail_stations[3])
-- Source FindJoiningBaseStation: diagonal adjacency counts, overlaps
-- take precedence, distinct neighbors conflict unless separate is chosen.
local one=assert(Place.layout(0,false,1,1))
local separate=assert(Place.layout(0,false,1,1,true))
local function quote(x,z,l)
  local tile=Sim.id(x,z)
  return api.rail_build.quote_station(n,tile,tile,l or one)
end
local function build(q) return assert(api.rail_build.build(n,q)) end
local corner=assert(quote(12,18))
assert(corner.join==1 and corner.combined.w==3 and corner.combined.h==4)
build(corner)
assert(s.tiles[Sim.id(12,18)].rail_station_id==1 and #st.tiles==7)
bound=Lab.board(s).station_area(1,"station")
assert(bound.tile==id and bound.w==3 and bound.h==4)
assert(not quote(12,18,separate))
local independent=assert(quote(13,18,separate))
assert(not independent.join)
build(independent)
assert(s.tiles[Sim.id(13,18)].rail_station_id==3 and #st.tiles==7)
local conflict,why=quote(12,19)
assert(not conflict and why:find("more than one",1,true))
assert(assert(quote(12,18)).join==1) -- overlapping station wins over neighbors
local blocked=Sim.id(31,32)
s.tiles[blocked].house=true
local no,_,footprint=api.rail_build.quote_station(n,blocked,Sim.id(32,33),Place.default)
assert(not no and #footprint==4)
print("PASS RC1 station drag, spread, fixed footprint, pricing, real station bounds, adjacency and separate stations")
