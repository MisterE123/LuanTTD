local root="mods/bayline/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local C=dofile(root.."rail_yapf_cost.lua")(T,F)
local Y=dofile(root.."rail_yapf_search.lua")(T,F,C)
local R=dofile(root.."rail_reservation.lua")(T,F,C)
local X,Y_AXIS=0,1
local function straight(k,fields)
  local t={kind=k or "rail",trackbits=1,owner=1,railtype=0}
  for a,b in pairs(fields or {}) do t[a]=b end
  return t
end
local function station()
  return straight("station",{station=1,axis=0})
end
local function corridor(with_pbs)
  local row={[5]=straight("depot",{dir=T.SW}),[6]=straight(),[7]=straight("rail",{trackbits=3}),
    [8]=straight(),[9]=straight(),[10]=station(),[11]=station()}
  if with_pbs then row[9]=straight("signals",{present_signals=4,green_signals=0,upper_signal_type=4}) end
  local board={tile=function(i)return row[i] end,
    adjacent=function(i,d) if d==T.NE then return i-1 elseif d==T.SW then return i+1 end end,
    xy=function(i)return i,12 end,tile_at=function(x,y)if y==12 then return x end end,
    station_area=function()return {tile=10,w=2,h=1},10 end,
    railtype=function()return {compatible={[0]=true}} end}
  local train={tile=5,owner=1,railtype=0,compatible={[0]=true},length=8,max_speed=80}
  local dest=C.destination(board,train,{kind="station",station=1})
  local found,best=Y.find(board,train,{tile=5,td=8},dest)
  assert(found and best.last_tile==11)
  return board,train,best,row
end
local board,train,best,row=corridor(false)
local state={[5]=1,[7]=2}
local target=R.choose_target(board,state,train,best)
assert(target and target.tile==11 and target.td==8 and target.origin==5)
local ok,why,tile=R.try_path(board,state,train,target)
assert(not ok and why=="overlap" and tile==7)
assert(state[5]==1 and state[7]==2 and not state[6] and not state[8] and not state[10] and not state[11],
  "collision transaction left a platform prefix or cleared an existing reservation")
assert(R.unreserve(board,state,7,Y_AXIS))
local won,claimed=R.try_path(board,state,train,target)
assert(won and #claimed==6)
for id=5,11 do assert(state[id]==1) end
assert(R.follow_end(board,state,train,5,8)==11)
assert(R.view(board,state).tile(10).reserved and not row[10].reserved)
assert(not R.waiting_free(board,state,train,11,8))
assert(R.safe_end(board,state,train,11,8,true))
assert(not R.safe_end(board,state,train,11,8,false),"line end ignoring caller's policy")
assert(R.unreserve(board,state,5,X) and R.follow_end(board,state,train,5,8)==5)

-- Platform low-level contract writes a prefix, while the high-level path
-- transaction above rolls that prefix back on refusal.
local platform,gap,written=R.reserve_platform(board,{[10]=1},11,T.NE,nil)
assert(not platform and gap==10 and #written==1 and written[1]==11)

board,train,best,row=corridor(true)
state={[5]=1}
target=R.choose_target(board,state,train,best)
assert(target.tile==8 and target.td==8,"path allocations must end before rather than on a PBS entrance")
assert(R.try_path(board,state,train,target))
assert(state[8]==1 and not state[9] and not state[10] and not state[11])
local staged=R.view(board,state)
assert(staged.tile(9).green_signals==0 and row[9].present_signals==4,
  "track reservation changed a signal aspect")

-- Parallel half-tracks legally carry independent reservations. Opposite
-- trackdirs on one physical piece are not separate lane reservations.
local bitsboard={tile=function()return straight("rail",{trackbits=63}) end}
state={}
assert(R.try_reserve(bitsboard,state,1,T.UPPER))
assert(R.try_reserve(bitsboard,state,1,T.LOWER))
assert(not R.try_reserve(bitsboard,state,1,T.UPPER))
assert(not R.try_reserve(bitsboard,state,1,T.LEFT))
assert(R.unreserve(bitsboard,state,1,T.UPPER) and state[1]==8)
assert(R.unreserve(bitsboard,state,1,T.LOWER) and not state[1])

local loop={
  [8+8*16]=straight("rail",{trackbits=4}),
  [7+8*16]=straight("rail",{trackbits=16}),
  [7+7*16]=straight("rail",{trackbits=8}),
  [8+7*16]=straight("rail",{trackbits=32}),
}
local axis={[0]=-1,16,1,-16}
local ring={tile=function(i)return loop[i] end,adjacent=function(i,d)return i+axis[d] end}
local ring_state={}
for id,r in pairs(loop) do
  local tr=0
  while not T.has(r.trackbits,tr) do tr=tr+1 end
  assert(R.try_reserve(ring,ring_state,id,tr))
end
local end_tile,end_td=R.follow_end(ring,ring_state,train,8+8*16,2)
assert(end_tile==7+8*16 and end_td==12,"reservation on a loop did not stop at its repeated directional state")
print("PASS: stock directional reservation transaction, PBS waiting point, platform rollback, independent parallels and loop termination")
