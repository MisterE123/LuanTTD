-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors: 16.0-RC1 src/industry_cmd.cpp,
-- execution portion of CheckIfCanLevelIndustryPlatform.
-- The caller quotes the whole footprint against unmodified terrain first.
-- Run the source's row-major one-corner commands in a sparse shadow so
-- an abandoned industry candidate never writes to the live world.
return function(Terrain)
  local L={}
  local NORTH=8
  function L.plan(grid,area,options)
    local staged=setmetatable({},{__index=grid.levels})
    local copy={}
    for key,value in pairs(grid) do copy[key]=value end
    copy.levels=staged
    local out={revision=grid.revision,dirty={},commands={},failures={},changes={}}
    local dirty={}
    for z=area.z+1,area.z+area.height do
      for x=area.x+1,area.x+area.width do
        local height=assert(Terrain.corner(copy,x,z),"Stock industry platform leaves the map")
        while height~=area.level do
          local raise=height<=area.level
          local context=options and options(copy,x,z,raise)
          local plan,why=Terrain.plan(copy,x,z,NORTH,raise,context)
          if plan then
            local touched={}
            if context and context.capture_stock_tops then
              for _,d in ipairs(plan.dirty) do
                if not context.void or not context.void(d.x,d.z) then
                  local _,_,top=Terrain.tile(copy,d.x,d.z,plan)
                  touched[#touched+1]={x=d.x,z=d.z,top=top}
                end
              end
            end
            assert(Terrain.apply(copy,plan))
            for _,d in ipairs(plan.dirty) do
              dirty[(d.z-1)*grid.width+d.x]=d
            end
            out.commands[#out.commands+1]={x=x,z=z,raise=raise,touched=#touched>0 and touched or nil}
          else
            -- The original command loop advances its local height counter
            -- regardless of the individual execution receipt.
            out.failures[#out.failures+1]={x=x,z=z,why=why}
          end
          height=height+(raise and 1 or -1)
        end
      end
    end
    local seq={}
    for id,height in pairs(staged) do
      if height~=grid.levels[id] then seq[#seq+1]={id=id,height=height} end
    end
    table.sort(seq,function(a,b)return a.id<b.id end)
    for _,c in ipairs(seq) do out.changes[#out.changes+1]=c end
    for _,d in pairs(dirty) do out.dirty[#out.dirty+1]=d end
    table.sort(out.dirty,function(a,b) return a.z<b.z or a.z==b.z and a.x<b.x end)
    out.width,out.depth=grid.width,grid.depth
    out.result_revision=copy.revision
    return out,copy
  end
  function L.apply(grid,receipt)
    if grid.revision~=receipt.revision or grid.width~=receipt.width or grid.depth~=receipt.depth then
      return nil,"STALE_INDUSTRY_PLATFORM"
    end
    for _,c in ipairs(receipt.changes) do grid.levels[c.id]=c.height end
    grid.revision=receipt.result_revision
    return true
  end
  return L
end
