local root="mods/bayline/"
local function stock(file,...) return dofile(root.."openttd/"..file..".lua")(...) end
local T=dofile(root.."openttd/rail_track.lua")
local F=stock("rail_follow",T)
local C=stock("rail_yapf_cost",T,F)
local S=stock("rail_yapf_search",T,F,C)
local M=stock("rail_motion",T)
local P=stock("rail_reservation",T,F,C)
local Life=stock("rail_consist_reservation",T,F,P)
local Sig=stock("rail_signals",T)
local Motion=stock("rail_consist_motion",T,M,F,Life)
local D=dofile(root.."rail_consist_dispatch.lua")(Motion,Life)
local Speed=stock("rail_station_speed",T,F)
local Sim={}
function Sim.id(x,y) if x>=0 and y>=0 and x<32 and y<32 then return x+y*32 end end
function Sim.xy(id) return id%32,math.floor(id/32) end
function Sim.adjacent(id,dir)
  local x,y=Sim.xy(id)
  local dx,dy={0,1,0,-1},{-1,0,1,0}
  return Sim.id(x+dx[dir],y+dy[dir])
end
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,{},C,S)
local Block=stock("rail_block_signals",T,Sig)
local R=dofile(root.."rail_dispatch_run.lua")(
  T,F,C,S,P,Life,Sig,Motion,D,Speed,Lab,nil,nil,nil,nil,nil,Block)
local id=Sim.id
local owner="Alice"
local entry_x,entry_y,exit_x,exit_y,cross=id(7,9),id(9,8),id(11,9),id(9,11),id(9,9)
local dep_x,dep_y=id(3,9),id(9,4)
local function fixture(enabled,parts)
  local s={tiles={},topology=0,rail_block_preview=enabled}
  local function put(x,y,bit)
    local i=id(x,y)
    local old=s.tiles[i]
    s.tiles[i]={owner=owner,rail_tracks=(old and old.rail_tracks or 0)+bit}
  end
  for x=3,16 do put(x,9,1) end
  for y=4,16 do put(9,y,2) end
  assert(Lab.depot(s,owner,dep_x,T.SW))
  assert(Lab.depot(s,owner,dep_y,T.SE))
  assert(Lab.station(s,owner,id(14,9),id(16,9)))
  assert(Lab.station(s,owner,id(9,14),id(9,16)))
  if parts then
    assert(R.place_signal(s,owner,entry_x,8,Sig.BLOCK))
    assert(R.place_signal(s,owner,entry_y,1,Sig.BLOCK))
    assert(R.place_signal(s,owner,exit_x,8,Sig.BLOCK))
    assert(R.place_signal(s,owner,exit_y,1,Sig.BLOCK))
  end
  return s
end
local off=fixture(false,false)
assert(not R.place_signal(off,owner,entry_x,8,Sig.BLOCK))
assert(not R.start_block(off,owner,dep_x,1))
assert(not R.current(off))
local wrong=fixture(true,false)
assert(R.place_signal(wrong,owner,entry_x,0,Sig.BLOCK))
assert(R.place_signal(wrong,owner,exit_x,8,Sig.BLOCK))
assert(not R.start_block(wrong,owner,dep_x,1))
local no_exit=fixture(true,false)
assert(R.place_signal(no_exit,owner,entry_x,8,Sig.BLOCK))
assert(not R.start_block(no_exit,owner,dep_x,1))
local path=fixture(true,false)
assert(R.place_signal(path,owner,entry_x,8,Sig.PBS))
assert(not R.place_signal(path,owner,exit_x,8,Sig.BLOCK))
assert(not R.start_block(path,owner,dep_x,1))

