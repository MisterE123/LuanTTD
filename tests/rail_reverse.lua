local root="mods/luanttd_core/openttd/"
local function port(name,...)return dofile(root..name..".lua")(...)end
local T=dofile(root.."rail_track.lua")
local F=port("rail_follow",T)
local Costs=port("rail_yapf_cost",T,F)
local Search=port("rail_yapf_search",T,F,Costs)
local P=port("rail_reservation",T,F,Costs)
local Life=port("rail_consist_reservation",T,F,P)
local Raw=port("rail_motion",T)
local K=port("rail_consist_motion",T,Raw,F,Life)
local Signal=port("rail_signals",T)
local R=port("rail_reverse",T,Raw,K,Life,Signal,F,P)
local function id(x,y)return x+32*y end
local function tile(x)return id(x,5) end
local tiles={}
for x=2,22 do tiles[tile(x)]={kind="rail",trackbits=1,owner=1,railtype=0} end
for _,site in ipairs({{2,3},{10,12},{19,22}}) do
  for x=site[1],site[2] do
    local t=tiles[tile(x)]
    t.kind="station";t.station=site[1];t.axis=0
  end
end
local stations={[2]={tile=tile(2),w=2,h=1},[10]={tile=tile(10),w=3,h=1},[19]={tile=tile(19),w=4,h=1}}
local off={[0]=-1,32,1,-32}
local board={tile=function(i)return tiles[i] end,adjacent=function(i,d)return i+off[d] end,
  xy=function(i)return i%32,math.floor(i/32) end,tile_at=id,
  station_area=function(n)local a=stations[n];return a,a and a.tile end}
local function part(x,l,vehicle)
  local tx=math.floor(x/16)
  return {length=l,vehicle_id=vehicle,tile=tile(tx),pose={x=x,y=88,tx=tx,ty=5,td=8,direction=5}}
end
local function fresh()
  local train=assert(K.place(board,1,{part(11*16+3,8),part(10*16+11,8),part(10*16+3,8)}))
  for i,p in ipairs(train.parts) do p.vehicle_id=i<2 and "engine" or i end
  local state,signals=Life.new(),Signal.new()
  assert(Life.register(board,state,17,1,{{tile=tile(11),td=8},{tile=tile(10),td=8},{tile=tile(10),td=8}}))
  assert(Life.register(board,state,23,1,{{tile=tile(18),td=8}}))
  local function acquire(x)
    assert(P.try_reserve(board,state.bits,tile(x),T.X));state.claims[tile(x)]={[T.X]=17}
  end
  for x=12,17 do acquire(x) end
  assert(Signal.place(board,signals,1,tile(13),T.X,{kind=Signal.PBS,copy_mask=T.signal_along(8)},1,false))
  assert(Signal.place(board,signals,1,tile(16),T.X,{kind=Signal.PBS,copy_mask=T.signal_along(8)},0,false))
  return train,state,signals
end
local train,state,signals=fresh()
local function unchanged()
  assert(train.serial==0 and train.parts[1].tile==tile(11) and train.parts[1].pose.td==8)
  assert(state.bits[tile(14)]==1 and Signal.aspect(Signal.view(board,signals).tile(tile(13)),8)=="green")
end
assert(not R.apply(board,train,state,17,signals,{speed=1}));unchanged()
assert(not R.apply(board,train,state,23,signals,{speed=0}));unchanged()
local plan=assert(R.apply(board,train,state,17,signals,{speed=0}))
assert(plan.origin.tile==tile(10) and plan.origin.td==0 and plan.first_tile_okay)
assert(plan.spacing_ok and train.reversed and train.parts[1].vehicle_id=="engine" and train.parts[3].vehicle_id==3)
assert(train.parts[1].pose.x==10*16+3 and train.parts[3].pose.x==11*16+3)
for _,p in ipairs(train.parts) do assert(p.pose.direction==1 and p.pose.td==0) end
assert(#plan.released==3 and #plan.signals_red==1)
for x=10,18 do
  local expected=x<13 and 17 or x>=16 and (x==18 and 23 or 17) or nil
  assert(Life.claim_owner(state,tile(x),T.X)==expected,"Wrong claim at x="..x)
end
assert(Signal.aspect(Signal.view(board,signals).tile(tile(13)),8)=="red")
assert(Life.valid_state(Signal.view(board,signals),state))
assert(not R.commit(train,plan))
local yes=R.check_order(board,train,{kind="station",station=19},Costs,Search)
assert(yes,"new order east from westbound train should select reversed rear origin")
assert(not R.check_order(board,train,{kind="station",station=2},Costs,Search))
assert(not R.check_order(board,train,{kind="station",station=19},Costs,Search,{line_reverse_mode=1}))
local redo=assert(R.apply(board,train,state,17,signals,{speed=0,stuck=true}))
assert(not train.reversed and #redo.released==0 and Life.valid_state(board,state))
assert(train.parts[1].tile==tile(11) and train.parts[1].pose.td==8)
-- Stock wholly inside depot is a no-op, not an engine/wagon queue edit.
tiles[tile(5)]={kind="depot",trackbits=1,owner=1,railtype=0,dir=T.SW}
local hidden=assert(K.seed_depot(board,tile(5),{8,8}))
assert(assert(R.plan(board,hidden)).noop)
assert(K.release_front(hidden))
assert(not R.plan(board,hidden))
print("PASS: stopped reversal, immutable locomotive identity, two-origin order choice, forward PBS cleanup, and preserved platform/other-train claims")
