-- Fixture over the real Sim command and physical landscape clock.
return function(Sim,Terrain)
  local F={}
  F.start_x,F.start_z,F.end_x,F.end_z=3,9,8,11
  F.trench_x,F.trench_z=14,14
  function F.seed(s)
    -- One strip of level-0 sea; every other original corner is a level-1
    -- shelf except the shared bank. No town or route state is borrowed.
    for z=1,Sim.H do for x=1,Sim.W do
      s.tiles[Sim.id(x,z)]={terrain=x<=2 and "water" or "grass",h=x<=3 and 0 or 1,
        variant=(x+z)%4}
    end end
    s.sites,s.stations,s.fleet,s.companies={},{},{},{}
    s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x)return x<=3 and 0 or 1 end)
    s.road_economy,s.road_stock_clock,s.road_stock_house_supply=true,true,true
    s.passenger_house_clock=nil
    s.changed=nil
    Sim.mount_coastal_flood(s)
    return s
  end
  local function level_zero(grid,x,z)
    local mask,base=Terrain.tile(grid,x,z)
    return mask==0 and base==0
  end
  function F.edit(s)
    local home=Sim.id(F.trench_x,F.trench_z)
    local bay=Sim.id(F.end_x-1,F.start_z)
    local company=Sim.company(s,"Survey")
    local cash=company.cash
    local before=s.corner_grid.revision
    local ok,cost=Sim.landscape(s,"Survey","level",F.start_x,F.start_z,F.end_x,F.end_z,false,true)
    assert(ok and cost>0 and s.corner_grid.revision==before and company.cash==cash)
    local built,_,dirty=Sim.landscape(s,"Survey","level",F.start_x,F.start_z,F.end_x,F.end_z,false)
    assert(built and #dirty>0 and company.cash==cash-cost)
    assert(level_zero(s.corner_grid,F.end_x-1,F.start_z) and s.tiles[bay].terrain=="grass")
    local built,note,other=Sim.landscape(s,"Survey","lower",F.trench_x,F.trench_z,F.trench_x+2,F.trench_z+2,false)
    assert(built,note)
    assert(level_zero(s.corner_grid,F.trench_x,F.trench_z) and s.tiles[home].terrain=="grass")
    local fail,reason=Sim.landscape(s,"Survey","lower",F.trench_x,F.trench_z)
    assert(not fail and reason:find("Already at sea level",1,true))
    return {bay=bay,home=home,changed=dirty,isolated_changed=other}
  end
  function F.flood(s,edit,after_day)
    local reached
    for i=1,75 do
      Sim.daily(s)
      if after_day then after_day(i) end
      if s.tiles[edit.bay].terrain=="water" then reached=reached or i end
    end
    assert(reached and reached>1 and s.tiles[edit.bay].water_class=="sea" and not s.tiles[edit.bay].coastal_water)
    assert(s.tiles[edit.home].terrain=="grass")
    return reached
  end
  return F
end
