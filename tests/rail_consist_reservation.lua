local root="mods/luanttd_core/openttd/"
local T=dofile(root.."rail_track.lua")
local F=dofile(root.."rail_follow.lua")(T)
local C=dofile(root.."rail_yapf_cost.lua")(T,F)
local Y=dofile(root.."rail_yapf_search.lua")(T,F,C)
local P=dofile(root.."rail_reservation.lua")(T,F,C)
local R=dofile(root.."rail_consist_reservation.lua")(T,F,P)
local side={[0]=-1,16,1,-16}
local tiles={}
local function tile(x,y,bits,options)
  local id=x+y*16
  local rec={railtype=0,owner=1,kind="rail",trackbits=bits}
  for k,v in pairs(options or {}) do rec[k]=v end
  tiles[id]=rec
  return id
end
local board={tile=function(id)return tiles[id] end,
  adjacent=function(id,d)return id+side[d] end,
  xy=function(id)return id%16,math.floor(id/16) end,
  tile_at=function(x,y)return x+y*16 end,
  station_area=function()return {tile=8+5*16,w=2,h=1},8+5*16 end}
local function part(id,td) return {tile=id,td=td} end
local function tagged(ok,events,...)
  assert(ok,events)
  local expected={...}
  assert(#events==#expected)
  for i,word in ipairs(expected) do assert(events[i].kind==word,events[i].kind.." ~= "..word) end
  return events
end
local function serial(v)
  if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
  if type(v)=="string" then return string.format("%q",v) end
  assert(type(v)=="table","the saved claim registry contains runtime objects")
  local out={"{"}
  for k,p in pairs(v) do out[#out+1]="["..serial(k).."]="..serial(p).."," end
  out[#out+1]="}"
  return table.concat(out)
end

local crossing=tile(5,5,3) -- true overlapping X/Y rail geometry, not a road crossing
local east=tile(6,5,1,{kind="signals",present_signals=4,green_signals=4,upper_signal_type=4})
local north=tile(5,4,2)
local reg=R.new()
assert(R.register(board,reg,1,1,{part(crossing,8),part(crossing,8)}))
assert(R.register(board,reg,2,1,{part(north,1)}))
assert(R.valid_state(board,reg))
assert(reg.bits[crossing]==1 and R.claim_owner(reg,crossing,T.X)==1)

local ok,events=R.enter(board,reg,1,1,east,8,nil,function(event)
  local live=reg.trains[1].parts[1].tile
  if event.kind=="front_passed_pbs" then assert(live==crossing) end
  if event.kind=="front_entered" then assert(live==east) end
end)
local engine=tagged(ok,events,"front_passed_pbs","front_entered")
assert(engine[1].phase=="before_position" and engine[1].aspect=="red")
assert(engine[2].phase=="after_position" and engine[2].enterdir==T.SW)
assert(tiles[east].green_signals==4,"emitting a signal event must not silently run aspect propagation")
assert(reg.trains[1].parts[1].tile==east and reg.trains[1].parts[2].tile==crossing)
assert(reg.bits[crossing]==1, "engine passing a signal cleared its wagon's crossing reservation")
local no,why=R.enter(board,reg,2,1,crossing,1)
assert(not no and why=="overlap" and reg.trains[2].parts[1].tile==north)

-- Carry the exact train slots, part positions and per-track owners through
-- serialized bytes; no transient closures or reconstructed optimistic lock.
local bytes=serial(reg)
local loaded=assert(loadstring("return "..bytes))()
local again=dofile(root.."rail_consist_reservation.lua")(T,F,P)
assert(again.valid_state(board,loaded))
assert(not again.enter(board,loaded,2,1,crossing,1),"orthogonal train entered occupied crossing after reload")
local ok,events=again.enter(board,loaded,1,2,east,8,nil,function(event)
  local live=loaded.trains[1].parts[2].tile
  if event.kind=="tail_released" then assert(live==crossing and not loaded.bits[crossing]) end
  if event.kind=="tail_left" then assert(live==east) end
end)
local tail=tagged(ok,events,"tail_released","tail_left")
assert(tail[1].tile==crossing and tail[1].track==T.X and tail[1].phase=="before_position")
assert(tail[2].tile==crossing and tail[2].enterdir==T.NE and tail[2].phase=="after_position")
assert(not loaded.bits[crossing] and loaded.bits[east]==1)
local ok,events=again.enter(board,loaded,2,1,crossing,1)
local next_events=tagged(ok,events,"tail_released","front_entered","tail_left")
assert(next_events[1].tile==north and next_events[2].tile==crossing)
assert(loaded.bits[crossing]==2 and again.claim_owner(loaded,crossing,T.Y)==2)
assert(again.valid_state(board,loaded))

-- Parallel half-tile pieces are independent reservations, even on the
-- very same map tile. Moving Upper's sole unit releases only its bit.
local shared=tile(10,10,12)
local left=tile(9,10,1)
local lower_dest=tile(11,10,1)
local halves=again.new()
assert(again.register(board,halves,"upper",1,{part(shared,2)}))
assert(again.register(board,halves,"lower",1,{part(shared,11)}))
assert(halves.bits[shared]==12 and R.claim_owner(halves,shared,T.LOWER)=="lower")
assert(again.enter(board,halves,"upper",1,left,0))
assert(halves.bits[shared]==8 and not again.claim_owner(halves,shared,T.UPPER))
assert(again.claim_owner(halves,shared,T.LOWER)=="lower" and again.valid_state(board,halves))
assert(again.enter(board,halves,"lower",1,lower_dest,8))
assert(not halves.bits[shared])

-- An engine's allocated station platform remains held each time the rear
-- steps internally past another tile of the same platform.
local st1=tile(8,5,1,{kind="station",axis=0,station=9})
local st2=tile(9,5,1,{kind="station",axis=0,station=9})
local yard=tile(10,5,1)
local approach=tile(7,5,1)
local p=R.new()
assert(R.register(board,p,"local",1,{part(st1,8)}))
assert(R.enter(board,p,"local",1,st2,8))
assert(p.bits[st1]==1 and p.bits[st2]==1)
local ok,events=R.enter(board,p,"local",1,yard,8)
local drop=tagged(ok,events,"tail_released","tail_released","front_entered","tail_left")
assert(drop[1].tile==st2 and drop[2].tile==st1 and p.bits[yard]==1)
assert(not p.bits[st1] and not p.bits[st2] and R.valid_state(board,p))
assert(not R.register(board,p,"refused",1,{part(approach,8),part(yard,8)}))
assert(not p.bits[approach] and R.claim_owner(p,yard,T.X)=="local","failed registration did not roll back")

-- Planned path allocation preserves ownership for each stock track bit,
-- explicitly excluding the already occupied start. Origin 7 -> real st 9.
local v={owner=1,railtype=0,compatible={[0]=true},tile=approach,length=8,max_speed=80}
local destinations=C.destination(board,v,{kind="station",station=9})
local found,best=Y.find(board,v,{tile=approach,td=8},destinations)
assert(found)
local planned=R.new()
assert(R.register(board,planned,42,1,{part(approach,8)}))
local target=P.choose_target(board,planned.bits,v,best)
assert(R.reserve_path(board,planned,42,target))
assert(R.claim_owner(planned,st1,T.X)==42 and R.claim_owner(planned,st2,T.X)==42)
assert(R.valid_state(board,planned))
-- Existing guideway reservation ownership can be restored for every
-- stock rail type, but front-engine motion still follows RC1 power masks.
for gauge=0,3 do
  local a=tile(2,1,1,{railtype=gauge})
  local b=tile(3,1,1,{railtype=gauge})
  local front=tile(4,1,1,{railtype=(gauge+2)%4})
  local db=R.new()
  assert(R.register(board,db,"typed",1,{part(a,8),part(a,8)},{engine_railtype=gauge}))
  assert(R.enter(board,db,"typed",1,b,8))
  assert(R.enter(board,db,"typed",2,b,8))
  local ok,err=R.enter(board,db,"typed",1,front,8)
  assert(not ok and err=="incompatible_railtype",gauge)
  assert(db.bits[b]==1 and not db.bits[front] and R.valid_state(board,db),gauge)
end
print("PASS: two trains at a crossing, front/tail event order, persisted ownership, platform hold/release, independent half tracks")
