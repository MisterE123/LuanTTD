-- Native stock campaign: no transport or route injection. The ordinary
-- company action can temporarily grow a town even on the None setting.
if not core.get_player_by_name then return end
for _,id in ipairs{"mapgen_stone","mapgen_water_source","mapgen_river_water_source"} do core.register_alias(id,"air") end
local m=core.get_modpath(core.get_current_modname())
local function load_(name) return dofile(m.."/"..name..".lua") end
local S,T,G=load_("sim"),load_("openttd/terrain"),load_("openttd/town_growth")
S.W,S.H=64,64
local s=S.new(4231)
local owner,file="Builder","municipal-roads.chk"
s.corner_grid=T.new(64,64,function() return 1 end)
s.stock_generated_profile={width=64,depth=64,map_height_limit=30,town_settings={growth_setting=0}}
S.mount_road_bus_market(s,load_("openttd/stock_engine_calendar"),1950)
s.day=10
s.passenger_house_clock=load_("openttd/town_passengers").new_clock(6,6,nil,s.day*74)
s.sites={{id=1,kind="town",name="Glenbrook",tile=S.id(18,20),population=0,stock={},produced={},received={}}}
s.stock_town_growth={version=1,order={1},towns={[1]=G.new(1,18,20,{grow_counter=0,layout="original"})}}
local c=S.company(s,owner)
c.cash,c.loan,c.expense=500000,0,0
local initial_cash=c.cash
for id in ipairs(s.tiles) do s.tiles[id]={h=1,terrain="grass",variant=1} end
for x=8,30 do assert(S.town_road_piece(s,1,S.id(x,20),10,true)) end
local disk=load_("campaign_checkpoint")(core,load_("packed_campaign"),file)
disk.write_state(s)
local client=load_("campaign_authority_client")(core,m)
local cap={autoplay=true,seconds_per_day=.05,road={start_year=1950,breakdowns=0,service_interval=0},oil_tanker=true,
  road_town_policy={allow_town_roads=false},durable_actions=true}
local function ask(q,done)
  q.player=owner
  assert(client.query(q,function(r) assert(r.ok,r.why);done(r) end))
end
local function stop()
  assert(client.query({kind="stop"},function() error("Unexpected early stop receipt") end))
end
local p=0
local function wait_day(n,done)
  ask({kind="clock"},function(r)
    p=p+1
    assert(p<500,"Timed out waiting for native campaign calendar")
    if r.day>=n then done(r) else core.after(.10,wait_day,n,done) end
  end)
end
local cost
local function expected_cash_after_funding(state)
  local year,month=S.date(state)
  return initial_cash-cost-25*((year-1950)*12+month-1)
end
core.register_on_mods_loaded(function()
  assert(client.start(cap,function(ready)
    assert(ready.ready and ready.day==10)
    ask({kind="town_authority",town=1},function(v)
      assert(v.value.funding.months==0 and v.value.funding.affordable)
      cost=v.value.funding.cost
      ask({kind="command",command={kind="town_fund_buildings",town=1,cost=cost,revision=v.revision}},function(f)
        assert(f.value.town==1 and f.value.months==3)
        wait_day(42,function()
          ask({kind="town_authority",town=1},function(month2)
            assert(month2.value.funding.months==2)
            stop()
          end)
        end)
      end)
    end)
  end,function(why)
    assert(why=="stopped")
    local midway=assert(disk.read())
    local town=midway.stock_town_growth.towns[1]
    assert(town.fund_buildings_months==2 and town.num_houses>0 and town.last_build and town.growing)
    assert(next(midway.fleet)==nil)
    assert(midway.companies[owner].cash==expected_cash_after_funding(midway))
    assert(midway.companies[owner].expense==initial_cash-midway.companies[owner].cash)
    assert(client.start(cap,function(ready)
      assert(ready.ready and ready.day==midway.day)
      wait_day(96,function()
        ask({kind="town_authority",town=1},function(expired)
          assert(expired.value.funding.months==0)
          stop()
        end)
      end)
    end,function(reason)
      assert(reason=="stopped")
      local expired=assert(disk.read())
      local t=expired.stock_town_growth.towns[1]
      assert(t.num_houses>=town.num_houses and not t.growing and t.reason=="disabled")
      assert(t.fund_buildings_months==0 and expired.day>=96)
      assert(client.start(cap,function(opened)
        assert(opened.ready and opened.day==expired.day)
        wait_day(136,stop)
      end,function(last)
        assert(last=="stopped")
        local complete=assert(disk.read())
        local no_growth=complete.stock_town_growth.towns[1]
        assert(no_growth.num_houses==t.num_houses and no_growth.last_build.tick==t.last_build.tick)
        assert(not no_growth.growing and no_growth.reason=="disabled" and complete.day>=136)
        assert(next(complete.fleet)==nil)
        assert(complete.companies[owner].cash==expected_cash_after_funding(complete))
        assert(complete.companies[owner].expense==initial_cash-complete.companies[owner].cash)
        assert(complete.companies[owner].stock_quarters[1].expenses==0,
          "Monthly Other overhead must not enter the operating-expense column")
        core.log("action",("PASS NATIVE MUNICIPAL ROADS: monthly funding grew %d houses, expired, and stayed disabled after two reopens"):format(t.num_houses))
        core.request_shutdown("Native monthly town growth passed",false,0)
      end,file))
    end,file))
  end,file))
end)
