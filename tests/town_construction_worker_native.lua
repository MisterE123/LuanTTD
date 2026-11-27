-- Native owner builds a house, checkpoints while unfinished, then
-- resumes the same construction clock and population change.
for _,alias in ipairs{"mapgen_stone","mapgen_water_source","mapgen_river_water_source"} do core.register_alias(alias,"air") end
local mod=core.get_modpath(core.get_current_modname())
local function load_(n) return dofile(mod.."/"..n..".lua") end
local S,T,G,H=load_("sim"),load_("openttd/terrain"),load_("openttd/town_growth"),load_("openttd/town_passengers")
S.W,S.H=64,64
local s=S.new(1751)
s.corner_grid=T.new(S.W,S.H,function()return 1 end)
s.stock_generated_profile={version=1,width=S.W,depth=S.H,map_height_limit=30}
S.mount_road_bus_market(s,load_("openttd/stock_engine_calendar"),1950)
s.day=4
s.passenger_house_clock=H.new_clock(6,6,nil,4*74)
local x,z=11,12
local center=S.id(x,z)
local town=G.new(1,x,z,{layout="grid2",grow_counter=0,growing=true,growth_rate=15000})
s.sites={{id=1,kind="town",name="Construction Test",tile=center,population=0,stock={},produced={},received={}}}
s.stock_town_growth={version=1,order={1},towns={[1]=town}}
for id in ipairs(s.tiles) do s.tiles[id]={h=1,terrain="grass",variant=1} end
assert(S.town_road_piece(s,1,center,10,true))
for _,dz in ipairs{-1,1} do s.tiles[S.id(x,z+dz)].wood=1 end
local file="town-construction.chk"
local disk=load_("campaign_checkpoint")(core,load_("packed_campaign"),file)
disk.write_state(s)
local client=load_("campaign_authority_client")(core,mod)
local caps={autoplay=false,road={start_year=1950,breakdowns=0,service_interval=0},
  road_town_policy={allow_town_roads=false},oil_tanker=true}
local target,before,mid,finished
local function ask(request,fn)
  assert(client.query(request,function(r) assert(r.ok,r.why);fn(r) end))
end
local function stop()
  assert(client.query({kind="stop"},function() error("Stop should acknowledge after writing the checkpoint") end))
end
local function drive(phase,left)
  assert(left>0,"Native house did not reach its construction stage")
  ask({kind="advance",days=4},function()
    ask({kind="snapshots",windows={{x=9,z=9,w=8,h=8}}},function(r)
      local h
      for _,row in ipairs(r.value[1].tiles) do
        if row.surface.source_house and row.surface.source_house.root and (not target or target==row.id) then
          target,h=row.id,row.surface.source_house;break
        end
      end
      if h then
        if phase=="first" and h.stage==1 then
          assert(not h.completed and h.counter>=0 and h.counter<8 and not h.first_cargo_tick)
          mid=h;stop();return
        elseif phase=="second" then
          assert(h.built_tick==mid.built_tick and h.id==mid.id and h.stage>=mid.stage)
          if h.completed then
            assert(h.stage==3 and h.counter==0)
            local duration=h.completed_tick-h.built_tick
            assert(duration>=23*256 and duration<=24*256,duration)
            assert(not h.first_cargo_tick or h.first_cargo_tick>h.completed_tick)
            finished=h;stop();return
          end
        end
      end
      drive(phase,left-1)
    end)
  end)
end
core.register_on_mods_loaded(function()
  assert(client.start(caps,function(ready)
    assert(ready.ready and ready.day==4)
    drive("first",12)
  end,function(reason,_,day,detail)
    assert(reason=="stopped",detail or reason)
    before=assert(disk.read())
    local stored=before.tiles[target].source_house
    assert(stored.stage==mid.stage and stored.counter==mid.counter and stored.built_tick==mid.built_tick)
    assert(before.stock_town_growth.towns[1].population==0)
    assert(client.start(caps,function(r)
      assert(r.ready and r.day==day)
      drive("second",22)
    end,function(final_reason,_,_,error_)
      assert(final_reason=="stopped",error_ or final_reason)
      local after=assert(disk.read())
      local h=after.tiles[target].source_house
      assert(h.completed_tick==finished.completed_tick and h.built_tick==mid.built_tick)
      assert(after.stock_town_growth.towns[1].population==H.specs[h.id][1])
      core.log("action",("PASS NATIVE MUNICIPAL ROADS: house saved at stage %d, counter %d; completed after %d ticks, with population credited once"):format(mid.stage,mid.counter,h.completed_tick-h.built_tick))
      core.request_shutdown("Native house construction parity passed",false,0)
    end,file))
  end,file))
end)
