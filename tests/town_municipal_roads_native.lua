-- A fresh owner runs the actual stock tick, projects public roads, and
-- reopens the written geometry. There is no company build command.
if not core.get_player_by_name then return end
for _,alias in ipairs({"mapgen_stone","mapgen_water_source","mapgen_river_water_source"}) do
  core.register_alias(alias,"air")
end
local m=core.get_modpath(core.get_current_modname())
local function load_(name) return dofile(m.."/"..name..".lua") end
local S,T,G=load_("sim"),load_("openttd/terrain"),load_("openttd/town_growth")
S.W,S.H=64,64
local s=S.new(1751)
s.corner_grid=T.new(64,64,function() return 1 end)
s.stock_generated_profile={width=64,depth=64,map_height_limit=30}
S.mount_road_bus_market(s,load_("openttd/stock_engine_calendar"),1950)
s.speed,s.day=1,4
s.passenger_house_clock=load_("openttd/town_passengers").new_clock(6,6,nil,4*74)
s.stock_town_growth={version=1,order={1},towns={}}
local mode=core.settings:get("luanttd_qa_municipal_kind") or "road"
local span=mode=="bridge" or mode=="tunnel"
local reseed=mode=="reseed"
local crossing=mode=="crossing"
local foreignhouse=mode=="foreignhouse"
local woodhouse=mode=="woodhouse" or foreignhouse
if span then s.passenger_rating_rng={3,3} end -- exercise the stock two-word RNG
local cx,cz=span and 13 or 11,span and 17 or 12
local center,protected=S.id(cx,cz),S.id(cx,cz+(woodhouse and 3 or 1))
local target=not span and "road" or "stock_road_"..mode
s.sites={{id=1,kind="town",name="Grid Town",tile=center,population=0,stock={},produced={},received={}}}
local rail_cell=S.id(cx+1,cz)
local town=G.new(1,cx,cz,{layout="grid2",grow_counter=0})
town.growing,town.growth_rate=true,(reseed or woodhouse) and 15000 or 0
s.stock_town_growth.towns[1]=town
for id in ipairs(s.tiles) do s.tiles[id]={h=1,terrain="grass",variant=1} end
local wooded=S.id(cx-1,cz)
if reseed then
  s.corner_grid.levels[(cz-1)*65+cx+1]=2
  assert(T.tile(s.corner_grid,cx,cz)~=0 and T.tile(s.corner_grid,cx-1,cz)==0)
  s.tiles[wooded].wood=1
else
  if foreignhouse then
    local nx,nz=cx+8,cz+8
    local other=G.new(2,nx,nz,{layout="original"})
    other.growing=false
    s.stock_town_growth.order[2],s.stock_town_growth.towns[2]=2,other
    s.sites[2]={id=2,kind="town",name="Neighbor",tile=S.id(nx,nz),population=0,stock={},produced={},received={}}
  end
  assert(S.town_road_piece(s,foreignhouse and 2 or 1,center,10,true))
  if woodhouse then for _,dz in ipairs{-1,1} do s.tiles[S.id(cx,cz+dz)].wood=1 end end
end
s.tiles[protected].stock_industry={id=77}
local rail_cash
if crossing then
  local company=S.company(s,"Rail Builder")
  rail_cash=company.cash
  local t=s.tiles[rail_cell]
  t.build,t.rail_tracks,t.owner,t.rail_type="stock_rail",2,"Rail Builder",0
  -- Prevent another new street from ending the first growth attempt.
  s.tiles[S.id(cx-1,cz)].stock_industry={id=78}
  s.tiles[S.id(cx,cz-1)].stock_industry={id=79}
end
if mode=="bridge" then
  for x=cx+2,cx+3 do
    local t=s.tiles[S.id(x,cz)];t.terrain,t.water_class="water","river"
  end
elseif mode=="tunnel" then
  for z=cz,cz+1 do for x=cx+2,cx+4 do s.corner_grid.levels[(z-1)*65+x]=2 end end
  assert(S.town_road_piece(s,1,S.id(cx+2,cz),5,true))
