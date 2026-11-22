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
local R=dofile(root.."rail_dispatch_run.lua")(T,F,C,S,P,Life,Sig,Motion,D,Speed,Lab)
local id=Sim.id
local s={tiles={},topology=0}
local function put(x,y,bit)
  local i=id(x,y)
  local old=s.tiles[i]
  s.tiles[i]={owner="Alice",rail_tracks=(old and old.rail_tracks or 0)+bit}
end
for x=3,16 do put(x,9,1) end
for y=4,16 do put(9,y,2) end
assert(Lab.depot(s,"Alice",id(3,9),T.SW))
assert(Lab.depot(s,"Alice",id(9,4),T.SE))
assert(Lab.station(s,"Alice",id(14,9),id(16,9)))
assert(Lab.station(s,"Alice",id(9,14),id(9,16)))
local sx,sy,ix=id(8,9),id(9,8),id(9,9)
assert(R.place_signal(s,"Alice",sx,8,Sig.PBS_ONEWAY))
assert(R.place_signal(s,"Alice",sy,1,Sig.PBS))
assert(R.signal(s,sx,8)=="red" and R.signal(s,sy,1)=="red" and R.signal(s,sy,9)==nil)
local ok,msg,a=R.start(s,"Alice",id(3,9),1);assert(ok,msg)
local ok,msg,b=R.start(s,"Alice",id(9,4),2);assert(ok,msg)
local preview=arg[1]=="--debug"
local function log(ev)
  if preview and (ev.tile==ix or ev.kind~="front_entered" and ev.kind~="tail_left" and ev.kind~="tail_released") then
    print(ev.tick,ev.train,ev.kind,ev.tile,ev.reason,ev.track)
  end
end
local function save(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local y={}
  for k,v in pairs(x) do y[k]=save(v) end
  return y
end
local crossed,held,reloaded,tail,second,arrived=nil,false,false,nil,nil,0
for tick=1,6000 do
  local d=R.current(s)
  local events=R.tick(s)
  assert(not d.failure,d.failure)
  for _,ev in ipairs(events) do
    log(ev)
    if ev.kind=="waiting" then held=ev end
    if ev.kind=="front_entered" and ev.tile==ix then
      if not crossed then crossed=ev
      else second=ev;assert(tail and tail.tick<=ev.tick and ev.train~=crossed.train) end
    end
    if ev.kind=="tail_released" and ev.tile==ix and not tail then tail=ev;assert(crossed and ev.train==crossed.train) end
    if ev.kind=="arrived" then arrived=arrived+1 end
  end
  if crossed and not tail then
    local path=crossed.train==1 and T.X or T.Y
    assert(Life.claim_owner(d.life,ix,path)==crossed.train)
    assert(Life.claim_owner(d.life,ix,1-path)==nil)
    local first=d.runs[crossed.train]
    local loser=3-crossed.train
    local other_signal,other_td=loser==1 and sx or sy,loser==1 and 8 or 1
    assert(R.signal(s,other_signal,other_td)=="red")
    if not reloaded and first.consist.parts[1].tile~=ix and first.consist.parts[2].tile==ix then
      s=save(s);reloaded=true
      assert(Life.valid_state(R.board(s),R.current(s).life))
      if preview then print("reloaded",tick,"loser phase",d.runs[loser].phase) end
    end
  end
  if arrived==2 then break end
end
local d=R.current(s)
assert(reloaded,"Never reloaded with only tail occupying crossing")
assert(held and held.train~=crossed.train and held.tick<tail.tick,"Competing consist did not wait for wagons")
assert(second and arrived==2,"Both trains did not clear crossing and arrive")
for i,run in ipairs(d.runs) do
  assert(run.phase=="arrived" and R.board(s).tile(run.arrival.tile).station==i)
  assert(Motion.check_spacing(R.board(s),run.consist))
  assert(Life.claim_owner(d.life,run.arrival.tile,i-1)==i,"Station must stay reserved while train is loading")
  local head,td,f=R.sample(run,1);local wagon,wtd,wf=R.sample(run,2)
  assert(head==run.arrival.tile and tonumber(f) and td==run.consist.parts[1].pose.td)
  assert(wagon and tonumber(wf) and wtd==run.consist.parts[2].pose.td)
end
assert(Life.valid_state(R.board(s),d.life))
assert(d.life.bits[ix]==nil)
assert(R.clear(s,"Alice"))
assert(#R.current(s).runs==0 and not next(R.current(s).life.bits))
assert(R.signal(s,sx,8)=="red" and R.signal(s,sy,1)=="red")
print("PASS: ordered stock two-consist depot-to-platform dispatch, PBS wait, tail release across reload, second train proceeds")

-- A non-stop order drives through another real multi-tile platform.
-- The entire platform keeps its claim until the final vehicle exits, as
-- in ClearPathReservation. The destination remains occupied at loading.
assert(Lab.station(s,"Alice",id(11,9),id(12,9)))
local first_platform,last_platform=id(11,9),id(12,9)
local aok,amsg,only=R.start(s,"Alice",id(3,9),1);assert(aok,amsg)
local was_on_platform,released=false,false
for _=1,1000 do
  local events=R.tick(s)
  local state=R.current(s)
  assert(not state.failure,state.failure)
  for _,ev in ipairs(events) do
    if ev.kind=="tail_released" and ev.tile==last_platform then
      assert(was_on_platform and ev.train==1)
      assert(Life.claim_owner(state.life,first_platform,T.X)==nil)
      assert(Life.claim_owner(state.life,last_platform,T.X)==nil)
      released=true
    end
  end
  local head,rear=only.consist.parts[1].tile,only.consist.parts[2].tile
  if head==id(13,9) and rear==last_platform then
    was_on_platform=true
    assert(Life.claim_owner(state.life,first_platform,T.X)==1)
    assert(Life.claim_owner(state.life,last_platform,T.X)==1)
  end
  if only.phase=="arrived" then break end
end
assert(released and only.phase=="arrived")
assert(R.clear(s,"Alice"))
assert(R.start(s,"Alice",id(3,9),1))
s.tiles[id(7,9)]=nil;s.topology=s.topology+1
local rejected=R.tick(s)
assert(#rejected==1 and rejected[1].kind=="blocked" and R.current(s).runs[1].phase=="blocked")
assert(R.clear(s,"Alice"))
print("PASS: pass-through platform keeps every claim until the tail exits; broken topology fails closed")
