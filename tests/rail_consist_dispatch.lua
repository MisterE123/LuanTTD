local root="mods/bayline/"
local upstream=root.."openttd/"
local T=dofile(upstream.."rail_track.lua")
local F=dofile(upstream.."rail_follow.lua")(T)
local C=dofile(upstream.."rail_yapf_cost.lua")(T,F)
local M=dofile(upstream.."rail_motion.lua")(T)
local PBS=dofile(upstream.."rail_reservation.lua")(T,F,C)
local Life=dofile(upstream.."rail_consist_reservation.lua")(T,F,PBS)
local Motion=dofile(upstream.."rail_consist_motion.lua")(T,M,F,Life)
local new_dispatch=dofile(root.."rail_consist_dispatch.lua")
local D=new_dispatch(Motion,Life)
local deltas={[0]=-1,32,1,-32}
local function id(x,y) return x+y*32 end
local tiles={}
local function put(x,y,bits,options)
  local k=id(x,y)
  local rec={kind="rail",owner="A",railtype=0,trackbits=bits}
  for k,v in pairs(options or {}) do rec[k]=v end
  tiles[k]=rec
  return k
end
local board={tile=function(i)return tiles[i] end,adjacent=function(i,d)return i+deltas[d] end,
  xy=function(i)return i%32,math.floor(i/32) end,tile_at=id}
local function straight(_,_,d,bits)
  local td=T.diagonal_trackdir(d)
  if T.has(bits,td) then return td end
end
local function part(x,y,td)
  local tx,ty=math.floor(x/16),math.floor(y/16)
  return {tile=id(tx,ty),length=8,pose={x=x,y=y,tx=tx,ty=ty,td=td,direction=T.heading(td)}}
end
local function save(value)
  if type(value)~="table" then return value end
  assert(not getmetatable(value))
  local t={}
  for k,v in pairs(value) do t[k]=save(v) end
  return t
end
local crossing=put(5,5,3)
local east=put(6,5,1)
local signal=put(7,5,1,{kind="signals",present_signals=4,green_signals=4,upper_signal_type=4})
put(8,5,1)
local north=put(5,4,2)
local south=put(5,6,2)
local train=assert(Motion.place(board,"A",{part(111,88,8),part(103,88,8),part(95,88,8)}))
local opposing=assert(Motion.place(board,"A",{part(88,79,1)}))
local state=Life.new()
assert(D.register(board,state,1,train) and D.register(board,state,2,opposing))
local before=state.trains[1]
local function unchanged()
  assert(train.serial==0 and train.parts[1].tile==east and train.parts[3].tile==crossing)
  assert(state.trains[1]==before and state.claims[signal]==nil and state.bits[crossing]==1)
  assert(state.bits[east]==1 and state.bits[signal]==nil and tiles[signal].green_signals==4)
end
local response,why=D.step(board,state,1,train,straight,nil,function(_, staged, transition)
  assert(transition.tile==signal and staged.bits[crossing]==1)
  return false,"signal_red"
end)
assert(not response and why=="signal_red")
unchanged()
response,why=D.step(board,state,2,opposing,straight)
assert(not response and why=="overlap" and opposing.parts[1].tile==north)
unchanged()

-- Force a failure AFTER real front entry and target acquisition to verify
-- the earlier edits and before-position events cannot be published.
local intercepted={}
for k,v in pairs(Life) do intercepted[k]=v end
function intercepted.enter(b,s,i,index,...)
  if index==3 then
    assert(s.bits[signal]==1 and s.trains[1].parts[1].tile==signal)
    return false,"late_tail_denial"
  end
  return Life.enter(b,s,i,index,...)
end
response,why=new_dispatch(Motion,intercepted).step(board,state,1,train,straight)
assert(not response and why=="late_tail_denial")
unchanged()

state,train,opposing=save(state),save(train),save(opposing)
assert(Life.valid_state(board,state))
assert(not D.step(board,state,2,opposing,straight))
local r=assert(D.step(board,state,1,train,straight))
assert(#r.events==4 and r.events[1].kind=="front_passed_pbs" and r.events[2].kind=="front_entered")
assert(r.events[3].kind=="tail_released" and r.events[4].kind=="tail_left")
assert(r.events[3].tile==crossing and state.bits[crossing]==nil and state.claims[crossing]==nil)
assert(tiles[signal].green_signals==4,"signal authority is external, not a mutation here")
assert(state.bits[signal]==1 and train.parts[1].tile==signal and train.parts[3].tile==east)
assert(D.step(board,state,2,opposing,straight) and state.bits[crossing]==2)
assert(Motion.check_spacing(board,train) and Life.valid_state(board,state))
-- Continue through an ordinary non-boundary step; no accidental release.
r=assert(D.step(board,state,1,train,straight))
assert(#r.events==0 and state.bits[east]==1 and train.parts[1].pose.x==113)
assert(Life.valid_state(board,state))
print("PASS: atomic front/back source transitions, signal gate, late denial rollback, reload, and conflict relief on exact tail crossing")