local s=fixture(true,true)
assert(R.signal(s,entry_x,8)=="green" and R.signal(s,entry_y,1)=="green")
assert(R.signal(s,entry_x,0)==nil and R.signal(s,entry_y,9)==nil)
assert(not R.place_signal(s,owner,id(10,9),8,Sig.PBS))
assert(not R.start(s,owner,dep_x,1))
local ok,msg=R.start_block(s,owner,dep_x,1);assert(ok,msg)
ok,msg=R.start_block(s,owner,dep_y,2);assert(ok,msg)
assert(not R.start_block(s,owner,dep_x,2))
local function save(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local y={}
  for k,v in pairs(x) do y[k]=save(v) end
  return y
end
local function no_reservations(d)
  assert(not next(d.life.trains) and not next(d.life.bits) and not next(d.life.claims))
end
local witness={arrived=0}
for tick=1,5000 do
  local events=R.tick(s,1)
  local d=assert(R.current(s))
  no_reservations(d)
  assert(not d.failure,d.failure)
  for _,e in ipairs(events) do
    if arg[1]=="--debug" and (e.kind~="front_entered" and e.kind~="tail_left" or
          e.tile==cross or e.tile==entry_x or e.tile==entry_y or e.tile==exit_x or e.tile==exit_y) then
      print(e.tick,e.train,e.kind,e.tile,e.reason,e.aspect)
    end
    if e.kind=="front_entered" and e.tile==cross then
      if witness.first then
        witness.second=e
        assert(witness.tail_exit and e.train~=witness.first.train and e.tick>=witness.tail_exit.tick)
      else witness.first=e end
    elseif e.kind=="waiting" then
      assert(e.reason=="red_block_signal")
      witness.wait=e
    elseif e.kind=="tail_left" and witness.first and e.train==witness.first.train then
      if e.tile==cross then witness.tail_cross=e end
      if e.tile==(e.train==1 and exit_x or exit_y) then witness.tail_exit=e end
    elseif e.kind=="arrived" then witness.arrived=witness.arrived+1 end
  end
  local crossed,wagon_only=0,false
  for _,r in ipairs(d.runs) do
    local on_cross=false
    for _,p in ipairs(r.consist.parts) do if p.tile==cross then on_cross=true end end
    if on_cross then crossed=crossed+1 end
    if r.consist.parts[2].tile==cross and r.consist.parts[1].tile~=cross then wagon_only=true end
  end
  assert(crossed<=1,"two physical consists occupied one diamond")
  if witness.first and not witness.tail_exit then
    local other=witness.first.train==1 and entry_y or entry_x
    local td=witness.first.train==1 and 1 or 8
    assert(R.signal(s,other,td)=="red","physical block went green before the last wagon cleared the next head")
    if wagon_only and not witness.reloaded then
      s=save(s);witness.reloaded=true
      s.rail_block_preview=false
      local count=d.ticks
      assert(#R.tick(s,3)==0 and R.current(s).ticks==count,"preview disabled on reopen must freeze")
      s.rail_block_preview=true
    end
  end
  if witness.arrived==2 then break end
end
assert(witness.first and witness.wait and witness.reloaded and witness.tail_cross and witness.tail_exit and witness.second)
assert(witness.wait.train~=witness.first.train and witness.wait.tick<witness.tail_exit.tick)
assert(witness.tail_cross.tick<witness.tail_exit.tick)
local d=R.current(s)
assert(witness.arrived==2)
for i,r in ipairs(d.runs) do
  assert(r.phase=="arrived" and r.station==i and Motion.check_spacing(R.board(s),r.consist))
  assert(R.sample(r,1) and R.sample(r,2))
end
assert(R.signal(s,exit_x,8)=="red" and R.signal(s,exit_y,1)=="red")
assert(R.signal(s,entry_x,8)=="green" and R.signal(s,entry_y,1)=="green")
assert(R.clear(s,owner))
assert(R.signal(s,exit_x,8)=="green" and R.signal(s,exit_y,1)=="green")
assert(not next(R.current(s).runs))
assert(R.start_block(s,owner,dep_x,1))
s.tiles[exit_x]=nil;s.topology=s.topology+1
local fault=R.tick(s)
assert(#fault==1 and fault[1].kind=="blocked")
print(("PASS conventional dispatch: wait %d, wagon left diamond %d, block reopened %d, competitor entered %d, both parked"):format(
  witness.wait.tick,witness.tail_cross.tick,witness.tail_exit.tick,witness.second.tick))
