local root="mods/luanttd_core/"
local src=root.."openttd/"
local function port(n,...)return dofile(src..n..".lua")(...)end
local T=dofile(src.."rail_track.lua")
local F=port("rail_follow",T)
local C=port("rail_yapf_cost",T,F)
local Search=port("rail_yapf_search",T,F,C)
local Raw=port("rail_motion",T)
local P=port("rail_reservation",T,F,C)
local L0=port("rail_consist_reservation",T,F,P)
local L=dofile(root.."rail_span_life.lua")(T,P,L0)
local Signal=port("rail_signals",T)
local Consist=port("rail_consist_motion",T,Raw,F,L0)
local Motion=dofile(root.."rail_span_consist.lua")(T,Raw,F,Consist,L0)
local Dispatch=dofile(root.."rail_consist_dispatch.lua")(Motion,L)
local Speed=port("rail_station_speed",T,F)
local Slope=dofile(src.."slope.lua")
local H=port("rail_height",T,Slope)
local Terrain=dofile(src.."terrain.lua")
local Q=port("rail_construction",T,Signal,H)
local Site=dofile(src.."rail_span_site.lua")
local B=port("rail_bridge",port("road_bridge",Slope),Q,Site)
local U=port("rail_tunnel",dofile(src.."road_tunnel.lua"),Q,Site,T)
local Sim={W=32,H=16}
function Sim.id(x,y) if x>=1 and y>=1 and x<=32 and y<=16 then return x+y*64 end end
function Sim.xy(id)return id%64,math.floor(id/64)end
function Sim.adjacent(id,d)
  local x,y=Sim.xy(id)
  local dx,dy={0,1,0,-1},{-1,0,1,0}
  return Sim.id(x+dx[d],y+dy[d])
end
function Sim.company(s,name)
  s.companies[name]=s.companies[name] or {cash=100000,expense=0,month_exp=0}
  return s.companies[name]
end
local s={tiles={},companies={},topology=0,rail_span_enabled=true}
s.corner_grid=Terrain.new(32,16,function(x,z)
  if x>=14 and x<=18 then return 5 end
  if x==7 or x==8 then return 3 end
  return 4
end)
local function terrain(id)
  local x,y=Sim.xy(id)
  return Terrain.tile(s.corner_grid,x,y)
end
for x=1,32 do
  local id=Sim.id(x,10)
  local _,h=terrain(id)
  s.tiles[id]={h=h,terrain="grass",variant=1}
end
local function id(x)return Sim.id(x,10)end
local Lab=dofile(root.."trackworks.lua")(Sim,T,F,Slope,C,Search,terrain)
local W=dofile(root.."rail_span_world.lua")(Sim,Terrain,H,B,U,T,{[0]=true,[2]=true})
local Run=dofile(root.."rail_dispatch_run.lua")(T,F,C,Search,P,L,Signal,Motion,Dispatch,Speed,Lab,nil,nil,W)
local function rail(x)
  local t=s.tiles[id(x)];t.owner="Alice";t.rail_tracks=1;t.build="stock_rail"
