local root="mods/luanttd_core/"
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
local Reverse=stock("rail_reverse",T,M,Motion,Life,Sig,F,P)
local Sim={}
function Sim.id(x,y) if x>=0 and y>=0 and x<32 and y<32 then return x+y*32 end end
function Sim.xy(id) return id%32,math.floor(id/32) end
function Sim.adjacent(id,dir)
  local x,y=Sim.xy(id)
  local dx,dy={0,1,0,-1},{-1,0,1,0}
  return Sim.id(x+dx[dir],y+dy[dir])
end
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,{},C,S)
local R=dofile(root.."rail_dispatch_run.lua")(T,F,C,S,P,Life,Sig,Motion,D,Speed,Lab,nil,Reverse)
local function id(x) return Sim.id(x,5) end
local s={tiles={},topology=0}
for x=2,14 do s.tiles[id(x)]={owner="Alice",rail_tracks=1} end
assert(Lab.depot(s,"Alice",id(2),T.SW))
assert(Lab.station(s,"Alice",id(4),id(6)))
assert(Lab.station(s,"Alice",id(12),id(14)))
local ok,msg=R.start_shuttle(s,"Alice",id(2),2,1)
assert(not ok and not R.current(s),"Unsafe west end must refuse without allocating the first leg")
assert(R.place_signal(s,"Alice",id(3),0,Sig.PBS))
assert(not R.start_shuttle(s,"Alice",id(2),2,2))
assert(R.start(s,"Alice",id(2),2))
assert(not R.start_shuttle(s,"Alice",id(2),2,1))
assert(R.clear(s,"Alice"))
local ok,msg,run=R.start_shuttle(s,"Alice",id(2),2,1);assert(ok,msg)
assert(not R.start(s,"Alice",id(2),2))
assert(not R.start_shuttle(s,"Alice",id(2),2,1))
local function save(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local y={}
  for k,v in pairs(x) do y[k]=save(v) end
  return y
end
local function equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~="table" then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function at_station(pos)
  local board=R.board(s)
  local t=board.tile(pos)
  return t and t.station
end
local function train() return R.current(s).runs[1] end
local arrivals,flips,departed=0,0,0
local last_arrival,last_front,last_back,station_claims,dwell_saved
for i=1,6000 do
  local events=R.tick(s)
  local d=R.current(s)
  run=train()
  assert(not d.failure,d.failure)
  for _,e in ipairs(events) do
    if e.kind=="arrived" then
      arrivals=arrivals+1
      local expected=arrivals%2==1 and 2 or 1
      assert(run.phase=="dwell" and e.station==expected and at_station(e.tile)==expected)
      assert(e.tick+R.SHUTTLE_DWELL_TICKS==run.shuttle.dwell_until)
      assert(Speed.should_stop(run,expected)==false and run.speed==0)
      assert(run.consist.parts[1].pose.x==(expected==2 and 14*16+12 or 4*16+3))
      last_front,last_back=save(run.consist.parts[1].pose),save(run.consist.parts[2].pose)
      station_claims=save(d.life.bits)
      last_arrival=e
      if arrivals==1 then
        local data=save(s)
        assert(equal(data.stock_rail_dispatch,d))
        s=data;d=R.current(s);run=train();dwell_saved=true
      end
    elseif e.kind=="reversed" then
      flips=flips+1
      local expected=flips%2==1
      assert(e.cab_reversed==expected and run.consist.reversed==expected)
      assert(run.phase=="turnaround" and run.speed==0 and run.index==1)
      assert(e.tick-last_arrival.tick==R.SHUTTLE_DWELL_TICKS)
      assert(run.consist.parts[1].pose.x==last_back.x and run.consist.parts[2].pose.x==last_front.x)
      assert(run.consist.parts[1].pose.td==T.reverse_trackdir(last_back.td))
      local emitted_claims=save(d.life.bits)
      -- Each part remains claimed across swap and serialization.
      for j,p in ipairs(run.consist.parts) do
        assert(Life.claim_owner(d.life,p.tile,T.X)==1)
        assert(at_station(p.tile)==last_arrival.station)
        local tile,td,f=R.sample(run,j)
        assert(tile==p.tile and td==p.pose.td and f>=0 and f<=1)
      end
      s=save(s);d=R.current(s);run=train()
      assert(run.consist.reversed==expected and equal(d.life.bits,emitted_claims))
      assert(run.consist.parts[1].pose.x==last_back.x and Life.valid_state(R.board(s),d.life))
    elseif e.kind=="shuttle_departed" then
      departed=departed+1
      assert(e.tick==last_arrival.tick+R.SHUTTLE_DWELL_TICKS+1)
      assert(run.phase=="running")
    end
  end
  if run.phase=="dwell" then
    assert(equal(d.life.bits,station_claims))
    assert(equal(run.consist.parts[1].pose,last_front) and equal(run.consist.parts[2].pose,last_back))
  end
  assert(Motion.check_spacing(R.board(s),run.consist))
  if arrivals==3 then break end
end
assert(dwell_saved and arrivals==3 and flips==2 and departed==2)
assert(train().shuttle.arrivals==3 and train().shuttle.reversals==2)
assert(R.clear(s,"Alice"))
assert(R.signal(s,id(3),0)=="red")
print("PASS: three alternating platform arrivals; two stock reversals, dwell and reversal reload, stable cab state and occupied claims")
