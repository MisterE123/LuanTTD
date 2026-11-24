local root="mods/luanttd_core/"
local function m(name) return dofile(root..name..".lua") end
local function u(name) return m("openttd/"..name) end
local Sim,Terrain,Track,Slope=m("sim"),u("terrain"),u("rail_track"),u("slope")
local World=m("level_crossing_world")(Sim,Terrain,u("level_crossing")(Track),Track)
local Runtime=m("level_crossing_runtime")(Sim,World)
local F=u("yapf_road_follow")
local C=u("yapf_road_cost")(F)
local Net=m("tram_network")(Sim,u("tram_construction")(u("road_slope"),u("road_bridge")(Slope).roadtypes),Terrain)
local Motion=u("tram_motion")(u("tram_motion_data"),u("road_motion")(u("road_motion_data")))
local Run=m("tram_preview_run")(Net,m("tram_trip")(F,C,u("yapf_road_search")(F,C),Motion),u("road_speed"))
local s=Sim.new(1751)
s.tiles,s.sites,s.stations,s.fleet={},{},{},{}
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 1 end)
for i=1,Sim.W*Sim.H do s.tiles[i]={terrain="grass",h=1,variant=1} end
s.road_stock_clock,s.road_economy,s.level_crossing_enabled=true,true,true
local owner="ELRL operator"
local c=Sim.company(s,owner)
local function at(x,z) return assert(Sim.id(x,z)) end
local crossing=at(12,12)
local base={tile=function(id)
  local t=s.tiles[id]
  if t and t.rail_tracks then return {kind="rail",owner=t.owner,trackbits=t.rail_tracks,railtype=0} end
end}
Sim.mount_crossings(s,Runtime,function()return base end)
s.tiles[crossing].build,s.tiles[crossing].rail_tracks,s.tiles[crossing].owner="stock_rail",2,owner
local function build(kind,tiles,axis) return assert(Net.construct(s,owner,kind,tiles,axis)) end
local depot,start,finish=at(9,14),at(10,12),at(14,12)
build("depot",{depot},F.NW)
build("road",Sim.line(at(8,12),at(16,12)))
build("road",Sim.line(at(9,12),at(9,13)))
build("road",{at(9,13)},4)
build("drive_stop",{start},F.NE)
build("drive_stop",{finish},F.NE)
local level=assert(s.tiles[crossing].level_crossing)
assert(level.tramtype==1 and level.tram_bits==10 and level.rail_axis==1 and not level.roadtype)
assert(not s.tiles[crossing].tram and Net.board(s).tile(crossing).kind=="crossing")
local run=assert(Run.start(s,owner,depot,start,finish))
s.stock_rail_dispatch={life={bits={[crossing]=2}},runs={}}
Runtime.refresh(s,base)
local wait
for _=1,6000 do
  Run.advance(s,1)
  if run.crossing_wait then wait=Run.frame(run);break end
end
assert(wait and wait[4]==at(11,12) and run.crossing_wait=="CROSSING_BARRED")
local cursor=run.index
Run.advance(s,137)
assert(run.index==cursor and Run.frame(run)[4]==at(11,12))
s.stock_rail_dispatch.life.bits[crossing]=nil
Runtime.refresh(s,base)
local on
for _=1,1200 do
  Run.advance(s,1)
  if Run.frame(run) and Run.frame(run)[4]==crossing then on=true;break end
