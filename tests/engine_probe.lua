-- Loaded only into a temporary copy by engine.sh, never by the shipping game.
return function(api,ui)
  local M,S,R=api.Sim,api.s,api.render
  local s=S
  local phase=core.settings:get("bayline_test_phase")
  local function finish(message)
    core.log("action","BAYLINE PASS "..phase.." "..message)
    core.request_shutdown("Bayline integration complete",false,0)
  end
  core.after(0.3,function()
    if phase=="create" then
      assert(s.day==0 and s.fleet[1]==nil)
      assert(M.demo(s,"Example"))
      for _=1,12 do M.daily(s) end
      local v=s.fleet[1];local c=s.companies.Example
      assert(v and v.route and c.revenue>0 and c.paid_units>0)
      local x,z=M.xy(s.stations[1].tile);x,z=x*2,z*2
      core.emerge_area({x=x,y=-4,z=z},{x=x+2,y=5,z=z+2},function(_,_,left)
        if left==0 then core.after(0,function()
          local shelter=false
          for dz=0,1 do for dx=0,1 do
            local at=core.get_node({x=x+dx,y=1,z=z+dz})
            if at.name:match("^bayline:stop_shelter") then shelter=true end
            assert(core.get_node({x=x+dx,y=0,z=z+dz}).name:match("^bayline:road_"))
          end end
          assert(shelter,"missing 3D shelter over the continuous road")
          for _,suffix in ipairs({"stop_shelter","stop_shelter_quarter","stop_shelter_corner","depot_0","depot_1","depot_2","depot_3"}) do
            local def=core.registered_nodes["bayline:"..suffix]
            assert(def and def.drawtype=="mesh")
            local model=assert(io.open(core.get_modpath("bayline").."/models/"..def.mesh,"r"))
            assert(model:read("*l"));model:close()
          end
          api.save()
          local file=assert(io.open(core.get_worldpath().."/expected.txt","w"))
          file:write(s.day," ",c.revenue," ",v.delivered," ",v.progress);file:close()
          finish("route paid and road stop rendered")
        end) end
      end)
    elseif phase=="reload" then
      local fd=assert(io.open(core.get_worldpath().."/expected.txt","r"))
      local day,revenue,delivered,prog=fd:read("*n","*n","*n","*n");fd:close()
      local c=s.companies.Example;local v=s.fleet[1]
      assert(s.day==day and c.revenue==revenue and v.delivered==delivered)
      assert(v.route and math.abs(v.progress-prog)<1e-10 and #v.orders==2)
      assert(s.fleet[2]==nil and M.position(s,v))
      for _=1,22 do M.daily(s) end
      assert(c.revenue>revenue and v.delivered>delivered)
      finish("vehicle, orders, route progress and balance survived restart; delivery resumed")
    elseif phase=="world" then
      assert(core.get_mapgen_setting("mg_name")=="singlenode")
      local p={ x=18,z=24, get_player_name=function()return "Builder" end,
        get_properties=function()return {eye_height=1.625} end,
        get_look_dir=function()return {x=0,y=-1,z=0} end}
      function p:get_pos() return {x=self.x,y=10,z=self.z} end
      M.company(s,"Builder")
      ui.select_tool(p,"road")
      local a,b=M.id(9,12),M.id(18,12)
      assert(api.world.target(p)==a)
      ui.build_world(p,a)
      assert(not s.tiles[a].build)
      p.x=36
      assert(api.world.target(p)==b)
      ui.build_world(p,b)
      for _,id in ipairs(M.line(a,b)) do assert(s.tiles[id].build=="road") end
      ui.select_tool(p,"road_station")
      ui.build_world(p,b)
      assert(s.tiles[b].station and s.stations[s.tiles[b].station].owner=="Builder")
      for id in pairs(M.vehicles) do
        local entity=core.registered_entities["bayline:vehicle_"..id]
        assert(entity and entity.initial_properties.visual=="mesh")
        local obj=assert(io.open(core.get_modpath("bayline").."/models/"..entity.initial_properties.mesh,"r"))
        assert(obj:read("*l"));obj:close()
      end
      finish("world-picked road and terminal build; all ten vehicle models registered")
    elseif phase=="rail" then
      local owner="Corridor"
      local first,last=M.id(8,12),M.id(31,12)
      local route=M.line(first,last)
      for _,id in ipairs(route) do s.tiles[id]={terrain="grass",h=0,variant=1} end
      assert(M.build(s,owner,"rail",route))
      assert(M.build(s,owner,"rail_station",{first,last}))
      assert(M.build(s,owner,"signal",{M.id(21,12)}))
      local a,b=s.tiles[first].station,s.tiles[last].station
      for _=1,2 do
        local id=assert(M.purchase(s,owner,"steam","passenger",a))
        assert(M.add_order(s,owner,id,b))
        assert(M.toggle(s,owner,id))
      end
      for _=1,8 do M.daily(s) end
      assert(s.fleet[1].route and s.fleet[2].route and s.fleet[1].progress-s.fleet[2].progress>=2)
      api.save()
      finish("signaled corridor carries two trains with two-tile headway")
    elseif phase=="reload_rail" then
      local a,b=s.fleet[1],s.fleet[2]
      assert(a and b and a.route and b.route and s.fleet[3]==nil)
      local company=s.companies.Corridor
      local before=company.revenue
      for _=1,45 do
        M.daily(s)
        if a.route and b.route then
          assert(table.concat(a.route,",")==table.concat(b.route,","))
          assert(math.abs(a.progress-b.progress)>=2)
        end
      end
      assert(company.revenue>before and a.delivered>0 and b.delivered>0)
      finish("two-train convoy safely resumed after restart")
    else error("Unknown probe phase") end
  end)
end
