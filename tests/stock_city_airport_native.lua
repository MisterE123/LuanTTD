-- Appended to a disposable ordinary Linux world; all authority is native.
local started=false
local stock=tonumber(core.settings:get("luanttd_qa_airframe")) or 226
local models={
  [218]={visual="yate_haugan",price=205078,flight=true},
  [220]={visual="bakewell_luckett_lb8",price=49218},[228]={visual="darwin_300",price=82031},
  [217]={visual="ffp_dart",price=43750},[225]={visual="yate_yac_1_11",price=43750},[226]={visual="darwin_100",price=49218},
  [221]={visual="bakewell_luckett_lb9",price=46484,flight=true},
  [222]={visual="bakewell_luckett_lb80",price=49218,flight=true},
  [223]={visual="bakewell_luckett_lb10",price=51953,flight=true},
  [224]={visual="bakewell_luckett_lb11",price=54687,flight=true},
  [227]={visual="darwin_200",price=46484,flight=true},[229]={visual="darwin_400",price=49218,flight=true},
  [230]={visual="darwin_500",price=51953,flight=true},[231]={visual="darwin_600",price=73828,flight=true},
  [232]={visual="guru_galaxy",price=68359,flight=true},[233]={visual="airtaxi_a21",price=54687,flight=true},
}
local model=assert(models[stock])
local layout=core.settings:get("luanttd_qa_air_layout") or "city"
local city=layout=="city"
assert(city or (stock==221 and layout=="country"))
local w,d=city and 6 or 4,city and 6 or 3
local airport_cost=w*d*600
local function scene(viewer)
  assert((not city or api.capabilities.city_airport) and api.capabilities.air[stock],"Complete stock media required")
  local owner=viewer:get_player_name()
  local function inspect(center,radius,accept)
    for _,ref in ipairs(core.get_objects_inside_radius(center,radius)) do
      local actor,pos=ref:get_luaentity(),ref:get_pos()
      if actor and pos and actor.name=="luanttd_core:stock_"..model.visual and accept(pos,ref:get_properties().mesh) then
        return pos
      end
    end
  end
  if core.settings:get_bool("luanttd_qa_air_restart",false) then
    local disk=assert(OwnerCheckpoint.read())
    local id,unit=next(disk.stock_owned_air_fleet)
    assert(id and unit.stock_id==stock and unit.hangar and disk.companies[owner])
    local a,b
    for _,airport in pairs(disk.stock_small_airports) do if a then b=airport else a=airport end end
    assert(a and b)
    local ax,az=Sim.xy(a.origin)
    local bx,bz=Sim.xy(b.origin)
    viewer:set_pos({x=ax+bx+5,y=10,z=az+bz+5})
    viewer:set_look_vertical(1.1)
    local prior
    local function again()
      local center=viewer:get_pos()
      local pos=inspect(center,70,function() return true end)
      if pos then
        if prior and (pos.x-prior.x)^2+(pos.y-prior.y)^2+(pos.z-prior.z)^2>.12 then
          local mounted=assert(OwnerCheckpoint.read())
          assert(mounted.stock_owned_air_fleet[id].stock_id==stock)
          core.log("action","PASS NATIVE CITY RESTART: same purchased aircraft #"..stock.." resumed moving on persisted orders")
          return
        end
        prior=pos
      end
      core.after(.16,again)
    end
    core.after(.3,again)
    return
  end
  local positions={}
  for v=3,Sim.H-9 do
    for u=3,Sim.W-9 do
      local enabled,level=true,nil
      for dz=0,d-1 do for dx=0,w-1 do
        local id=Sim.id(u+dx,v+dz)
        local t=S.tiles[id]
        local slope,h=api.terrain.tile(id)
        if slope~=0 or level and h~=level or t.wood or t.house or t.site or t.owner or t.stock_industry or
            t.stock_landmark or t.stock_void or t.terrain=="water" or t.build then enabled=false end
        level=h
      end end
      if enabled and (#positions==0 or math.abs(positions[1].x-u)+math.abs(positions[1].z-v)>=25) then
        positions[#positions+1]={x=u,z=v,h=level,id=Sim.id(u,v)}
        if #positions==2 then break end
      end
    end
    if #positions==2 then break end
  end
  assert(#positions==2)
  local focus=positions[1]
  viewer:set_pos({x=2*focus.x+5,y=focus.h+9,z=2*focus.z-10})
  viewer:set_look_horizontal(0)
  viewer:set_look_vertical(.55)
  assert(world.go_menu(viewer,"airfields"))
  local has=false
  for _,slot in ipairs(world.hotbar_layout(viewer)) do if slot==4 then has=true end end
  assert(has,"The airport has no native hotbar item")
  local function ask(value,cb)
    value.player=owner
    local yes,why=authority.query(value,function(r)
      assert(r.ok,value.kind..": "..tostring(r.why or r.value));cb(r)
    end)
    assert(yes,why)
  end
  local function use(req,cb)
    ask({kind="transport_quote",request=req},function(q)
      if req.operation=="build" then assert(#q.value.tiles==w*d and q.value.cost==airport_cost) end
      ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},cb)
    end)
  end
  local ground="bl_stock_"..model.visual..".obj"
  local flight="bl_stock_"..model.visual.."_flight.obj"
  local departed,approach=false,false
  local function watch_flight()
    local target=positions[2]
    if not departed then
      local p=inspect({x=focus.x*2+5,y=focus.h+4,z=focus.z*2+5},42,function(pos,mesh)
        return pos.y>focus.h+1.85 and mesh==flight
      end)
      if p then
        departed=true
        core.log("action","NATIVE AIR AIRBORNE: actual flight mesh in motion for #"..stock)
        core.after(.24,function()
          viewer:set_pos({x=2*target.x+5,y=target.h+8,z=2*target.z-8})
          viewer:set_look_horizontal(0);viewer:set_look_vertical(.58)
          approach=true
        end)
      end
    elseif approach then
      local landed=inspect({x=target.x*2+5,y=target.h+1,z=target.z*2+5},10,function(pos,mesh)
        return pos.y<target.h+1.03 and mesh==ground and pos.x>target.x*2-1 and
          pos.x<target.x*2+w*2+1 and pos.z>target.z*2-1 and pos.z<target.z*2+d*2+1
      end)
      if landed then
        core.log("action","PASS NATIVE CITY: built worker "..layout.." runways, bought #"..stock..", observed ground taxi, gear-up flight and gear-down arrival")
        return
      end
    end
    core.after(.10,watch_flight)
  end
  local function observe()
    local paint=core.get_node({x=focus.x*2+(w-1)*2,y=focus.h+1,z=focus.z*2})
    if paint.name~=("luanttd_core:"..(city and "city" or "small").."_airport_"..(w-1).."_0") then core.after(.18,observe);return end
    local taxi=inspect({x=focus.x*2+5,y=focus.h+2,z=focus.z*2+5},12,function(pos,mesh)
      return pos.z>focus.z*2+2.6 and pos.y<focus.h+1.1 and mesh==ground
    end)
    if taxi then
      if model.flight then
        core.log("action","NATIVE AIR TAXI: worker "..layout.." pavement and the correct gear-down airframe #"..stock)
        watch_flight()
      else core.log("action","PASS NATIVE CITY: worker built and painted "..w*d.." stock tiles; taxi by airframe #"..stock) end
      return
    end
    core.after(.12,observe)
  end
  local loans=math.max(0,math.ceil((2*airport_cost+model.price-100000)/10000))
  local function airports()
    use({mode="air",operation="build",layout=layout,tile=positions[1].id},function(one)
      use({mode="air",operation="build",layout=layout,tile=positions[2].id},function(two)
        local first,second=one.value.id,two.value.id
        ask({kind="depot",mode="air",depot=first},function(q)
          local chosen
          for _,entry in ipairs(q.value.offers) do if entry.request.engine==stock then chosen=entry end end
          assert(chosen and chosen.price==model.price)
          use(chosen.request,function(bought)
            ask({kind="command",command={kind="transport_start",mode="air",first=first,second=second,
                revision=bought.revision}},function()
              local disk=assert(OwnerCheckpoint.read())
              assert((disk.stock_small_airports[first].layout or "country")==layout and disk.stock_owned_air_fleet[bought.value.id].stock_id==stock)
              assert(disk.companies[owner].cash==100000+loans*10000-2*airport_cost-model.price)
              core.after(.22,observe)
            end)
          end)
        end)
      end)
    end)
  end
  local function lend(left)
    if left==0 then airports();return end
    ask({kind="company"},function(q)
      ask({kind="command",command={kind="company_loan",amount=10000,revision=q.revision}},function()
        lend(left-1)
      end)
    end)
  end
  lend(loans)
end
local function begin()
  local p=core.get_player_by_name("CityReview")
  if p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0 then
    if not started then started=true;scene(p) end
  else core.after(.22,begin) end
end
core.after(.22,begin)
