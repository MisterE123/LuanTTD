-- SPDX-License-Identifier: GPL-2.0-only
-- Production construction entry points used by Road, straight rail and AutoRail.
local base="mods/luanttd_core/"
local function m(f)return dofile(base..f..".lua")end
local function up(f,...)return m("openttd/"..f)(...)end
local Sim,Terrain,Track,Slope=m("sim"),m("openttd/terrain"),m("openttd/rail_track"),m("openttd/slope")
local F=up("rail_follow",Track)
local C=up("rail_yapf_cost",Track,F)
local Y=up("rail_yapf_search",Track,F,C)
local Signals=up("rail_signals",Track)
local Q=up("rail_construction",Track,Signals,up("rail_height",Track,Slope))
local Rule=up("level_crossing",Track)
local World=m("level_crossing_world")(Sim,Terrain,Rule,Track)
local Run=m("level_crossing_runtime")(Sim,World)
local s=Sim.new(1751);local at=Sim.id
s.road_stock_clock,s.road_economy,s.level_crossing_enabled=true,true,true
s.corner_grid=Terrain.new(Sim.W,Sim.H,function()return 0 end)
for i in pairs(s.tiles) do s.tiles[i]={terrain="grass",h=0} end
s.sites,s.stations,s.fleet={},{},{}
local owner="Builder"
local money=Sim.company(s,owner)
local clear=true
local function shape(id)return Terrain.tile(s.corner_grid,Sim.xy(id))end
local Lab=m("trackworks")(Sim,Track,F,Slope,C,Y,shape)
Sim.mount_crossings(s,Run,function(w)return Lab.board(w)end,function()return clear end)
local updates,saves={},0
local B=m("rail_construction_tools")({Sim=Sim,s=s,terrain={tile=shape},
 render={update=function(ids)updates=ids end},save=function()saves=saves+1 end},Lab,Track,nil,
 {track=function(t,p,o)local q,e=Q.piece(t,p.track,o);return q and q.cost,e end})
local function road(a,b)return Sim.build(s,owner,"road",Sim.line(a,b))end
local function rail(x,z,t)
  local id=at(x,z)
  assert(Lab.change(s,owner,id,t,false,shape(id)))
  return id
end
local function charged(fn,cost)
  local c,e=money.cash,money.expense
  local okay,msg,ids=fn()
  assert(okay,msg)
  assert(c-money.cash==cost and money.expense-e==cost and money.month_exp==money.expense)
  return ids
end

