-- Included only in a disposable native Luanti fixture world.
local owner="Paired Native QA"
local function id(x,z) return Sim.id(x,z) end
local function verify()
  local O,R=assert(api.rail_owned),assert(api.rail_dispatch_controller)
  local qa=S.owned_pair_native
  local merge=id(8,14)
  local function day()
    Sim.daily(S)
    assert(not R.current(S).failure,R.current(S).failure)
    local motion,loading=Sim.rail_paid_motion_events(S),Sim.rail_loading_events(S)
    return motion,loading
  end
  local function matches(r,i)
    local tile,td,f=Sim.rail_paid_pose(S,i,1,r.fleet_id)
    if not tile then assert(r.consist.parts[i].hidden);return end
    assert(tile==r.consist.parts[i].tile and td==r.consist.parts[i].pose.td)
    local pose=dofile(mod.."/rail_pose.lua")(Track)
    local x,z=pose.sample(td,f)
    local tx,tz=Sim.xy(tile)
    local pos={x=2*tx+.5+x,y=.614,z=2*tz+.5+z}
    local name=i==1 and "bayline:dispatch_steam" or "bayline:dispatch_wagon"
    for _,obj in ipairs(core.get_objects_inside_radius(pos,.09)) do
      local e=obj:get_luaentity()
      if e and e.name==name then return obj end
    end
    error("Missing independent visible steam consist part for "..r.fleet_id..":"..i)
  end
  local function rendered(a,b)
    api.rail_dispatch_view.step(.1,true,1)
    local proof={}
    for _,r in ipairs({a,b}) do
      for i=1,2 do
        local obj=matches(r,i)
        if obj then assert(not proof[obj]);proof[obj]=true end
      end
    end
  end
  if qa then
    local a,b=assert(R.current_paid(S,qa.a)),assert(R.current_paid(S,qa.b))
    assert(a.consist.parts[1].tile~=merge and a.consist.parts[2].tile==merge)
    assert(b.phase=="waiting" and R.signal(S,id(8,13),1)=="red")
    assert(S.stock_ship_commercial.rail_serials[0x4000+a.paid_clock])
    assert(S.stock_ship_commercial.rail_serials[0x4000+b.paid_clock])
    assert(S.companies[owner].cash==qa.cash)
    rendered(a,b)
    local tail,entry,paidA,paidB=nil,nil,0,0
    for _=1,100 do
      local motion,loading=day()
      for _,e in ipairs(motion) do
        if e.kind=="tail_left" and e.tile==merge and e.train==a.id then tail=e.world_tick end
        if e.kind=="front_entered" and e.tile==merge and e.train==b.id then entry=e.world_tick end
      end
      for _,e in ipairs(loading) do
        if e.kind=="fare" and e.vehicle==0x4000+a.paid_clock then paidA=paidA+e.amount
        elseif e.kind=="fare" and e.vehicle==0x4000+b.paid_clock then paidB=paidB+e.amount end
      end
      if a.paired.complete and b.paired.complete then break end
    end
    assert(tail and entry and tail<=entry and a.paired.complete and b.paired.complete)
    local av,bv=Sim.rail_paid_status(S,a.fleet_id),Sim.rail_paid_status(S,b.fleet_id)
    assert(av.fare==paidA and bv.fare==paidB and paidA>0 and paidB>0)
    assert(av.delivered==40 and bv.delivered==40 and av.finished and bv.finished)
    assert(S.companies[owner].revenue==paidA+paidB)
    assert(R.board(S).tile(a.consist.parts[1].tile).reserved_bits~=0)
    assert(R.board(S).tile(b.consist.parts[1].tile).reserved_bits~=0)
    assert(a.consist.parts[1].tile~=b.consist.parts[1].tile and not R.clear(S,owner))
    core.log("action",("OWNED_PAIR_NATIVE_PASS paid=%d/%d release=%d entry=%d parked=2"):format(paidA,paidB,tail,entry))
    core.request_shutdown("Both purchased coaches survived and completed their distinct orders",false,0)
    return
  end

  local g=S.corner_grid
  for i=1,#g.levels do g.levels[i]=0 end
  for _,t in ipairs(S.tiles) do
    t.terrain,t.h,t.build,t.owner,t.site,t.wood,t.house,t.source_house,t.rail_tracks="grass",0,nil,nil,nil,nil,nil,nil,nil
  end
  S.stock_select_goods=false
  local Signal=dofile(mod.."/openttd/rail_signals.lua")(Track)
  local first,lastA,lastB=dofile(mod.."/rail_owned_pair_fixture.lua")(S,Sim,Track,api.trackworks,R,Signal,owner)
  local c=Sim.company(S,owner)
  local function buy(depot)
    return assert(O.commit(S,owner,assert(O.quote(S,owner,depot,{0,27})))).id
  end
  local a,b=buy(id(2,14)),buy(id(8,9))
  local setupA,setupB={id=a,first=first,second=lastA},{id=b,first=first,second=lastB}
  assert(S.rail_owned_pair_enabled,"Mount the actual opt-in setting before running the fixture")
  assert(not O.start_pair(S,owner,setupA,{id=b,first=first,second=9000}))
  assert(#R.current(S).runs==0 and c.cash==100000-2*12866)
  local ok,why,runs=O.start_pair(S,owner,setupA,setupB)
  assert(ok,why)
  local one,two=runs[1],runs[2]
  assert(O.toggle(S,owner,b))
  for index=1,32 do
    day()
    if index==1 then assert(O.toggle(S,owner,b)) end
    if one.consist.parts[1].tile~=merge and one.consist.parts[2].tile==merge and two.phase=="waiting" then
      assert(R.signal(S,id(8,13),1)=="red")
      rendered(one,two)
      S.owned_pair_native={a=a,b=b,cash=c.cash}
      api.save()
      core.log("action","OWNED_PAIR_NATIVE_SAVED_TAIL")
      core.request_shutdown("Saved the real red PBS merge with the first train's rear still occupying it",false,0)
      return
    end
  end
  error("Did not save live contention on stock PBS merge")
end
core.after(0,function()
  core.emerge_area({x=4,y=-1,z=6},{x=73,y=4,z=31},function(_,_,remaining)
    if remaining==0 then core.after(0,verify) end
  end)
end)
