-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 industry_cmd.cpp: CheckNewIndustry_*,
-- CheckIfFarEnoughFromConflictingIndustry and CheckIfIndustryIsAllowed.
-- Map coordinates are zero-based; the host supplies the stock town lookup.
local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local Geometry=dofile(dir.."industry_footprint_rc1.lua")
local M={}
local floor,max,abs=math.floor,math.max,math.abs
local u32=4294967296
local function max_distance(x,z,u,v) return max(abs(x-u),abs(z-v)) end
function M.conflicts(spec,x,z,placed)
  for _,kind in ipairs(spec.conflicts) do
    for _,p in ipairs(placed or {}) do
      if p.type==kind and max_distance(x,z,p.x,p.z)<=14 then
        return false,"INDUSTRY_TOO_CLOSE"
      end
    end
  end
  return true
end
function M.town(spec,x,z,town,placed,multiple)
  if not town then return false,"NO_TOWN" end
  if not multiple then
    for _,p in ipairs(placed or {}) do
      if p.type==spec.id and p.town==town.id then return false,"ONLY_ONE_ALLOWED_PER_TOWN" end
    end
  end
  if spec.behavior.Town1200More and town.population<1200 then
    return false,"CAN_ONLY_BE_BUILT_IN_TOWNS_WITH_POPULATION_OF_1200"
  end
  if spec.behavior.OnlyNearTown and max_distance(x,z,town.x,town.z)>9 then
    return false,"CAN_ONLY_BE_BUILT_NEAR_TOWN_CENTER"
  end
  return true
end
function M.scaled_edge(x,z,opts)
  local w,h=opts.width,opts.height
  local t=(z*w+x+1+w)%(w*h)
  local sx,sz=t%w,floor(t/w)
  local d=opts.oil_refinery_limit or 32
  local dx,dz=d*max(1,floor(w/256)),d*max(1,floor(h/256))
  local north=opts.freeform and 1 or 0
  return (sx-north)%u32<dx or (sz-north)%u32<dz
    or (w-2-sx)%u32<dx or (h-2-sz)%u32<dz
end
function M.anchor(kind,x,z,t,opts)
  assert(kind=="None" or kind=="Forest" or kind=="Refinery" or kind=="Farm" or kind=="Plantation"
    or kind=="Water" or kind=="Lumbermill" or kind=="BubbleGen" or kind=="OilRig","Unknown stock location test")
  if kind=="Forest" and opts.landscape=="arctic" and t.base<opts.highest_snowline+2 then
    return false,"FOREST_CAN_ONLY_BE_PLANTED"
  elseif kind=="Farm" and opts.landscape=="arctic" and t.base+2>=opts.highest_snowline then
    return false,"SITE_UNSUITABLE"
  elseif kind=="Plantation" and t.zone==1 then
    return false,"SITE_UNSUITABLE"
  elseif kind=="Water" and t.zone~=1 then
    return false,"CAN_ONLY_BE_BUILT_IN_DESERT"
  elseif kind=="Lumbermill" and t.zone~=2 then
    return false,"CAN_ONLY_BE_BUILT_IN_RAINFOREST"
  elseif kind=="BubbleGen" and t.base>4 then
    return false,"CAN_ONLY_BE_BUILT_IN_LOW_AREAS"
  elseif kind=="Refinery" and not opts.editor and not M.scaled_edge(x,z,opts) then
    return false,"CAN_ONLY_BE_POSITIONED"
  elseif kind=="OilRig" and not (opts.editor and opts.ignore) and
      (t.north~=0 or not M.scaled_edge(x,z,opts)) then
    return false,"CAN_ONLY_BE_POSITIONED"
  end
  return true
end
-- Vanilla CreateNewIndustryHelper through the final pool gate. No
-- drawing, payment or command mutation is allowed during these phases.
function M.quote(spec,layout,masks,x,z,board,opts,placed)
  local ok,why=M.conflicts(spec,x,z,placed)
  if not ok then return nil,why end
  local town=board.town(x,z)
  ok,why=M.town(spec,x,z,town,placed,opts.multiple)
  if not ok then return nil,why end
  local b=spec.behavior
  local cells
  cells,why=Geometry.tiles_free(layout,masks,x,z,{
    built_on_water=b.BuiltOnWater,only_in_town=b.OnlyInTown,
    town_1200=b.Town1200More,only_near_town=b.OnlyNearTown},board)
  if not cells then return nil,why end
  ok,why=M.anchor(spec.check,x,z,assert(board.tile(x,z)),opts)
  if not ok then return nil,why end
  local grading
  ok,grading=Geometry.slopes(cells,masks,opts.terragenesis,opts.generating_world,opts.ignore)
  if not ok then return nil,grading end
  local platform
  if opts.terragenesis and opts.generating_world and not opts.ignore then
    platform,why=board.platform(x,z,layout,cells,grading)
    if not platform then return nil,why or "SITE_UNSUITABLE" end
  end
  if board.can_allocate and not board.can_allocate() then return nil,"TOO_MANY_INDUSTRIES" end
  return {cells=cells,town=town.id,needs_grading=grading,platform=platform}
end
return M
