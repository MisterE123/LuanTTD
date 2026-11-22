local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local C=dofile(root.."rail_yapf_cost.lua")(T,F)
local M=dofile(root.."rail_motion.lua")(T)
local PBS=dofile(root.."rail_reservation.lua")(T,F,C)
local Life=dofile(root.."rail_consist_reservation.lua")(T,F,PBS)
local Motion=dofile(root.."rail_consist_motion.lua")(T,M,F,Life)
local deltas={[0]=-1,32,1,-32}
local tiles={}
local function id(x,y) return x+y*32 end
local function put(x,y,bits,options)
  local k=id(x,y)
  local rec={kind="rail",owner=1,railtype=0,trackbits=bits}
  for a,b in pairs(options or {}) do rec[a]=b end
  tiles[k]=rec
  return k
end
local board={tile=function(i)return tiles[i] end,adjacent=function(i,d)return i+deltas[d] end,
  xy=function(i)return i%32,math.floor(i/32) end,tile_at=id}
local function straight(_,_,d,bits)
  local t=T.diagonal_trackdir(d)
  if T.has(bits,t) then return t end
end

-- Stock delayed outbound depot activation occurs on the preceding unit's
-- proposed position; the released wagon moves exactly one pixel THAT step.
for travel=0,3 do
  tiles={}
  local ax,ay=15,15
  local dx,dy=({[0]=-1,0,1,0})[travel],({[0]=0,1,0,-1})[travel]
  local depot=put(ax,ay,2^(travel%2),{kind="depot",dir=travel})
  for j=1,5 do put(ax+j*dx,ay+j*dy,2^(travel%2)) end
  local chain=assert(Motion.seed_depot(board,depot,{7,4,3}))
  assert(not Motion.plan(board,chain,straight) and Motion.check_spacing(board,chain))
  assert(Motion.release_front(chain))
  local reveals={}
  for step=1,42 do
    local p,why=Motion.plan(board,chain,straight)
    assert(p,why)
    for _,r in ipairs(p.reveals) do reveals[r.index]=step end
    assert(Motion.commit(chain,p))
    assert(not Motion.commit(chain,p),"a stale proposal committed twice")
    assert(Motion.check_spacing(board,chain))
  end
  assert(reveals[2]==6 and reveals[3]==10,("direction %d or following length lost offset"):format(travel))
  assert(Motion.next_offset(7,4)==5 and Motion.next_offset(4,3)==4)
  local p=chain.parts
  assert(not p[3].hidden and Motion.chebyshev(p[1].pose,p[3].pose)==9)
end

local function persist(v)
  if type(v)~="table" then
    assert(type(v)=="number" or type(v)=="boolean" or type(v)=="string")
    return v
  end
  local copy={}
  for k,x in pairs(v) do copy[k]=persist(x) end
  return copy
end
local function place_part(x,y,td,length)
  local tx,ty=math.floor(x/16),math.floor(y/16)
  return {tile=id(tx,ty),length=length,pose={x=x,y=y,tx=tx,ty=ty,td=td,direction=T.heading(td)}}
end
local function register(state,train_id,k)
  local placed={}
  for i,p in ipairs(k.parts) do placed[i]={tile=p.tile,td=p.pose.td} end
  assert(Life.register(board,state,train_id,k.owner,placed))
end
local function apply(state,train_id,k,proposal)
  local saw={}
  for _,cross in ipairs(proposal.transitions) do
    local okay,events=Life.enter(board,state,train_id,cross.index,cross.tile,cross.td)
    if not okay then return false,events end
    for _,e in ipairs(events) do saw[#saw+1]=e end
  end
  assert(Motion.commit(k,proposal))
  return true,saw
end

-- This fixture advances real stock pixel spacing, not two hand-stepped
-- tile pointers. The rear remains seven stock px behind an odd-length
-- engine while the orthogonal locomotive waits at the boundary.
tiles={}
local crossing=put(5,5,3)
local east=put(6,5,1,{kind="signals",present_signals=4,green_signals=4,upper_signal_type=4})
put(7,5,1)
local north=put(5,4,2)
put(5,6,2)
local lead=assert(Motion.place(board,1,{place_part(95,88,8,7),place_part(88,88,8,7)}))
local waiting=assert(Motion.place(board,1,{place_part(88,79,1,8)}))
local state=Life.new()
register(state,1,lead);register(state,2,waiting)
local a=assert(Motion.plan(board,lead,straight))
local ok,e=apply(state,1,lead,a)
assert(ok and e[1].kind=="front_passed_pbs" and e[2].kind=="front_entered")
assert(lead.parts[1].tile==east and lead.parts[2].tile==crossing and state.bits[crossing]==1)
local attempt=assert(Motion.plan(board,waiting,straight))
local ok,why=apply(state,2,waiting,attempt)
assert(not ok and why=="overlap" and waiting.parts[1].pose.y==79)
lead,waiting,state=persist(lead),persist(waiting),persist(state)
assert(Life.valid_state(board,state) and Motion.check_spacing(board,lead))
for i=1,7 do
  local p=assert(Motion.plan(board,lead,straight))
  local moved,events=apply(state,1,lead,p)
  assert(moved and Motion.check_spacing(board,lead))
  if i<7 then
    assert(state.bits[crossing]==1)
    assert(not apply(state,2,waiting,attempt) and waiting.parts[1].tile==north)
  else
    assert(state.bits[crossing]==nil and events[1].kind=="tail_released")
  end
end
assert(apply(state,2,waiting,attempt) and waiting.parts[1].tile==crossing and waiting.parts[1].pose.y==80)
assert(state.bits[crossing]==2 and Life.valid_state(board,state))
print("PASS: delayed odd-length depot couplings in four directions, persisted physical crossing wait and final wagon release")
