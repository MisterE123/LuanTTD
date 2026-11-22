-- Luanti preload for the isolated async VM. The returned factory is also
-- used by plain-Lua conformance tests. No world handle or engine writes.
local function make(P,Slope,Terrain)
  local byte,char=string.byte,string.char
  return function(s,job,id)
    local valid=P.snapshot(s)
    local r=P.envelope(valid and s or {},type(job)=="table" and job.kind,id)
    if not valid then r.error="INVALID_SNAPSHOT";return r end
    job=P.job(s,job)
    if not job then r.error="INVALID_JOB";return r end
    if job.kind=="raster" or job.kind=="river_raster" then
      local w,h=s.width,s.depth
      local rows={}
      for z=0,h-1 do
        local row={}
        for x=0,w-1 do
          local i=z*(w+1)+x+1
          local n,a,b,d=byte(s.corners,i),byte(s.corners,i+1),byte(s.corners,i+w+1),byte(s.corners,i+w+2)
          if not Slope.valid(n,a,b,d) then r.error="INVALID_CORNERS";return r end
          local m,base=Slope.classify(n,a,b,d)
          local high=math.max(n,a,b,d)
          if job.kind=="river_raster" then
            local packed=P.terrain_bytes(s.tiles,z*w+x,m,base,high)
            if not packed then r.error="INVALID_TERRAIN_WORD";return r end
            row[x+1]=packed
          else
            row[x+1]=char(m,base,high)
          end
        end
        rows[z+1]=table.concat(row)
      end
      r.profiles=table.concat(rows)
      return r
    end
    local ok,g=pcall(Terrain.new,s.width,s.depth,function(x,z)
      return byte(s.corners,(z-1)*(s.width+1)+x)
    end)
    if not ok then r.error="INVALID_CORNERS";return r end
    -- The planner's edge/freeform predicate is applied to WORLD coords
    -- after translating its bounded local quote. A window isn't a map.
    local plan,err=Terrain.plan(g,job.x-s.x+1,job.z-s.z+1,job.mask,job.up,
      {max_height=job.max_height,freeform_edges=true})
    if not plan then r.error=err;return r end
    local rows={}
    for _,c in ipairs(plan.changes) do
      if c.x==1 or c.z==1 or c.x==s.width+1 or c.z==s.depth+1 then
        r.error="NEED_WIDER_REGION";return r
      end
      local x,z=c.x+s.x-1,c.z+s.z-1
      if not job.freeform_edges and (x<=2 or z<=2 or x>=s.map_width or z>=s.map_depth) then
        r.error="TOO_CLOSE_TO_EDGE";return r
      end
      rows[#rows+1]=P.encode(x,z,c.height)
    end
    r.patch,r.cost=table.concat(rows),plan.cost
    return r
  end
end

if core and not core.get_player_by_name then
  local mod=core.get_current_modname()
  local path=assert(core.get_modpath(mod or "bayline"),"No owning Luanti module in terrain async VM")
  local protocol=dofile(path.."/world_async_protocol.lua")
  local Slope=dofile(path.."/openttd/slope.lua")
  local Terrain=dofile(path.."/openttd/terrain.lua")
  core.luanttd_world_async_run=make(protocol,Slope,Terrain)
end
return make
