-- Observe ordinary native Luanti map generation on a stock fresh world.
core.after(0,function()
  assert(api.generated_world)
  local id,mask,base
  for i,t in ipairs(S.tiles) do
    local m,h=api.terrain.tile(i)
    if (m==1 or m==2 or m==4 or m==8) and api.render.uses_slope(i)
        and not (t.coastal_water or t.wood or t.build or t.water_class or t.stock_clear_ground or t.stock_landmark) then
      id,mask,base=i,m,h
      break
    end
  end
  assert(id,"No ordinary generated one-corner slope")
  local x,z=Sim.xy(id)
  local lower={x=2*x,y=base,z=2*z}
  local upper={x=lower.x+1,y=base+1,z=lower.z+1}
  core.emerge_area(lower,upper,function(_,_,remaining)
    if remaining~=0 then return end
    core.after(0,function()
      local fill="luanttd_core:slope_fill_open"
      assert(core.registered_nodes[fill].mesh=="bl_slope_fill_open.obj")
      for dx=0,1 do for dz=0,1 do
        assert(core.get_node({x=lower.x+dx,y=base,z=lower.z+dz}).name==fill)
        local top=core.get_node({x=lower.x+dx,y=base+1,z=lower.z+dz}).name
        local expected=dx+dz==0 and ("luanttd_core:slope_%d_%d"):format(mask,S.tiles[id].variant) or "air"
        assert(top==expected,top.." vs "..expected)
      end end
      core.log("action",("SLOPE_FILL_NATIVE_PASS corner=%d tile=(%d,%d) base=%d top=original"):format(mask,x,z,base))
      core.request_shutdown("Native slope no-overlap verified",false,0)
    end)
  end)
end)
