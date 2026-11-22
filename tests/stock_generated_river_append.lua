-- Appended only to a disposable Luanti test game.
local function river_digest()
  local a={}
  local count,sloped=0,0
  for i,t in ipairs(S.tiles) do
    if t.water_class=="river" then
      local slope,base=api.terrain.tile(i)
      assert(t.terrain=="water" and not t.coastal_water and not t.stock_void)
      assert(type(t.stock_river_bits)=="number" and base==t.h)
      a[#a+1]=table.concat({i,t.stock_river_bits,slope,base},",")
      count=count+1
      if slope~=0 then sloped=sloped+1 end
    else assert(t.stock_river_bits==nil) end
  end
  assert(count==63 and sloped==5)
  return core.sha256(table.concat(a,";"))
end
core.after(0,function()
  local p=assert(S.stock_generated_profile)
  local river=assert(p.river_stats)
  assert(p.river_rng_cursor==2899 and S.passenger_house_clock.head==2899)
  assert(p.terrain_rng[1]==2550762642 and p.terrain_rng[2]==824967927)
  assert(river.rivers==2 and river.terraform_commands==2 and river.terraform_committed==2 and
    river.terraform_corner_edits==2 and river.terraform_cleared_water==3)
  local digest=river_digest()
  local phase=core.settings:get("bayline_native_generation_phase")
  local flat,slope,lock=Sim.id(15,18),Sim.id(9,18),Sim.id(25,20)
  local Water=dofile(mod.."/openttd/ship_follow.lua")(Track)
  local Facilities=dofile(mod.."/openttd/ship_facilities.lua")(Track,Water)
  local Network=dofile(mod.."/ship_network.lua")(Sim,dofile(mod.."/openttd/terrain.lua"),Water,Facilities)
  local board=Network.board(S)
  assert(board.tile(flat).kind=="river" and Water.at(board,flat)~=0)
  assert(board.tile(slope).kind=="river" and Water.at(board,slope)==0)
  assert(S.tiles[flat].stock_river_bits==224 and S.tiles[slope].stock_river_bits==219)
  assert(not Sim.plan(S,"riverQA","road",{flat}))
  local lock_state
  core.emerge_area({x=17,y=0,z=35},{x=53,y=5,z=41},function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      assert(core.get_node({x=30,y=1,z=36}).name:match("^bayline:stock_river_flat"))
      assert(core.get_node({x=18,y=1,z=36}).name:match("^bayline:stock_river_3"))
      if phase=="save" then
        local company=Sim.company(S,"riverQA")
        local cash=company.cash
        local quote,why=api.waterworks.quote_lock(S,"riverQA",lock)
        assert(quote,why)
        lock_state=assert(api.waterworks.build_lock(S,"riverQA",lock))
        assert(lock_state.cost==quote.cost and company.cash==cash-lock_state.cost)
        api.render.update(lock_state.tiles)
        S.river_qacheck={digest=digest,lock_cost=lock_state.cost,lock_cash=company.cash}
        api.save()
      else
        lock_state=assert(S.stock_ship_locks[lock])
        local proof=assert(S.river_qacheck)
        assert(digest==proof.digest and Sim.company(S,"riverQA").cash==proof.lock_cash)
        assert(S.tiles[lock].ship.kind=="lock" and S.tiles[lock].water_class=="river")
      end
      assert(Water.at(board,lock)~=0)
      core.log("action",("STOCK GENERATED NATIVE %s rivers=63 slopes=5 cursor=%d lock-cost=%d")
        :format(phase,p.river_rng_cursor,S.river_qacheck.lock_cost))
      core.request_shutdown("Generated river verification complete",false,0)
    end)
  end)
end)
