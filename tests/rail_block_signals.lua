local dir="mods/bayline/openttd/"
local T=dofile(dir.."rail_track.lua")
local R=dofile(dir.."rail_signals.lua")(T)
local B=dofile(dir.."rail_block_signals.lua")(T,R)
local delta={[0]=-1,64,1,-64}
local tiles,physical
local state
local board={
  adjacent=function(id,side) return id+delta[side] end,
  tile=function(id) return tiles[id] end,
}
local function parts(id) return physical[id] end
local function reset() tiles,physical,state={},{},R.new() end
local function rail(id,bits,owner)
  tiles[id]={kind="rail",trackbits=bits or 1,owner=owner or 1}
end
local function signal(id,bits,present,kind,green)
  rail(id,bits)
  local t=tiles[id]
  t.kind="signals"
  t.present_signals=present
  t.green_signals=green or 15
  t.upper_signal_type=kind or R.BLOCK
  t.lower_signal_type=kind or R.BLOCK
end
local function aspect(id,td) return R.aspect(R.view(board,state).tile(id),td) end
local function update(tile,side)
  return B.update_segment(board,state,1,parts,tile,side)
end

-- Bidirectional physically clear engine end but the final carriage has
-- not exited. Adjacent block/aspect on the same signal remains separate.
for travel=0,3 do
  reset()
  local first=522
  local step=delta[travel]
  local bit=2^(travel%2)
  local tr=travel%2
  local next_signal=first+4*step
  local td=T.trackdir_for_entry(tr,travel)
  local rev=T.reverse_trackdir(td)
  for i=-1,5 do rail(first+i*step,bit) end
  signal(first,bit,12); signal(next_signal,bit,12)
  assert(update(first,travel)==B.FREE)
  assert(aspect(first,td)=="green" and aspect(first,rev)=="green")
  physical[first]={bit}
  local needs_reservation,changes,over=B.train_moved_change_signals(board,state,parts,first,travel)
  assert(not needs_reservation and #changes==2 and not over)
  assert(aspect(first,td)=="red" and aspect(first,rev)=="green")
  assert(aspect(next_signal,rev)=="red" and aspect(next_signal,td)=="green")
  local approach={speed=44,subspeed=83,progress=0}
  local t=R.view(board,state).tile(first)
  assert(R.entry_wait(t,R.capture_entry(t,travel,td),tr,approach)=="wait")
  assert(approach.speed==0 and approach.subspeed==0 and approach.progress==255)
  physical[first]=nil; physical[next_signal-2*step]={bit}
  physical[next_signal]={bit}
  -- First vehicle on the second boundary closes its new block, but
  -- cannot reopen the previous block while the rear is in it.
  B.train_moved_change_signals(board,state,parts,next_signal,travel)
  assert(aspect(first,td)=="red" and aspect(next_signal,td)=="red")
  physical[next_signal-2*step]=nil
  assert(update(first,travel)==B.FULL) -- even the boundary tile is occupied
  -- Copy the save exactly as the host will: persist only committed masks,
  -- not ephemeral traversal buffers. Rebuild physical occupancy from parts.
  local saved=R.new()
  for id,rec in pairs(state.records) do
    saved.records[id]={}
    for k,v in pairs(rec) do saved.records[id][k]=v end
  end
  state=saved
  assert(aspect(first,td)=="red")
  physical[next_signal]=nil; physical[next_signal+step]={bit}
  B.train_moved_change_signals(board,state,parts,next_signal,T.reverse_side(travel))
  assert(aspect(first,td)=="green" and aspect(next_signal,rev)=="green")
  t=R.view(board,state).tile(first)
  assert(R.entry_wait(t,R.capture_entry(t,travel,td),tr,approach)=="enter")
  assert(aspect(next_signal,td)=="red")
end

-- Ordinary junction search sees all three sides and one train occupies the
-- block across all branches. Foreign company track is a boundary.
reset()
local jun,left,right,top=530,528,532,402
signal(left,1,12)
rail(left+1)
rail(jun,1+16)
rail(right-1)
signal(right,1,12)
rail(top+64,2)
signal(top,2,12)
physical[top+64]={2}
assert(update(left,T.SW)==B.FULL)
assert(aspect(left,8)=="red" and aspect(right,0)=="red" and aspect(top,1)=="red")
physical[top+64]=nil
assert(update(left,T.SW)==B.FREE)
assert(aspect(left,8)=="green" and aspect(right,0)=="green" and aspect(top,1)=="green")
tiles[top+64].owner=2; physical[top+64]={2}
assert(update(left,T.SW)==B.FREE)
assert(aspect(left,8)=="green")

-- Independent half tracks don't inherit occupancy from the opposite lane.
-- An unsignaled branch, however, is governed by the shared interlocked block.
for _,raw in ipairs({{12,2,3},{48,4,5}}) do
  reset()
  local both,first,second=raw[1],raw[2],raw[3]
  signal(522,both,15)
  local td,other=first,second
  physical[522]={T.trackbit(second)}
  assert(update(522,T.exit_side(td))==B.FREE)
  assert(update(522,T.exit_side(other))==B.FULL)
  assert(aspect(522,td)=="green" and aspect(522,other)=="red")
end

-- A pre-signal Exit itself changes due to a train on the far block; its
-- queued back-propagation turns the Entry red across the empty near block.
reset()
signal(518,1,4,R.ENTRY); rail(519); rail(520)
signal(521,1,4,R.EXIT); rail(522)
physical[522]={1}
local result,changed=update(521,T.SW)
assert(result==B.FULL and #changed==2)
assert(changed[1].tile==521 and changed[2].tile==518)
physical[522]=nil
result,changed=update(521,T.SW)
assert(result==B.FREE and #changed==2)
assert(aspect(518,8)=="green" and aspect(521,8)=="green")

-- A facing PBS_ONEWAY at the far end does not classify this side as PBS,
-- ordinary PBS does. Block propagation must never force the PBS lamp green.
reset()
signal(518,1,4,R.BLOCK); rail(519)
signal(520,1,4,R.PBS,0)
assert(B.train_moved_change_signals(board,state,parts,518,T.SW))
assert(aspect(520,8)=="red")
tiles[520].upper_signal_type=R.PBS_ONEWAY
assert(not B.train_moved_change_signals(board,state,parts,518,T.SW))
assert(aspect(520,8)=="red")

-- Bound source update structures without partially applying stale aspects.
reset()
for x=8,59 do
  rail(640+x,3)
  signal(576+x,2,12,R.BLOCK,0)
  signal(704+x,2,12,R.BLOCK,0)
end
local end_state,list,overflow=update(648,T.NE)
assert(end_state==B.FULL and #list==0 and overflow)
assert(next(state.records)==nil)

print("rail block signal integration fixture: directional head/tail, wait/reload, junction, parallel lanes and pre-signals passed")
