-- Normal TileLoop_Town in a real worker: an old house above a road
-- tunnel renews and a protected house sharing the bore stays put.
for _,alias in ipairs{"mapgen_stone","mapgen_water_source","mapgen_river_water_source"} do core.register_alias(alias,"air") end
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
local S,T,G,H=m("sim"),m("openttd/terrain"),m("openttd/town_growth"),m("openttd/town_passengers")
local kind=core.settings:get("luanttd_qa_municipal_kind")
local replacement,manual=kind=="renewbore-replace",kind=="renewbore-manual"
S.W,S.H=64,64
local s=S.new(1751)
local x,z=11,12
local start,finish,old,protected=S.id(x-4,z),S.id(x+4,z),S.id(x,z),S.id(x+1,z)
s.corner_grid=T.new(S.W,S.H,function(u) return u>=x-3 and u<=x+4 and 2 or 1 end)
s.stock_generated_profile={version=1,width=S.W,depth=S.H,map_height_limit=30}
S.mount_road_bus_market(s,m("openttd/stock_engine_calendar"),1950)
s.day=4
s.passenger_house_clock=H.new_clock(6,6,nil,4*74)
s.passenger_rating_rng=replacement and {4,3} or {800043008,3063445365}
for id in ipairs(s.tiles) do s.tiles[id]={h=1,terrain="grass",variant=1} end
local ok,why=S.road_tunnel(s,"Span Builder",start,false)
assert(ok,why)
local level=assert(s.tunnel_below[old])
assert(s.tunnel_below[protected]==level and s.stock_road_tunnels[level]["end"]==finish)
local cash=S.company(s,"Span Builder").cash
local pop=H.specs[0][1]
local town=G.new(1,x,z,{layout="original",population=2*pop,num_houses=2,growing=true,
  grow_counter=15000,growth_rate=15000})
town.time_until_rebuild=1
town.house_counts={[0]=2}
s.sites={{id=1,kind="town",name="Renewal Test",tile=old,population=2*pop,stock={},produced={},received={}}}
s.stock_town_growth={version=1,order={1},towns={[1]=town}}
for _,id in ipairs({old,protected}) do
  local a,b=S.xy(id)
  local t=s.tiles[id]
  t.h,t.terrain,t.house=2,"hill",true
  t.source_house={id=0,x=a,z=b,root=true,root_x=a,root_z=b,town=1,completed=true,stage=3,counter=0,
    age=90,random_bits=65,built_tick=0,player_protected=id==protected or nil}
end
local buyer="Town House Buyer"
local budget
if manual then budget=S.company(s,buyer).cash end
local file="town-renew-bore.chk"
local disk=m("campaign_checkpoint")(core,m("packed_campaign"),file)
disk.write_state(s)
local client=m("campaign_authority_client")(core,mod)
local cap={autoplay=false,road={start_year=1950,breakdowns=0,service_interval=0},oil_tanker=true}
local function ask(req,fn)
  assert(client.query(req,function(r) assert(r.ok,r.why);fn(r) end))
end
local released
local function manual_work()
  local function option(r,key)
    for _,row in ipairs(r.value.options) do if row.key==key then return row end end
  end
  ask({kind="demolition",player=buyer,tile=protected},function(r)
    local locked=assert(option(r,"surface_house"))
    assert(not locked.ok and locked.detail:find("protected",1,true), tostring(locked.ok)..": "..locked.detail)
    ask({kind="demolition",player=buyer,tile=old},function(q)
      local surface=assert(option(q,"surface_house"))
      assert(surface.ok and surface.detail:find("$937",1,true))
      assert(not option(q,"road_tunnel") or not option(q,"road_tunnel").ok)
      ask({kind="command",player=buyer,command={kind="demolition",token=q.value.token,
        layer="surface_house",revision=q.revision}},function(a)
        assert(#a.value==1 and a.value[1]==old,"Only the occupied surface lot may be erased")
        released=true
        assert(client.query({kind="stop"},function()error("Expected a durable stop frame")end))
      end)
    end)
  end)
end
local function work(left)
  assert(left>0,"Town never renewed the aged house above the bore")
  ask({kind="advance",days=1},function()
    ask({kind="snapshots",windows={{x=8,z=9,w=8,h=8}}},function(r)
      local changed
      for _,row in ipairs(r.value[1].tiles) do
        local h=row.surface.source_house
        if row.id==old then changed=not h or (h.built_tick or 0)>0 end
        if row.id==protected then assert(h and h.id==0 and h.player_protected and h.completed) end
      end
      if changed then
        released=true
        assert(client.query({kind="stop"},function()error("Expected a durable stop frame")end))
      else work(left-1) end
    end)
  end)
end
core.register_on_mods_loaded(function()
  assert(client.start(cap,function(r) assert(r.ready);if manual then manual_work() else work(18) end end,function(reason,_,day,detail)
    assert(reason=="stopped" and released,detail or reason)
    local copied=assert(disk.read())
    assert(copied.day==day and copied.tunnel_below[old]==level and copied.tunnel_below[protected]==level)
    local run=assert(copied.stock_road_tunnels[level])
    assert(run.owner=="Span Builder" and run.start==start and run["end"]==finish and run.base==1)
    assert(copied.companies["Span Builder"].cash==cash)
    assert(copied.tiles[protected].source_house.player_protected)
    local h=copied.tiles[old].source_house
    if replacement then assert(h and h.id==6 and h.built_tick==375 and not h.completed)
    else assert(not h) end
    if manual then
      local c=assert(copied.companies[buyer])
      assert(c.cash==budget-937 and c.stock_town_authority_ratings[1]==360)
      assert(copied.stock_town_growth.towns[1].num_houses==1 and copied.sites[1].population==pop)
    end
    local F=m("openttd/yapf_road_follow")
    local road=m("road_yapf_board")(S,copied,F)
    for _,at in ipairs({run.start,run["end"]}) do
      local a=road.tile(at)
      local followed=F.follow(road,{owner="Carrier"},at,F.direction_trackdir(a.dir))
      assert(followed.ok and followed.tunnel and followed.tile==a.other)
    end
    core.log("action","PASS NATIVE MUNICIPAL ROADS: "..(manual and "player demolished upper office only" or replacement and "replaced old office with Town Houses" or "cleared old office")..
      " above owned bore; protected house and route survived")
    core.request_shutdown("Town renewal verified",false,0)
  end,file))
end)