end
assert(on and not run.crossing_wait)
local seen=Runtime.context(s,base).vehicles_at(crossing)
assert(#seen==1 and seen[1].type=="road" and seen[1].id==-1)
assert(not Runtime.quote(s,owner,crossing,{kind="road",pieces=10},base))
local entered=false
local permitted=Runtime.train_move(s,base,{{old_tile=at(12,11),tile=crossing,td=1}},owner,function()entered=true;return true end)
assert(not permitted and not entered,"Protected railway cannot move through the tram's committed pose")
assert(Run.clear(s,owner))
Runtime.refresh(s,base)
local cash=c.cash
assert(Sim.autoroad_build(s,owner,crossing,crossing,0,false,true))
assert(c.cash==cash-190)
level=s.tiles[crossing].level_crossing
assert(level.roadtype==0 and level.road_owner==owner and level.tramtype==1 and level.tram_owner==owner)
print("PASS live tram waits at the reserved rail crossing, continues after release, occupies the railway guard and permits separately priced shared pavement after it clears")

s.stock_rail_dispatch.life.bits[crossing]=2
local choose=m("demolition_layer_choices")({s=s,Sim=Sim,tram={network=Net,busy=function()return false end}},
  function()return false end)
local options={}
for _,o in ipairs(choose(owner,crossing)) do options[o.key]=o end
assert(options.crossing_road and options.crossing_road.ok and options.crossing_road.detail=="Cost: $80")
assert(options.crossing_tram and options.crossing_tram.ok and options.crossing_tram.detail=="Refund: $204")
local remove=assert(Sim.road_remove_plan(s,owner,crossing,crossing,0,false,true))
assert(remove.cost==80 and Sim.apply_road_removal(s,owner,remove))
assert(s.tiles[crossing].level_crossing.tramtype==1 and s.tiles[crossing].level_crossing.roadtype==nil)
assert(s.stock_rail_dispatch.life.bits[crossing]==2)
local q=assert(Net.remove_plan(s,owner,{first=crossing,last=crossing,axis=0,start_half=false,end_half=true},
  function()return false end))
assert(q.cost==-204 and Net.apply_remove(s,owner,q))
assert(s.tiles[crossing].build=="stock_rail" and s.tiles[crossing].rail_tracks==2)
assert(not s.tiles[crossing].level_crossing and s.stock_rail_dispatch.life.bits[crossing]==2)
print("PASS selectively removing pavement and tramway preserves the straight railway and its live reservation")

local perpendicular=at(32,18)
build("road",{perpendicular},5)
assert(s.tiles[perpendicular].tram.tram_bits==5 and not s.tiles[perpendicular].build)
local reverse=assert(Runtime.quote(s,owner,perpendicular,{kind="rail",track=0},base))
assert(reverse.price==100)
assert(Runtime.commit(s,owner,reverse,base))
local both=s.tiles[perpendicular].level_crossing
assert(both.rail_axis==0 and both.tram_bits==5 and both.tram_owner==owner and not both.roadtype)
assert(Net.surface(s,perpendicular).base==both.top)
print("PASS rail over an already laid north–south tram creates the same canonical paired crossing with no duplicate surface")

local another="Independent road owner"
local account=Sim.company(s,another)
assert(Sim.autoroad_build(s,another,perpendicular,perpendicular,1,false,true))
local record=s.tiles[perpendicular].level_crossing
assert(record.rail_owner==owner and record.tram_owner==owner and record.road_owner==another)
assert(not Sim.crossing_rail_remove_plan(s,another,perpendicular))
s.stock_rail_dispatch.life.bits[perpendicular]=1
local blocked,why=Sim.crossing_rail_remove_plan(s,owner,perpendicular)
assert(not blocked and why=="WAIT_RAIL_RESERVATION")
s.stock_rail_dispatch.life.bits[perpendicular]=nil
local proposal=assert(Sim.crossing_rail_remove_plan(s,owner,perpendicular))
local previous=c.cash
assert(proposal.cost==-70 and Sim.apply_crossing_rail_removal(s,owner,proposal))
local surface=s.tiles[perpendicular]
assert(c.cash==previous+70 and surface.tram.kind=="road" and surface.tram.tram_owner==owner)
assert(surface.road_bits==5 and surface.owner==another and surface.build=="road")
assert(not surface.level_crossing and not surface.rail_tracks and not s.level_crossing_tiles[perpendicular])
print("PASS Bulldozer railway removal keeps independent standard road and tram layers and refuses a live reservation")