end
local file="municipal-roads.chk"
local disk=load_("campaign_checkpoint")(core,load_("packed_campaign"),file)
disk.write_state(s)
local client=load_("campaign_authority_client")(core,m)
local cap={autoplay=true,seconds_per_day=.15,road={start_year=1950,breakdowns=0,service_interval=0},oil_tanker=true}
if woodhouse then cap.road_town_policy={allow_town_roads=false} end
local view={{x=1,z=1,w=32,h=32}}
local newroad,polls,closing=nil,0,false
local function ask()
  assert(client.query({kind="snapshots",windows=view},function(r)
    polls=polls+1
    assert(r.ok and r.value[1].tiles)
    local junction,guard
    for _,row in ipairs(r.value[1].tiles) do
      if row.id==center then junction=row.surface end
      if row.id==protected then guard=row.surface end
      if crossing then
        if row.id==rail_cell and row.surface.level_crossing then newroad=row.id end
      elseif woodhouse then
        if row.surface.source_house and row.surface.source_house.root then newroad=row.id end
      elseif row.id~=center and row.surface.build==target and row.surface.road_town==1 then newroad=row.id end
    end
    assert(guard and guard.stock_industry.id==77 and not guard.build)
    if reseed then
      assert(not junction or not junction.build)
      if newroad then assert(newroad==wooded) end
    else
      assert(junction and junction.build=="road" and junction.road_town==(foreignhouse and 2 or 1))
    end
    if newroad then
      assert(r.actor_tick>=s.passenger_house_clock.counter)
      closing=true
      assert(client.query({kind="stop"},function() error("Unexpected early stop receipt") end))
    else assert(polls<100,"Town never expanded its public road");core.after(.05,ask) end
  end))
end
core.register_on_mods_loaded(function()
  assert(client.start(cap,function(r)
    assert(r.ready and r.day==4);ask()
  end,function(why,_,day,detail)
    assert(why=="stopped" and closing,detail or why)
    local next_=assert(disk.read())
    assert(next_.day==day and next_.passenger_house_clock.counter==day*74)
    local created=assert(next_.tiles[newroad])
    if woodhouse then
      assert(newroad==S.id(cx,cz-1) or newroad==S.id(cx,cz+1))
      assert(not created.wood and created.house and created.source_house.town==1 and not created.owner)
      assert(next_.tiles[center].road_town==(foreignhouse and 2 or 1) and next_.tiles[center].road_bits==10)
      assert(next_.tiles[newroad==S.id(cx,cz-1) and S.id(cx,cz+1) or S.id(cx,cz-1)].wood)
    else
      assert(created.build==target and created.road_town==1 and (not created.owner or created.owner=="town"))
    end
    if crossing then
      assert(newroad==rail_cell and created.level_crossing)
      local c=created.level_crossing
      assert(c.rail_owner=="Rail Builder" and c.rail_axis==1 and c.road_axis==0 and c.town==1)
      assert(next_.companies["Rail Builder"].cash==rail_cash and not next_.companies.town)
    end
    if span then
      local _,book=next(next_["stock_road_"..mode.."s"])
      assert(book.town==1 and #book.middle>=1)
      for _,id in ipairs(book.middle) do
        if mode=="bridge" then assert(next_.tiles[id].water_class=="river")
        elseif id==S.id(cx+2,cz) then assert(next_.tiles[id].build=="road") end
      end
      local F=load_("openttd/yapf_road_follow")
      local road=load_("road_yapf_board")(S,next_,F)
      for _,id in ipairs({book.start,book["end"]}) do
        local a=road.tile(id)
        local r=F.follow(road,{owner="Carrier"},id,F.direction_trackdir(a.dir))
        assert(r.ok and r[mode] and r.tile==a.other)
      end
    elseif not woodhouse then assert(created.road_bits>0) end
    assert((crossing or not next(next_.companies)) and next_.tiles[protected].stock_industry.id==77)
    if reseed then
      assert(not created.wood and not next_.tiles[center].build)
    elseif not span and not woodhouse and not crossing then assert(next_.tiles[center].road_bits~=10) end
    cap.autoplay=false
    assert(client.start(cap,function(ready)
      assert(ready.ready and ready.day==day)
      assert(client.query({kind="snapshots",windows=view},function(r)
        local found=false
        for _,row in ipairs(r.value[1].tiles) do
          if row.id==newroad then
            if crossing then assert(row.surface.level_crossing.rail_owner=="Rail Builder" and row.surface.road_town==1)
            elseif woodhouse then assert(row.surface.source_house.id==created.source_house.id and not row.surface.wood)
            else assert(row.surface.road_bits==created.road_bits and row.surface.road_town==1) end
            found=true
          end
        end
        assert(found)
        assert(client.query({kind="stop"},function() error("Unexpected reopen receipt") end))
      end))
    end,function(reason)
      assert(reason=="stopped")
      core.log("action",("PASS NATIVE MUNICIPAL ROADS: real stock owner grew and displayed public %s tile %d, preserved private clearance, reopened geometry"):format(woodhouse and "house on former woodland at" or mode,newroad))
      core.request_shutdown("Native municipal road proof passed",false,0)
    end,file))
  end,file))
end)