end
for _,x in ipairs({2,3,4,10,11,12,19,20,21,22,23,24}) do rail(x) end
assert(Lab.depot(s,"Alice",id(2),T.SW))
assert(Lab.station(s,"Alice",id(22),id(24)))
assert(Lab.station(s,"Alice",id(10),id(11)))
local b=assert(W.quote_bridge(s,"Alice",id(5),id(9)))
assert(b.deck==5 and b.middle_by_tile[id(7)] and b.rail_cost==500)
local ok,msg,dirty= W.commit(s,"Alice",b)
assert(ok,msg);assert(#dirty==5 and W.protected(s,id(7)))
assert(not W.commit(s,"Alice",b),"stale plans must refuse")
local u=assert(W.quote_tunnel(s,"Alice",id(13)))
assert(u["end"]==id(18) and u.head.slope==3 and u.tail.slope==12)
assert(W.commit(s,"Alice",u))
assert(W.protected(s,id(15)) and W.protected(s,id(13)))
assert(s.companies.Alice.cash==100000-b.price-u.price)
local before=s.topology
assert(not Lab.change(s,"Alice",id(7),T.X,false,0))
assert(not Lab.change(s,"Alice",id(15),T.X,false,0))
assert(not Lab.commit_depot(s,"Alice",id(5),T.SW))
assert(not Lab.commit_station(s,"Alice",{id(8),id(9)},T.X))
assert(not Lab.commit_piece(s,"Alice",{id=id(13),tracks=1}))
assert(not Run.place_signal(s,"Alice",id(15),8,Signal.PBS))
assert(s.topology==before and W.by_portal(s,id(13)).kind=="tunnel")
assert(not Run.start(s,"Alice",id(2),1),"opt-in service required")
local ok,msg,run=Run.start_span(s,"Alice",id(2),1)
assert(ok,msg)
assert(not W.clear(s,"Alice",id(5)),"occupied service must protect infrastructure")
assert(not Run.start(s,"Alice",id(2),2))
local function save(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local y={}
  for k,v in pairs(x) do y[k]=save(v) end
  return y
end
local function claims(state,head,tail,expected)
  assert((L.claim_owner(state.life,id(head),T.X) or 0)==expected)
  assert((L.claim_owner(state.life,id(tail),T.X) or 0)==expected)
end
local arrived=false
local ladder={}
local bridge_seen,wagon_hold,tunnel_seen,tunnel_wagon_hold=false,false,false,false
local reloaded_bridge,reloaded_tunnel,bridge_release,tunnel_release=false,false,false,false
for tick=1,4000 do
  local d=Run.current(s)
  local events=Run.tick(s)
  assert(not d.failure,d.failure)
  run=d.runs[1]
  assert(Motion.check_spacing(Run.board(s),run.consist))
  assert(L.valid_state(Run.board(s),d.life))
  local h,v=run.consist.parts[1],run.consist.parts[2]
  if h.tile==id(5) and (not h.wormhole or h.draw_tile==id(5)) then
    local f=h.pose.x%16
    assert(h.z==4*8+math.floor((f+1)/2))
    if h.span_prepared then assert(f==15 and h.z==40) end
    ladder[f]=true
  elseif h.tile==id(9) then
    assert(h.z==4*8+math.floor((16-h.pose.x%16)/2))
  end
  for _,e in ipairs(events) do
    if e.kind=="span_released" and e.tile==id(9) then
      claims(d,5,9,0);assert(wagon_hold and not v.wormhole)
      bridge_release=true
    elseif e.kind=="span_released" and e.tile==id(18) then
      claims(d,13,18,0);assert(tunnel_wagon_hold)
      tunnel_release=true
    elseif e.kind=="tunnel_hidden" then
      assert(e.tile==id(13))
      assert(run.consist.parts[e.index].pose.x%16==8)
    elseif e.kind=="tunnel_revealed" then
      assert(e.tile==id(18))
      assert(run.consist.parts[e.index].pose.x%16==4)
    elseif e.kind=="arrived" then
      assert(e.station==1 and h.tile==id(24))
      arrived=true
    end
  end
  if h.wormhole and h.draw_tile==id(7) then
    assert(h.tile==id(5) and h.z==b.deck*8 and h.hidden~=true and run.speed<=64)
    local draw,td,f=Run.sample(run,1)
    assert(draw==id(7) and W.presentation(s,draw,td,f,h)==b.deck)
    bridge_seen=true
    if not reloaded_bridge then
      claims(d,5,9,1)
      local span_key=s.tiles[id(5)].rail_span_id
      local old_span=W.by_portal(s,id(5))
      local next_span=s.next_stock_rail_span
      local money=s.companies.Alice.cash
      local q=assert(W.quote_bridge(s,"Alice",id(9),id(5),0,nil,2))
      local good,note,changed,_,live=W.commit(s,"Alice",q)
      assert(good,note)
      assert(#changed==5 and live==old_span and s.tiles[id(5)].rail_span_id==span_key)
      assert(s.rail_bridge_above[id(7)]==span_key and s.next_stock_rail_span==next_span)
      assert(s.companies.Alice.cash==money-q.price and live.bridge_type==2)
      assert(Motion.max_bridge_speed(Run.board(s),run.consist)==64)
      claims(d,5,9,1)
      s=save(s);reloaded_bridge=true
    end
  end
  if h.tile==id(10) and v.tile==id(9) then
    claims(d,5,9,1);wagon_hold=true
  end
  if h.wormhole and v.wormhole and h.tile==id(13) and v.tile==id(13) then
    assert(h.hidden and v.hidden and h.z==u.base*8 and v.z==h.z)
    assert(Run.sample(run,1)==nil and Run.sample(run,2)==nil)
    for i=1,2 do
      local draw,td,f,interior=Run.bore_sample(run,i)
      assert(draw and interior and W.presentation(s,draw,td,f,{wormhole=true})==u.base)
    end
    claims(d,13,18,1)
    tunnel_seen=true
    if not reloaded_tunnel then s=save(s);reloaded_tunnel=true end
  end
  if h.tile==id(19) and v.tile==id(18) then
    claims(d,13,18,1);tunnel_wagon_hold=true
  end
  if arrived then break end
end
assert(bridge_seen and bridge_release and wagon_hold and tunnel_seen and tunnel_release and tunnel_wagon_hold and arrived)
assert(reloaded_bridge and reloaded_tunnel)
for frame=0,15 do assert(ladder[frame],"Missing stock bridge frame "..frame) end
assert(Run.clear(s,"Alice"))
assert(W.clear(s,"Alice",id(13)) and W.clear(s,"Alice",id(5)))
assert(not W.protected(s,id(7)) and s.tiles[id(13)].h==4)
print("PASS: built native-board rail spans via quotes, live grade upgrade and tunnel movement held both claims until actual tail, stock frames/speed and two reloads")
