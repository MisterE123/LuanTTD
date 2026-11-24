local root="mods/luanttd_core/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local Bridge=dofile(root.."openttd/road_bridge.lua")(dofile(root.."openttd/slope.lua"))
local Construction=dofile(root.."openttd/tram_construction.lua")(
  dofile(root.."openttd/road_slope.lua"),Bridge.roadtypes)
local Span=dofile(root.."tram_span_layers.lua")(Sim,Terrain,Construction,Bridge)
local function check(kind,along_y)
  local s=Sim.new(1751)
  for _,t in ipairs(s.tiles) do
    t.terrain,t.h,t.wood,t.house,t.site,t.build,t.owner="grass",0,nil,nil,nil,nil,nil
  end
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z)
    local n=along_y and z or x
    return kind=="tunnel" and n>=24 and n<=27 and 1 or 0
  end)
  local function at(n) return along_y and Sim.id(12,n) or Sim.id(n,12) end
  local a,b=at(23),at(27)
  local Road,Tram,Visitor="Road owner","Tram owner","Visitor"
  local c=Sim.company(s,Tram)
  Sim.company(s,Visitor)
  if kind=="bridge" then assert(Sim.road_bridge(s,Road,a,b,0))
  else assert(Sim.road_tunnel(s,Road,a)) end
  local t=assert(Span.get(s,a))
  local u=assert(Span.get(s,b))
  assert(t.dir==(along_y and 1 or 2) and t.outer==(along_y and 1 or 8))
  assert(u.dir==(along_y and 3 or 0) and u.outer==(along_y and 4 or 2))
  assert(t.other==b and u.other==a and t.plan==u.plan and t.skip==3)
  assert(t.roadtype==0 and t.owner==Road and t.tramtype==nil)
  assert(not Span.get(s,at(25)))
  local occupied=false
  local function busy(a0,b0,p)
    assert((a0==a and b0==b or a0==b and b0==a) and p==t.plan)
    return occupied
  end
  local cash,revision=c.cash,s.topology
  local function reject(player,id,bits,op,expect)
    local q,reason=Span.quote(s,player,id,bits,op,busy)
    assert(q==nil and reason==expect,tostring(reason))
  end
  reject(Tram,a,t.axis,"lay","OUTSIDE_PORTAL_BIT_REQUIRED")
  reject(Tram,a,t.outer,"remove","NO_TRAMWAY")
  occupied=true
  reject(Tram,b,u.outer,"lay","VEHICLE_IN_THE_WAY")
  occupied=false
  local q=assert(Span.quote(s,Tram,b,u.outer,"lay",busy))
  assert(q.cost==1900 and c.cash==cash and s.topology==revision)
  occupied=true
  local ids,why=Span.apply(s,Tram,q,busy)
  assert(not ids and why=="VEHICLE_IN_THE_WAY")
  occupied=false
  ids=assert(Span.apply(s,Tram,q,busy))
  assert(#ids==(kind=="bridge" and 5 or 2) and ids[1]==b and ids[2]==a)
  assert(s.topology==revision+1 and c.cash==cash-1900 and c.expense==1900)
  assert(Span.get(s,a).tram_owner==Tram and Span.get(s,b).tramtype==1)
  assert(t.plan.road_owner==Road and s.tiles[at(25)].tram==nil)
  assert(not Span.apply(s,Tram,q,busy))
  reject(Tram,a,t.outer,"lay","ALREADY_BUILT")
  reject(Visitor,a,t.outer,"remove","OWNED_BY_ANOTHER")
  reject(Tram,a,along_y and 2 or 1,"remove","NO_TRAMWAY")

  -- RemoveLongRoad permits either half along the axis. Selling this
  -- material refunds $102 per bit and does not delete the shared span.
  local r=assert(Span.quote(s,Tram,a,u.outer,"remove",busy))
  assert(r.cost==-1020)
  occupied=true
  ids,why=Span.apply(s,Tram,r,busy)
  assert(not ids and why=="VEHICLE_IN_THE_WAY")
  occupied=false
  t.plan.owner=Tram
  s.tiles[a].owner,s.tiles[b].owner=Tram,Tram
  assert(Span.apply(s,Tram,r,busy))
  assert(Span.get(s,a).tramtype==nil and Span.get(s,b).tramtype==nil)
  assert(Span.get(s,b).owner==Road and s.tiles[a].owner==Road and s.tiles[b].owner==Road)
  assert(c.cash==cash-880 and c.expense==880 and c.month_exp==880)
  if kind=="bridge" then assert(s.bridge_above[at(25)]==t.key)
  else assert(s.tunnel_below[at(25)]==t.key) end
end
for _,kind in ipairs({"bridge","tunnel"}) do
  check(kind,false)
  check(kind,true)
end
print("PASS: both axes and endpoint directions; paired stock tram price/refund, occupancy recheck, split ownership and intact underlying tiles")

local U=root.."openttd/"
local F=dofile(U.."yapf_road_follow.lua")
local Cost=dofile(U.."yapf_road_cost.lua")(F)
local Search=dofile(U.."yapf_road_search.lua")(F,Cost)
local RoadMotion=dofile(U.."road_motion.lua")(dofile(U.."road_motion_data.lua"))
local Motion=dofile(U.."tram_motion.lua")(dofile(U.."tram_motion_data.lua"),RoadMotion)
local Wormhole=dofile(root.."road_bridge_motion.lua")
local Trip=dofile(root.."tram_trip.lua")(F,Cost,Search,Motion,Wormhole)
local function movement(kind,along_y)
  local s=Sim.new(1751)
  for _,t in ipairs(s.tiles) do
    t.terrain,t.h,t.wood,t.house,t.site,t.build,t.owner="grass",0,nil,nil,nil,nil,nil
  end
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z)
    local n=along_y and z or x
    return kind=="tunnel" and n>=24 and n<=27 and 1 or 0
  end)
  local function at(n) return along_y and Sim.id(12,n) or Sim.id(n,12) end
  local a,b=at(23),at(27)
  local owner="Company"
  if kind=="bridge" then assert(Sim.road_bridge(s,owner,a,b,0))
  else assert(Sim.road_tunnel(s,owner,a)) end
  local t=assert(Span.get(s,a))
  local function free() return false end
  assert(Span.apply(s,owner,assert(Span.quote(s,owner,a,t.outer,"lay",free)),free))
  local dir=t.dir
  local depots={
    [at(22)]={kind="depot",dir=dir,owner=owner,tramtype=1,base=0},
    [at(28)]={kind="depot",dir=(dir+2)%4,owner=owner,tramtype=1,base=0}}
  local board={
    xy=Sim.xy,tile_at=Sim.id,adjacent=function(id,d) return Sim.adjacent(id,4-d) end,
    tile=function(id) return depots[id] or Span.get(s,id) end,
    center_z=function() return 0 end,
  }
  function board.edge_available(id,other,d)
    assert(board.adjacent(id,d)==other, "span was treated as an ordinary tile edge")
    return board.tile(id)~=nil and board.tile(other)~=nil
  end
  function board.surface(id) return board.tile(id)~=nil end
  function board.tram_bits(id,inside) return Construction.effective_bits(board.tile(id),inside) end
  local v={owner=owner,tramtype=1,cargo="passenger"}
  for _,n in ipairs({22,28}) do
    for side=0,1 do
      local route,td,_,frames,trace=Trip.route(board,at(n),at(50-n),v,{road_side=side})
      assert(route,tostring(td))
      assert(#route==4 and #trace==4 and route[2]==(n==22 and a or b))
      local inside={}
      for i,f in ipairs(frames) do
        local p=frames[i-1]
        if p then assert(math.abs(p[1]-f[1])<=1 and math.abs(p[2]-f[2])<=1) end
        if f[4]==at(24) or f[4]==at(25) or f[4]==at(26) then
          inside[f[4]]=(inside[f[4]] or 0)+1
          assert(f[12] and f[6]==Wormhole.WORMHOLE)
          if kind=="bridge" then assert(f[10]==t.key and f[11]==t.bridge_speed*2 and not f[13])
          else assert(not f[10] and f[13] and f[14]==t.key) end
        end
      end
      assert(inside[at(24)]==16 and inside[at(25)]==16 and inside[at(26)]==16)
      assert(frames[#frames][4]==at(50-n))
      local old=trace[3].tile
      trace[3].tile=trace[2].tile
      assert(not Trip.compile(board,trace,v,{road_side=side}))
      trace[3].tile=old
    end
  end
end
for _,kind in ipairs({"bridge","tunnel"}) do movement(kind,false);movement(kind,true) end
print("PASS: vehicle follows the real paired span with the stock wormhole frame, both directions, both axes and both driving sides")

local Runtime=dofile(root.."campaign_authority_runtime.lua")
local API=dofile(root.."campaign_authority_endpoint.lua")
local Pack=dofile(root.."packed_campaign.lua")
local owner="Elevated company"
local function authoritative(kind)
  local s=Sim.new(1751)
  for _,tile in ipairs(s.tiles) do
    tile.terrain,tile.h,tile.wood,tile.house,tile.site,tile.build,tile.owner="grass",0,nil,nil,nil,nil,nil
  end
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x)
    return kind=="tunnel" and x>=24 and x<=27 and 1 or 0
  end)
  s.tram_enabled,s.road_stock_clock,s.road_stock_loading,s.road_economy=true,true,true,true
  local cap={road={start_year=1950,breakdowns=0,service_interval=150},seconds_per_day=1.25}
  local r=Runtime(Sim,"mods/luanttd_core",s,cap)
  local a=API(Sim,r)
  local function at(x,z) return Sim.id(x,z or 12) end
  local first,last=at(23),at(27)
  if kind=="bridge" then assert(Sim.road_bridge(s,owner,first,last,0))
  else assert(Sim.road_tunnel(s,owner,first)) end
  local c=Sim.company(s,owner)
  local cash=c.cash
  local req={tool="tram_lay",axis=0,first=first,start_half=true,end_half=true}
  assert(not a.road_place(owner,req).ok and c.cash==cash,"inside half must not be accepted")
  req.start_half,req.end_half=false,false
  local q=assert(a.road_quote(owner,req).value)
  assert(q.cost==1900 and #q.tiles==(kind=="bridge" and 5 or 2))
  local h=assert(a.road_place(owner,req,q))
  assert(h.ok,h.why or h.note)
  assert(c.cash==cash-1900)
  local projected=a.snapshot(25,12,1,1).value
  local index=kind=="bridge" and "stock_road_bridges" or "stock_road_tunnels"
  assert(projected.registries[index][1].tramtype==1 and projected.registries[index][1].tram_owner==owner)
  assert(projected.tiles[1].id==at(25) and projected.tiles[1].tram==nil)

  local depot,a1,a2=at(20,11),at(21),at(29)
  local n=r.tram.net
  assert(n.construct(s,owner,"depot",{depot},F.SE))
  assert(n.construct(s,owner,"road",Sim.line(at(19),at(22))))
  assert(n.construct(s,owner,"road",{at(22)},2)) -- exterior approach to first ramp
  assert(n.construct(s,owner,"road",Sim.line(at(28),at(31))))
  assert(n.construct(s,owner,"road",{at(28)},8))
  assert(n.construct(s,owner,"road",{at(20)},1))
  assert(n.construct(s,owner,"drive_stop",{a1},0))
  assert(n.construct(s,owner,"drive_stop",{a2},0))
  local pilot=assert(r.tram.run.start(s,owner,depot,a1,a2))
  local function options()
    return assert(a.demolition(owner,kind=="bridge" and at(25) or first).value)
  end
  local function choice(quote)
    for _,o in ipairs(quote.options) do if o.key=="tram_span" then return o end end
  end
  assert(not assert(choice(options())).ok,"the live scheduled route protects the shared wire")
  if kind=="bridge" then assert(not Sim.remove_wood_bridge(s,owner,first))
  else assert(not Sim.remove_road_tunnel(s,owner,first)) end
  local seen={}
  for _,leg in ipairs(pilot.legs) do
    for _,f in ipairs(leg.frames) do
      if f[4]==at(25) then
        seen[f[3]]=true
        local pos,_,_,inside=r.tram.pose(f)
        assert(pos and pos.y==(kind=="bridge" and 1.52 or .52) and (kind~="tunnel" or inside))
      end
    end
  end
  assert(seen[1] and seen[5])
  for _=1,40 do
    assert(a.advance(1).ok)
    if pilot.arrivals>=3 then break end
  end
  assert(pilot.arrivals>=3)
  s=assert(Pack.decode(Pack.encode(s)))
  r=Runtime(Sim,"mods/luanttd_core",s,cap); a=API(Sim,r)
  assert(r.tram.run.current(s).arrivals>=3 and not assert(choice(options())).ok)
  assert(r.tram.run.clear(s,owner))
  local d=options()
  local match=assert(choice(d))
  assert(match.ok and match.detail=="Refund: $1020")
  local removal=a.command(owner,{kind="demolition",layer="tram_span",token=d.token,
    revision=s.authority_revision or 0})
  assert(removal.ok,removal.why)
  assert(s[index][1].tramtype==nil and s[index][1].roadtype==0)
  assert(s.tiles[at(25)].build==nil and s.tiles[at(25)].tram==nil)
end
authoritative("bridge")
authoritative("tunnel")
print("PASS: ordinary outside-half command, projected layer, complete repeated span visits after dispatch, SQLite codec reload and layer-only refund")
