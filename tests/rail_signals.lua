local root="mods/bayline/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local C=dofile(root.."rail_yapf_cost.lua")(T,F)
local Y=dofile(root.."rail_yapf_search.lua")(T,F,C)
local PBS=dofile(root.."rail_reservation.lua")(T,F,C)
local Life=dofile(root.."rail_consist_reservation.lua")(T,F,PBS)
local Signal=dofile(root.."rail_signals.lua")(T)
local d={[0]=-1,16,1,-16}
local tiles={}
local function id(x,y)return x+y*16 end
local function place(x,y,bits,opts)
  local k=id(x,y)
  local t={kind="rail",owner=1,railtype=0,trackbits=bits}
  for key,value in pairs(opts or {}) do t[key]=value end
  tiles[k]=t
  return k
end
local a_origin=place(5,5,3)
local a_exit=place(6,5,1)
local b_origin=place(5,3,2)
local b_signal=place(5,4,2)
local b_after=place(5,6,2)
local b_end=place(5,7,2,{kind="station",station=2,axis=1})
local board={tile=function(i)return tiles[i]end,adjacent=function(i,s)return i+d[s]end,
  railtype=function()return {compatible={[0]=true}}end,
  xy=function(i)return i%16,math.floor(i/16)end,tile_at=id,
  station_area=function()return {tile=b_end,w=1,h=1},b_end end}
local aspects=Signal.new()
local reg=Life.new()
assert(not Signal.place(board,aspects,1,a_origin,0,{kind=Signal.PBS}),
  "stock PBS cannot be placed on overlapping X/Y")
assert(Signal.place(board,aspects,1,b_signal,1,{kind=Signal.PBS}))
local function view() return Signal.view(board,aspects) end
assert(view().tile(b_signal).present_signals==T.signal_along(1))
assert(Signal.aspect(view().tile(b_signal),1)=="red")
assert(tiles[b_signal].kind=="rail","aspect overlay mutated base geometry")
assert(Signal.pbs_along(view().tile(b_signal),1))
assert(not Signal.oneway_blocking(view().tile(b_signal),9))
local back=Signal.capture_entry(view().tile(b_signal),T.NW,9,false)
assert(back.tracks==2 and not T.has(back.red_tracks,T.Y),
  "normal PBS backside must not be treated as a red signal")

assert(Life.register(view(),reg,100,1,{{tile=a_origin,td=8},{tile=a_origin,td=8}}))
assert(Life.register(view(),reg,200,1,{{tile=b_origin,td=1}}))
local train={owner=1,tile=b_origin,length=8,max_speed=80,railtype=0,compatible={[0]=true}}
local function reserve(opened)
  assert(Signal.aspect(opened.tile(b_signal),1)=="green","search did not see temporarily opened aspect")
  local look=Life.view(opened,reg)
  local goal=C.destination(look,train,{kind="station",station=2})
  local found,best=Y.find(look,train,{tile=b_origin,td=1},goal)
  if not found then return false end
  local target=PBS.choose_target(opened,reg.bits,train,best)
  return Life.reserve_path(opened,reg,200,target)
end
local function choose()
  return Signal.try_single_path_signal(board,aspects,b_signal,T.SE,2,reg.bits[b_signal],reserve)
end

local track,status=choose()
assert(track==T.Y and status=="reservation_failed")
assert(Signal.aspect(view().tile(b_signal),1)=="red" and not reg.bits[b_signal] and not reg.bits[b_end])
assert(Life.enter(view(),reg,100,1,a_exit,8))
track,status=choose()
assert(status=="reservation_failed" and Signal.aspect(view().tile(b_signal),1)=="red",
  "engine departure must not make the conflicting route green with its tail still on X")
assert(Life.enter(view(),reg,100,2,a_exit,8))
local red_snapshot=Signal.capture_entry(view().tile(b_signal),T.SE,1,false)
track,status=choose()
assert(track==1 and status=="reserved")
assert(Signal.aspect(view().tile(b_signal),1)=="green")
assert(reg.bits[b_signal]==2 and reg.bits[a_origin]==2 and reg.bits[b_after]==2 and reg.bits[b_end]==2)
assert(Life.valid_state(view(),reg))
local waiting={speed=44,subspeed=37,progress=24,wait_counter=0,force=0}
assert(Signal.entry_wait(view().tile(b_signal),red_snapshot,track,waiting)=="wait",
  "controller replaced its captured red with the aspect staged later in the same pass")
assert(waiting.speed==0 and waiting.subspeed==0 and waiting.progress==255)
assert(choose()==T.Y)
local green=Signal.capture_entry(view().tile(b_signal),T.SE,1,false)
assert(Signal.entry_wait(view().tile(b_signal),green,track,waiting)=="enter")
local success,events=Life.enter(view(),reg,200,1,b_signal,1)
assert(success)
for _,e in ipairs(events) do
  if e.kind=="front_passed_pbs" then assert(Signal.apply_consist_event(board,aspects,e)) end
end
assert(Signal.aspect(view().tile(b_signal),1)=="red","front passage did not close PBS")
assert(reg.bits[b_signal]==2 and reg.bits[a_origin]==2,
  "signal closing incorrectly cleared track ownership")

-- A physically identical facing signal becomes blocking in reverse
-- direction only when its actual type is the stock one-way variant.
local other=Signal.new()
assert(Signal.place(board,other,1,b_signal,T.Y,{kind=Signal.PBS_ONEWAY}))
local next_=Signal.view(board,other).tile(b_signal)
assert(Signal.oneway_blocking(next_,9) and not Signal.pbs_along(next_,9))
local denied=Signal.capture_entry(next_,T.NW,9,false)
assert(T.has(denied.red_tracks,T.Y))
local v={speed=44,subspeed=37,progress=24,wait_counter=0,force=0}
assert(Signal.entry_wait(next_,denied,T.Y,v,{execute_reverse=false})=="reverse")

local parallel=place(10,10,12)
assert(Signal.place(board,other,1,parallel,T.UPPER,{kind=Signal.PBS},4,true))
local signal=Signal.view(board,other).tile(parallel)
assert(Signal.aspect(signal,2)=="red","stock placement requires the entire tile to be empty before green")
assert(Signal.place(board,other,1,parallel,T.LOWER,{kind=Signal.PBS},8,false))
signal=Signal.view(board,other).tile(parallel)
assert(Signal.aspect(signal,2)=="red" and Signal.aspect(signal,3)=="green",
  "parallel placement overwrote the unrelated signal group")
print("PASS: directional PBS placement, wrong-way admission, real YAPF reservation, tail-controlled wait, and signal consumption")
