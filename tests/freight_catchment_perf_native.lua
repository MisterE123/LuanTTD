-- Native async comparison of normal mixed road/ship freight reports.
for _,name in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..name,"air") end
core.after(0,function()
  assert(core.handle_async(function()
    local mod=core.get_modpath("luanttd_core").."/"
    local function m(n) return dofile(mod..n..".lua") end
    local S,P,R,I=m("sim"),m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
    S.W,S.H=512,512
    local C=m("openttd/station_catchment")(P,R)
    local Coal=m("openttd/coal_industry")(P,R,C,I)
    local Timber=m("openttd/timber_industry")(P,C,R,I,Coal,m("openttd/town_goods"))
    local FC=m("openttd/farm_factory_industry")
    local Farm=FC(P,C,R,I,Coal,Timber)
    Farm=m("openttd/iron_steel_rules")(Farm,m("openttd/iron_steel_data"))
    m("openttd/temperate_bank_rules")(Farm,m("openttd/temperate_bank_data"))
    local Oil=m("openttd/oil_industry")(FC,P,C,R,I,Coal,Timber)
    local Fields=m("openttd/farm_factory_fields")(Coal)
    local Station=m("station_rating_runtime")(S,R,P)
    local cargo={"oil","livestock","goods","grain","wood","iron_ore","steel","valuables"}
    local vehicles={oil="oil_tanker",livestock="livestock_van",goods="goods_truck",grain="grain_truck",
      wood="wood_truck",iron_ore="iron_mps",steel="steel_balogh",valuables="valuables_balogh"}

    local function make(base)
      local runtime=m(base and "baseline_industry" or "timber_industry_runtime")
      local rules,adapter=m("combined_industry_runtime")(Timber,Farm,Oil,Fields,runtime,C)
      local Host=m(base and "baseline_road" or "road_farm_service")
      local host=Host(S,rules,adapter,P,I,R,Station,{tag="bench",label="Mixed",vehicles=vehicles,cargo=cargo})
      local s={sites={},tiles={},stations={},topology=1}
      local industries,ports={},{}
      local rows={{"forest",Timber},{"sawmill",Timber},{"farm",Farm},{"factory",Farm},{"oil_well",Oil},
        {"oil_refinery",Oil},{"oil_rig",Oil},{"steel_mill",Farm},{"iron_mine",Farm},{"temperate_bank",Farm}}
      local function origin(i) return ((i-1)%32)*16+3,math.floor((i-1)/32)*16+3 end
      for i=1,768 do
        local row=rows[(i-1)%#rows+1]
        local x,z=origin(i)
        local firm=row[2].new(row[1],i,x,z,{completed=true,original=true,generating_world=true})
        if row[1]=="oil_rig" then firm.neutral_station=2000+i end
        if i%27==0 then firm.removed=true end
        industries[i]=firm
      end
      for i=1,128 do
        local firm=industries[1+i*5]
        local x,z=firm.x,firm.z
        local at=S.id(x+1,z+1)
        local other=S.id(x+12,z+11)
        local st={id=i,tile=at,mode="road",owner="A",town=i,stop_type="truck"}
        if i%5==1 then
          st.road_members={[at]="truck",[other]="truck"}
          st.road_stop_areas={truck=true}
        end
        s.stations[i]=st
        for dx=2,3 do s.tiles[S.id(x+dx,z+1)]={house=true,source_house={id=18,town=i}} end
      end
      for i,f in ipairs(industries) do
        if f.neutral_station and not f.removed then
          ports[#ports+1]={id=f.neutral_station,mode="ship",owner="A",freight_cargo="oil",
            neutral_rig=i,serve_neutral=false,tile=S.id(f.x+1,f.z+1),
            tiles={{x=f.x,y=f.z,kind="dock"}}}
          if #ports==5 then break end
        end
      end
      s.stock_serve_neutral_industries=false
      local host_=host.bind(s,{industries=industries,ship_stations=ports})
      return s,host_,ports
    end
    local function same(a,b)
      if a==b then return true end
      if type(a)~="table" or type(b)~="table" then return false end
      for k,v in pairs(a) do if not same(v,b[k]) then return false end end
      for k in pairs(b) do if a[k]==nil then return false end end
      return true
    end
    local a,old,ap=make(true)
    local b,new,bp=make(false)
    assert(same(a,b))
    local function measure(s,host,ports,batch)
      collectgarbage("collect")
      local now=os.clock()
      for tick=1,3 do
        s.topology=1+batch*3+tick
        for _,st in ipairs(s.stations) do
          for _,kind in ipairs(cargo) do assert(host.report(st,kind,tick)) end
        end
        for _,st in ipairs(ports) do assert(host.report(st,"oil",tick)) end
      end
      return (os.clock()-now)*1000
    end
    local results={}
    for i=1,4 do
      local t,u
      if i%2==1 then t=measure(a,old,ap,i);u=measure(b,new,bp,i)
      else u=measure(b,new,bp,i);t=measure(a,old,ap,i) end
      assert(same(a,b) and same(ap,bp),"An ordinary freight report or saved queue changed")
      results[#results+1]={t,u}
    end
    local got_accept,has_source,grant=false,false,false
    for _,st in ipairs(b.stations) do
      local reports=st.bench_acceptance.reports
      got_accept=got_accept or reports.grain.accepts or reports.oil.accepts or reports.wood.accepts
      has_source=has_source or #reports.wood.sources>0 or #reports.oil.sources>0
      grant=grant or reports.goods.accepts
    end
    assert(got_accept and has_source and grant)
    for _,st in ipairs(bp) do
      assert(st.bench_acceptance.reports.oil.sources[1]==st.neutral_rig)
      assert(#st.bench_acceptance.reports.oil.sources==1)
    end
    -- A warm coverage index may still contain the now-closed address.
    -- The actual stock rule must no longer accept/offer from it.
    local retired=bp[1].neutral_rig
    for _,host in ipairs({old,new}) do
      for _,ind in ipairs(host.industries) do if ind.id==retired then ind.removed=true end end
    end
    measure(a,old,ap,5);measure(b,new,bp,5)
    assert(same(a,b) and same(ap,bp) and #bp[1].bench_acceptance.reports.oil.sources==0)
    return results
  end,function(results)
    assert(results and #results==4)
    for i,r in ipairs(results) do
      core.log("action",("NATIVE FREIGHT CATCHMENT %d before=%.3f after=%.3f ms"):format(i,unpack(r)))
    end
    core.request_shutdown("Mixed freight catchment reports match",false,0)
  end))
end)
