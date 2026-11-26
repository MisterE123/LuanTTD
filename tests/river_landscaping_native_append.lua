-- Appended only to the disposable generated game.
core.after(0,function()
  local p=assert(S.stock_generated_profile)
  assert(p.river_stats.rivers==2 and api.coastal_flood_tools and S.stock_coastal_flood)
  local phase=core.settings:get("bayline_native_generation_phase")
  local flat,slope,untouched=Sim.id(15,18),Sim.id(9,18),Sim.id(17,18)
  local function read(id)
    local x,z=Sim.xy(id)
    local m,h=api.terrain.tile(id)
    local t=S.tiles[id]
    local n=core.get_node({x=x*2,y=h+(m==0 and 0 or 1),z=z*2}).name
    return {slope=m,base=h,node=n,class=t.water_class,variant=t.stock_river_bits}
  end
  local function still_river(cell,id,shape,variant)
    assert(cell.class=="river" and cell.slope==shape and cell.variant==variant)
    assert(cell.node:find(shape==0 and "luanttd_core:stock_river_flat" or "luanttd_core:stock_river_"..shape,1,true)==1,
      "Missing native river mesh at "..id..": "..cell.node)
  end
  local function grade(owner,x,z,expected)
    local company=Sim.company(S,owner)
    local cash,rev,topology=company.cash,S.corner_grid.revision,S.topology
    local yes,price,foot=Sim.landscape(S,owner,"raise",x,z,nil,nil,nil,"footprint")
    local ok,message,changed=Sim.landscape(S,owner,"raise",x,z)
    if expected then
      assert(yes and price==expected and #foot.corners==1,price)
      assert(ok,message)
      assert(company.cash==cash-expected)
      render.update(changed)
    else
      assert(not yes and price:find("remove the river",1,true),price)
      assert(not ok and message==price)
      assert(company.cash==cash and S.corner_grid.revision==rev and S.topology==topology)
    end
  end
  core.emerge_area({x=14,y=0,z=30},{x=37,y=4,z=42},function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      if phase=="save" then
        still_river(read(flat),flat,0,224)
        still_river(read(slope),slope,3,219)
        still_river(read(untouched),untouched,0,87)
        grade("River QA",15,15,250) -- safe bank tile away from all affected river corners
        grade("River QA",16,19)
        grade("River QA other account",9,18)
        still_river(read(flat),flat,0,224)
        still_river(read(slope),slope,3,219)
        local account=Sim.company(S,"River QA")
        local q,cost=Sim.plan(S,"River QA","clear",{flat})
        assert(q and cost==10000)
        local prior=account.cash
        local ok,note,changed=Sim.build(S,"River QA","clear",{flat})
        assert(ok,note);assert(account.cash==prior-10000)
        render.update(changed)
        assert(not read(flat).class and not read(flat).variant and not read(flat).node:find("river"))
        still_river(read(slope),slope,3,219)
        S.stock_river_landscape_qa={flat=read(flat),slope=read(slope)}
        api.save()
      else
        local history=assert(S.stock_river_landscape_qa)
        for name,id in pairs{flat=flat,slope=slope} do
          local now=read(id)
          for _,key in ipairs{"slope","base","node","class","variant"} do assert(now[key]==history[name][key],key) end
        end
      end
      still_river(read(untouched),untouched,0,87)
      local a,b=read(flat),read(slope)
      assert(a.class~="river" and not a.variant)
      still_river(b,slope,3,219)
      core.log("action",("STOCK GENERATED NATIVE %s river landscaping flat=%s incline=%s adjacent=%s")
        :format(phase,a.class or "dry",b.class or "dry",read(untouched).class))
      core.request_shutdown("Generated river landscaping verification complete",false,0)
    end)
  end)
end)
