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
    assert(cell.node:find(shape==0 and "bayline:stock_river_flat" or "bayline:stock_river_"..shape,1,true)==1,
      "Missing native river mesh at "..id..": "..cell.node)
  end
  local function cut(owner,x,z,cost)
    local company=Sim.company(S,owner)
    local cash=company.cash
    local yes,price,foot=Sim.landscape(S,owner,"raise",x,z,nil,nil,nil,"footprint")
    assert(yes and price==cost and #foot.corners==1)
    local ok,message,changed=Sim.landscape(S,owner,"raise",x,z)
    assert(ok,message)
    assert(company.cash==cash-cost)
    render.update(changed)
  end
  core.emerge_area({x=14,y=0,z=30},{x=37,y=4,z=42},function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      if phase=="save" then
        still_river(read(flat),flat,0,224)
        still_river(read(slope),slope,3,219)
        still_river(read(untouched),untouched,0,87)
        -- Editing other river cells along the adjoining row does not clear
        -- this flat river or rerender it as grass.
        cut("River QA",15,17,20250)
        still_river(read(flat),flat,0,224)
        -- Both commands share an actual changed corner with their river.
        cut("River QA",16,19,40250)
        cut("River QA other account",9,18,40250)
        assert(S.tiles[flat].terrain=="grass" and S.tiles[slope].terrain=="grass")
        assert(not read(flat).node:find("river") and not read(slope).node:find("river"))
        for _=1,5 do Sim.daily(S);render.update(S.changed);S.changed={} end
        assert(not read(flat).class and not read(flat).variant)
        assert(read(slope).class~="river" and not read(slope).variant)
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
      assert(a.class~="river" and b.class~="river" and not a.variant and not b.variant)
      core.log("action",("STOCK GENERATED NATIVE %s river landscaping flat=%s incline=%s adjacent=%s")
        :format(phase,a.class or "dry",b.class or "dry",read(untouched).class))
      core.request_shutdown("Generated river landscaping verification complete",false,0)
    end)
  end)
end)