-- Reported screenshot: eastmost road has only its far-side half. Crossing
-- is valid/full already; including it must only buy the missing approach.
local approach,crossing=at(8,8),rail(9,8,Track.Y)
assert(road(at(6,8),approach))
assert(Sim.road_bits(s,approach)==8)
local explicit=assert(Run.quote(s,owner,crossing,{kind="road",pieces=10},Lab.board(s)))
assert(explicit.price==190)
charged(function()return Run.commit(s,owner,explicit,Lab.board(s))end,190)
local original=s.tiles[crossing].level_crossing
local phase,revisions=s.topology,s.level_crossing_tiles
local before=money.cash
local plan,quote=Sim.plan(s,owner,"road",{approach,crossing})
assert(plan and #plan==1 and plan[1].id==approach and quote==63,quote)
assert(not Sim.road_connected(s,approach,2))
assert(s.tiles[crossing].level_crossing==original and s.topology==phase and money.cash==before)
local ids=charged(function()return road(approach,crossing)end,63)
assert(#ids==1 and ids[1]==approach and Sim.road_connected(s,approach,2))
assert(Sim.road_bits(s,approach)==10 and Sim.road_bits(s,crossing)==10)
assert(s.tiles[crossing].level_crossing==original and s.level_crossing_tiles==revisions)
ids=charged(function()return road(at(7,8),at(11,8))end,188)
assert(#ids==2 and ids[1]==at(10,8) and ids[2]==at(11,8))
assert(s.tiles[crossing].level_crossing==original and Sim.road_connected(s,crossing,2))
charged(function()return road(at(7,8),at(11,8))end,0)
local no,why=road(crossing,at(9,7))
assert(not no and why:match("right angles") and s.tiles[crossing].level_crossing==original)
s.level_crossing_enabled=false
charged(function()return road(approach,crossing)end,0)
s.level_crossing_enabled=true

-- Road first or rail first: one normal drag, one combined debit, no
-- crossing toolbar. Source costs are independently pinned to exact 14.1.
local cross2=rail(11,13,Track.X)
local r_ids=Sim.line(at(11,12),at(11,14))
plan,quote=Sim.plan(s,owner,"road",r_ids)
assert(plan and #plan==3 and quote==316 and plan[2].crossing_quote.price==190)
charged(function()return Sim.build(s,owner,"road",r_ids)end,316)
local c=s.tiles[cross2].level_crossing
assert(c.road_axis==1 and c.rail_axis==0 and c.phase=="open")
assert(Sim.road_connected(s,cross2,1) and Sim.road_connected(s,cross2,3))
local road3=at(16,15)
assert(road(at(15,15),at(17,15)))
local qt=assert(B.quote_track(owner,at(16,14),at(16,16),Track.Y,false))
assert(qt.crossing and #qt.ids==3 and qt.price==340)
charged(function()return B.build(owner,qt)end,340)
c=s.tiles[road3].level_crossing
assert(c.road_axis==0 and c.rail_axis==1 and c.phase=="open")
assert(#updates==3 and saves==1 and not s.tiles[road3].rail_tracks)
qt=assert(B.quote_track(owner,at(16,16),at(16,13),Track.Y,false))
assert(not qt.crossing and #qt.ids==1 and qt.ids[1]==at(16,13))
charged(function()return B.build(owner,qt)end,120)
assert(s.tiles[road3].level_crossing==c)

-- The far half of a public-facing road costs a real extra road half when
-- stock rail crosses at its dead end. The crossing piece itself costs $100.
local half=at(21,18)
assert(road(at(20,18),half) and Sim.road_bits(s,half)==8)
local mid={x=21*16+8,z=18*16+8}
local into={x=21*16+8,z=19*16+8}
qt=assert(B.quote_autotrack(owner,mid,into))
assert(#qt.ids==2 and qt.crossing and qt.price==315)
charged(function()return B.build(owner,qt)end,315)
assert(s.tiles[half].level_crossing.road_pieces_added==1 and Sim.road_bits(s,half)==10)

-- A failure on a L-bend, an earlier/later ordinary tile, or a newly
-- unverified physical road cannot leave a partially laid mixed drag.
local rd=at(11,19)
rail(11,19,Track.X)
local bend={at(11,18),rd,at(12,19)}
before=money.cash
no,why=Sim.build(s,owner,"road",bend)
assert(not no and why:match("right angles") and money.cash==before and not s.tiles[bend[1]].build)
local target=at(18,23)
assert(road(at(17,23),at(19,23)))
local wrong,msg=B.quote_track(owner,at(16,23),at(18,23),Track.X,false)
assert(not wrong and msg:match("right angles"))
qt=assert(B.quote_track(owner,at(18,22),at(18,24),Track.Y,false))
s.fleet[1]={id=1,engine="bus",route={target}}
before=money.cash
no,why=B.build(owner,qt)
assert(not no and why:match("position") and money.cash==before and not s.tiles[at(18,22)].build)
s.fleet[1]=nil

local sign=rail(23,23,Track.Y)
s.stock_rail_dispatch={runs={},signals={records={[sign]={present_signals=4}}},life={bits={},claims={}}}
no,why=road(at(22,23),at(24,23))
assert(not no and why:match("signal") and s.tiles[sign].rail_tracks==2 and not s.tiles[sign].level_crossing)
s.stock_rail_dispatch=nil
s.tiles[sign].rail_type=1
no,why=road(at(22,23),at(24,23))
assert(not no and why:match("Electrified"))
s.tiles[sign].rail_type=nil
clear=false
no,why=road(at(22,23),at(24,23))
assert(not no and why:match("surveyed"))
clear=true
local rail_board=Run.rail_board(s,Lab.board(s))
assert(rail_board.tile(road3).kind=="crossing" and rail_board.tile(road3).trackbits==2)
print("PASS ordinary rail and road construction: priced crossings both ways, missing approach half, drags and refusals")

-- AutoRoad uses the real stock human command. Stop one tile short: the
-- existing crossing supplies the reciprocal endpoint bit, not a tile edit.
local r,near=rail(27,24,Track.Y),at(26,24)
assert(Run.commit(s,owner,assert(Run.quote(s,owner,r,{kind="road",pieces=10},Lab.board(s))),Lab.board(s)))
local old_record=s.tiles[r].level_crossing
local first=at(23,24)
local topology=s.topology
local cash=money.cash
local q=assert(Sim.autoroad_plan(s,owner,first,near,0,false,false))
assert(#q.ids==4 and q.ids[4]==near and q.changes[4].road_bits==10)
assert(s.topology==topology and money.cash==cash and Sim.road_bits(s,near)==0)
charged(function()return Sim.autoroad_build(s,owner,first,near,0,false,false)end,q.cost)
assert(Sim.road_connected(s,near,2) and s.tiles[r].level_crossing==old_record)
assert(not Sim.autoroad_plan(s,owner,first,at(26,23),0,false,false))

-- Empty or wrong-axis neighbor cannot supply the extra half.
local z=25
local a,b=at(24,z),at(26,z)
assert(road(at(27,z),at(27,z+1)))
local endpoint=assert(Sim.autoroad_plan(s,owner,a,b,0,true,false))
assert(endpoint.changes[3].road_bits==8)
assert(Sim.autoroad_build(s,owner,a,b,0,true,false))
assert(not Sim.road_connected(s,b,2))

-- The original press direction, not tile numeric order, decides the
-- committed prefix. An obstacle before any success is skipped. Existing
-- bits don't count as a success or break the command after one.
for _,zrow in ipairs({29,30}) do
  for _,x in ipairs({30,34}) do s.tiles[at(x,zrow)].house=true end
  s.tiles[at(32,zrow)].build,s.tiles[at(32,zrow)].road_bits,s.tiles[at(32,zrow)].owner="road",10,owner
end
for _,k in ipairs({{29,30,36,31,33},{30,36,30,36,35}}) do
  local row,from,to,a1,a2=unpack(k)
  local a,b=at(from,row),at(to,row)
  local q=assert(Sim.autoroad_plan(s,owner,a,b,0,false,false))
  assert(#q.ids==2 and q.ids[1]==at(a1,row) and q.ids[2]==at(a2,row))
  assert(q.stopped_at==at(34,row))
  local saved=money.cash
  money.cash=q.cost-1
  assert(not Sim.autoroad_build(s,owner,a,b,0,false,false))
  assert(money.cash==q.cost-1)
  money.cash=saved
  charged(function()return Sim.autoroad_build(s,owner,a,b,0,false,false)end,q.cost)
end

local point=function(x,z,fx,fz) return {x=x*2-.5+fx/8,z=z*2-.5+fz/8} end
-- OpenTTD 16.0-RC1 #16101: coordinates on either side of the 15/16
-- diagonal must not introduce a one-sided X hotspot. Test the native
-- 3D-to-tile fractional projection for every stock click pixel.
local stock_click=at(40,31)
for x=0,15 do for z=0,15 do
  local hit=point(40,31,x,z)
  local target,axis,first,last=Sim.autoroad_selection(stock_click,hit,stock_click,hit)
  local rc1_x=(x<z and z<=15-x) or (x>z and z>=15-x)
  assert(target==stock_click and axis==(rc1_x and 0 or 1))
  assert(first==last and last==((rc1_x and x or z)>=8))
end end
local id,axis,h0,h1=Sim.autoroad_selection(at(40,31),point(40,31,2,9),at(44,32),point(44,32,12,1))
assert(id==at(44,31) and axis==0 and not h0 and h1)
id,axis,h0,h1=Sim.autoroad_selection(at(40,31),point(40,31,7,12),at(41,32),point(41,32,8,8))
assert(id==at(40,32) and axis==1 and h0 and h1)
id,axis,h0,h1=Sim.autoroad_selection(at(40,31),point(40,31,2,7),at(40,31),point(40,31,2,7))
assert(id==at(40,31) and axis==0 and not h0 and not h1)
q=assert(Sim.autoroad_plan(s,owner,id,id,axis,h0,h1))
assert(q.changes[1].road_bits==8 and q.cost==63)
print("PASS AutoRoad axis/halves, reciprocal outside crossing, obstacle sweep order and cash quote")

-- OpenTTD 14.1 CmdRailTrackHelper: skip starting obstructions until a
-- real addition, pass existing track without counting it as success,
-- and stop at the next obstruction. Manual track stays all-or-nothing.
local function rp(x,z)return {x=x*16+8,z=z*16+8}end
for _,x in ipairs({5,10}) do s.tiles[at(x,31)].house=true end
rail(4,31,Track.X)
rail(7,31,Track.X)
local strict,why=B.quote_track(owner,at(4,31),at(11,31),Track.X,false)
assert(not strict and why)
local drag=assert(B.quote_autotrack(owner,rp(4,31),rp(11,31)))
assert(drag.skipped_start==1 and drag.stopped_at==at(10,31) and drag.price==360)
assert(#drag.ids==3 and drag.ids[1]==at(6,31) and drag.ids[2]==at(8,31) and drag.ids[3]==at(9,31))
local balance=money.cash
money.cash=359
assert(not B.quote_autotrack(owner,rp(4,31),rp(11,31)) and money.cash==359)
money.cash=balance
charged(function()return B.build(owner,drag)end,360)
assert(not s.tiles[at(11,31)].rail_tracks and s.tiles[at(6,31)].rail_tracks==1)
local flip=assert(B.quote_autotrack(owner,rp(11,31),rp(4,31)))
assert(flip.skipped_start==0 and flip.stopped_at==at(10,31) and flip.ids[1]==at(11,31) and flip.price==120)
charged(function()return B.build(owner,flip)end,120)
assert(not B.quote_autotrack(owner,rp(5,31),rp(5,31)))
print("PASS AutoRail stock obstruction order, existing pieces, partial quotes and atomic finance")

-- Optional bend is a single connected, all-or-nothing construction quote.
local from,to=at(3,32),at(8,35)
local elbow=at(8,32)
local plan,why,path=Sim.autoroad_bend_plan(s,owner,from,to)
assert(plan,why)
assert(#path==9 and path[1]==from and path[6]==elbow and path[9]==to)
assert(plan.cost==1001) -- 7 full tiles and 2 priced half ends
assert(not s.tiles[elbow].build)
s.tiles[elbow].house=true
local cash=money.cash
assert(not Sim.autoroad_bend_build(s,owner,from,to))
assert(money.cash==cash and not s.tiles[from].build and not s.tiles[to].build)
s.tiles[elbow].house=nil
local changed=charged(function()return Sim.autoroad_bend_build(s,owner,from,to)end,plan.cost)
assert(#changed==9 and Sim.road_bits(s,elbow)==12)
for i=2,#path do
  local d
  for j=1,4 do if Sim.adjacent(path[i-1],j)==path[i] then d=j end end
  assert(d and Sim.road_connected(s,path[i-1],d))
end
local reverse=assert(Sim.autoroad_bend_plan(s,owner,to,from))
assert(reverse.path[6]==at(3,35) and reverse.path[6]~=elbow)
assert(not Sim.autoroad_bend_plan(s,owner,from,at(8,32)))
print("PASS AutoRoad connected bend, opposite drag, half endpoints, and no partial purchase if blocked")

-- Generated dry forest is part of the normal AutoRail quote, not a
-- protected structure. Price counts stems and never mutates during hover.
local forest=at(25,22)
local protected=at(27,22)
s.tiles[forest].wood={count=3,type=2,growth=3}
s.tiles[protected].stock_landmark={kind="transmitter"}
local x,z=Sim.xy(at(24,22))
local u,v=Sim.xy(at(29,22))
local start={x=16*x+8,z=16*z+8};local finish={x=16*u+8,z=16*v+8}
local draft=assert(B.quote_autotrack(owner,start,finish))
assert(draft.tree_count==3 and #draft.ids==3 and draft.stopped_at==protected)
assert(draft.price==120*2+100+60 and s.tiles[forest].wood.count==3)
local old_cash=money.cash
s.tiles[forest].wood.count=4
assert(not B.build(owner,draft) and money.cash==old_cash and s.tiles[forest].wood.count==4)
draft=assert(B.quote_autotrack(owner,start,finish))
assert(draft.tree_count==4 and draft.price==420)
assert(B.build(owner,draft))
assert(not s.tiles[forest].wood and s.tiles[forest].rail_tracks==1 and old_cash-money.cash==420)
assert(s.tiles[protected].stock_landmark and not s.tiles[protected].rail_tracks and not s.tiles[at(28,22)].rail_tracks)
print("PASS ordinary AutoRail removes dry woods with priced stems, rejects stale quotes and stops at protected landmarks")

-- The real normal UI goes through a modal before removing a facility.
local markup,form
core={get_modpath=function()return "mods/luanttd_core" end,
  formspec_escape=function(x)return x end,
  show_formspec=function(_,name,data)form,markup=name,data end,
  close_formspec=function(_,name)assert(name==form)end}
local function player(n) return {get_player_name=function()return n end} end
local U=m("ui")({Sim=Sim,s=s,road_first=true,rail_build=B,trackworks=Lab,
 render={update=function(ids) updates=ids end},save=function() saves=saves+1 end})
local p=player(owner)
local modal="luanttd_core:demolish_layers"
local function choice(label)
  assert(markup:find(label,1,true),label)
  return assert(markup:match("(bulldoze_%d+_%d+);"..label),label)
end
local function click(tile)
  U.select_tool(p,"clear")
  assert(U.begin_demolition(p,tile))
  U.end_demolition(p,tile)
  assert(form==modal)
end
for x=30,35 do rail(x,20,Track.X) end
local a,b=at(31,20),at(32,20)
assert(Lab.station(s,owner,a,b))
local sid=s.tiles[a].rail_station_id
local cash=money.cash
local saved=saves
click(a)
local cancel=choice("Remove entire station platform, keep rails")
assert(s.tiles[a].rail_station_id==sid and s.tiles[b].rail_station_id==sid and money.cash==cash and saved==saves)
assert(U.fields(p,modal,{cancel_layers=true}))
assert(U.fields(p,modal,{[cancel]=true}))
assert(s.tiles[a].rail_station_id==sid and saved==saves)
click(a)
local stale=choice("Remove entire station platform, keep rails")
s.topology=s.topology+1
assert(U.fields(p,modal,{[stale]=true}) and s.tiles[a].rail_station_id==sid and saved==saves)
click(a)
local accepted=choice("Remove entire station platform, keep rails")
assert(U.fields(p,modal,{[accepted]=true}))
assert(not s.stock_rail_stations[sid] and not s.tiles[a].rail_station_id and not s.tiles[b].rail_station_id)
assert(s.tiles[a].rail_tracks==1 and s.tiles[b].rail_tracks==1 and #updates==2 and saved+1==saves)
assert(U.fields(p,modal,{[accepted]=true}) and saved+1==saves)
local depot=at(30,20)
assert(Lab.depot(s,owner,depot,Track.SW))
Lab.owned_depot_occupied=function()return true end
click(depot)
assert(markup:find("unavailable") and markup:find("purchased train"))
assert(s.tiles[depot].rail_depot_dir==Track.SW)
Lab.owned_depot_occupied=nil
click(depot)
assert(U.fields(p,modal,{[choice("Remove railway depot, keep rails")]=true}))
assert(s.tiles[depot].rail_depot_dir==nil and s.tiles[depot].rail_tracks==1)
local stop=at(32,24)
s.sites[1]={id=1,kind="town",name="Modalton",tile=at(30,25),stock={},received={},produced={}}
assert(road(at(30,24),at(34,24)))
assert(Sim.build(s,owner,"road_station",{stop}))
assert(s.tiles[stop].stop_axis and s.tiles[stop].station)
local id=s.tiles[stop].station
local q=assert(Sim.clear_area(s,owner,at(31,24),at(33,24),false,false))
for _,tile in ipairs(q.ids) do assert(tile~=stop,"Area sweep must not remove a transport facility") end
click(stop)
assert(choice("Remove stop and its road"))
assert(U.fields(p,modal,{[choice("Remove stop, keep road")]=true}))
assert(not s.stations[id] and not s.tiles[stop].station and s.tiles[stop].build=="road")
assert(Sim.road_bits(s,stop)==10 and s.tiles[stop].owner==owner)
print("PASS real single-tile Bulldozer modal: cancel, stale/duplicate, station/depot rail retention, separate road-stop layers")

-- RC1 rail_gui.cpp depot callback adds the stock candidate pieces to the
-- next tile only, paying their ordinary price after the depot purchase.
local D=m("rail_construction_tools")({Sim=Sim,s=s,terrain={tile=shape},
 render={update=function()end},save=function()end},Lab,Track,nil,{
  track=function(t,p,o)local r,w=Q.piece(t,p.track,o);return r and r.cost,w end,
  depot=function(t,d,o)local r,w=Q.depot(t,d,o);return r and r.cost,w end})
local stopped=at(40,20)
local adjacent=rail(41,20,Track.Y)
local receipt=assert(D.quote_depot(owner,stopped,Track.SW))
local before=money.cash
assert(D.build(owner,receipt))
assert(s.tiles[stopped].rail_depot_dir==Track.SW and s.tiles[adjacent].rail_tracks==2+4+32,
  s.tiles[adjacent].rail_tracks)
assert(before-money.cash==receipt.price+200 and not s.tiles[at(42,20)].rail_tracks)
print("PASS OpenTTD depot auto-attachment adds and charges only valid existing-mouth connections")
