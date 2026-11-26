local m=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
local function mod(p) return dofile(m.."/"..p..".lua") end
local Sim=mod("sim")
local Pack=mod("packed_campaign")
local P=mod("openttd/passengers")
local Rating=mod("openttd/station_rating")
local Roads=mod("station_rating_runtime")(Sim,Rating,P)
local C=mod("openttd/station_catchment")(P,Rating,function() return 0 end,function() return 0 end)
local Source=mod("passenger_supply_mux")
local side=256
Sim.W,Sim.H=side,side
local native=core~=nil
local function time() return native and core.get_us_time()/1000000 or os.clock() end
local function run()
  local old=Source(Sim,C,P,Roads,Rating)
  local new=Source(Sim,C,P,Roads,Rating)
  local orig={road={stations={},seed=501,day=0,topology=1},service={stations={}}}
  for i=0,511 do
    local x,z=(i%32)*8,math.floor(i/32)*16
    local kind=i%4
    local st={id=i+1,owner="Team "..i%7,site=i%15+1,mode=kind==0 and "road" or "service",
      stock={},last_service={},tile=Sim.id(x+1,z+1)}
    if kind==0 then
      orig.road.stations[st.id]=st
      Roads.status(orig.road,st)
    else
      local names={[1]="rail",[2]="dock",[3]="airport_intercontinental"}
      st.tiles={{x=x,y=z,kind=names[kind]}}
      orig.service.stations[st.id]=st
      st.passenger_rating_state=Rating.new()
    end
    Rating.observe_loading(st.passenger_rating_state,80,0,25)
    st.passenger_rating_state.rating=100+i%131
  end
  local packed=Pack.encode(orig)
  local function ctx(indexed)
    return {width=side,height=side,station_id=function(kind,s)return kind=="road" and s.id or s.id+10000 end,
      index_passenger_catchments=indexed,select_goods=true,modified=true}
  end
  local function sample(M,indexed)
    local st=Pack.decode(packed)
    collectgarbage("collect")
    local settings=ctx(indexed)
    local began=time()
    local units,count=0,0
    for i=1,2000 do
      local x,z=(i*107)%255,math.floor(i*23027/255)%255
      assert(M.capture(st.road,8+i%8,x,z,{town=i%35+1,area=i%5==0 and 2 or 1},i))
      local n,r=M.consume(st.road,st.service,i,settings)
      units,count=units+n,count+#r
    end
    return (time()-began)*1000,st,units,count
  end
  local function same(a,b)
    if type(a)~="table" then return a==b end
    if type(b)~="table" then return false end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
  end
  for i=1,8 do
    local a,b,as,bs,au,bu,ac,bc
    if i%2==1 then a,as,au,ac=sample(old,false);b,bs,bu,bc=sample(new,true)
    else b,bs,bu,bc=sample(new,true);a,as,au,ac=sample(old,false) end
    assert(au==bu and ac==bc and au>0 and same(as,bs))
    print(("SPATIAL_PASSENGERS batch=%d baseline_ms=%.3f indexed_ms=%.3f matching_units=%d allocations=%d"):format(i,a,b,au,ac))
  end
  if native then core.request_shutdown("Native passenger coverage benchmark complete",false,0) end
end
if native then
  for _,g in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..g,"air") end
  core.after(0,run)
else run() end
