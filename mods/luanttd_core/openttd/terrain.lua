-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors. No warranty.
-- See COPYING.OpenTTD.md and PORTING.md at the game root.
-- Ported to Lua on 2026-11-22 from OpenTTD 14.1 src/terraform_cmd.cpp:
-- TerraformAddDirtyTileAround, TerraformTileHeight, and the model,
-- validation, and height-commit portions of CmdTerraformLand.
-- A game adapter supplies tile-class, infrastructure and company state.
-- OpenTTD "north corner" of tile (x,z) is corner (x,z) in this grid.
-- Logical tile x,z start at 1. The inclusive far corner is (width+1,depth+1).
local path = debug and debug.getinfo(1,"S").source
local sibling = path and path:match("^@(.*/)terrain%.lua$")
local slope = dofile((sibling or (core and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/").."slope.lua")
local T={}
local floor,abs=math.floor,math.abs
local function int(value)
  return type(value)=="number" and value==floor(value)
end
local function index(g,x,z)
  if not int(x) or not int(z) or x<1 or x>g.width+1 or z<1 or z>g.depth+1 then return nil end
  return (z-1)*(g.width+1)+x
end
local function xyz(g,i)
  return (i-1)%(g.width+1)+1,floor((i-1)/(g.width+1))+1
end
local function tile(g,x,z)
  return index(g,x,z) and x<=g.width and z<=g.depth
end

function T.new(width,depth,initialize,opts)
  opts=opts or {}
  assert(int(width) and width>=1 and int(depth) and depth>=1,"positive terrain dimensions required")
  local limit=opts.max_height or 255
  assert(int(limit) and limit>=0 and limit<=255,"map height limit must be between 0 and 255")
  local g={
    width=width,depth=depth,levels={},revision=0,max_height=limit,
    freeform_edges=opts.freeform_edges~=false,
    unit_cost=opts.unit_cost or 1,
  }
  for z=1,depth+1 do
    if opts.pulse and z%16==0 then opts.pulse((z-1)/depth) end
    for x=1,width+1 do
      local value=initialize and initialize(x,z) or 0
      assert(int(value) and value>=0 and value<=limit,"invalid initial corner height")
      local id=index(g,x,z)
      assert(x==1 or abs(value-g.levels[id-1])<=1,"initial X edge has height difference over one")
      assert(z==1 or abs(value-g.levels[id-width-1])<=1,"initial Z edge has height difference over one")
      g.levels[id]=value
    end
  end
  return g
end

function T.corner(g,x,z,plan)
  local id=index(g,x,z)
  if not id then return nil end
  return (plan and plan.levels[id]) or g.levels[id]
end

function T.tile(g,x,z,plan)
  -- All four corners are in bounds once the tile is in bounds. Reuse its
  -- single row-major address; preserve the same shared-corner ordering
  -- and the same staged-plan fallback as T.corner.
  local i=index(g,x,z)
  if not i or x>g.width or z>g.depth then return nil end
  local stride=g.width+1
  local heights=g.levels
  local hn,hw,he,hs=heights[i],heights[i+1],heights[i+stride],heights[i+stride+1]
  if plan then
    local staged=plan.levels
    hn,hw,he,hs=staged[i] or hn,staged[i+1] or hw,staged[i+stride] or he,staged[i+stride+1] or hs
  end
  local mask,base=slope.classify(hn,hw,he,hs)
  return mask,base,math.max(hn,hw,he,hs)
end

-- Field writes remember their exact shared-corner surface. For each
-- legal sampled shape the four normalized corner heights are unique.
local native_corners={}
for n=0,2 do for w=0,2 do for e=0,2 do for s=0,2 do
  if math.min(n,w,e,s)==0 and slope.valid(n,w,e,s) then
    local mask=slope.classify(n,w,e,s)
    assert(not native_corners[mask])
    native_corners[mask]={n,w,e,s}
  end
end end end end
function T.matches(g,x,z,expected_mask,expected_base)
  local levels=native_corners[expected_mask]
  local i=levels and type(expected_base)=="number" and index(g,x,z)
  if i and x<=g.width and z<=g.depth then
    local heights,stride=g.levels,g.width+1
    if heights[i]==expected_base+levels[1] and heights[i+1]==expected_base+levels[2]
       and heights[i+stride]==expected_base+levels[3] and heights[i+stride+1]==expected_base+levels[4] then return true end
  end
  local mask,base=T.tile(g,x,z)
  return mask==expected_mask and base==expected_base
end

function T.normalized_height(mask,base,u,v)
  if not mask then return nil end
  return base+slope.surface(u,v,mask)
end
function T.height(g,x,z,u,v,plan)
  local mask,base=T.tile(g,x,z,plan)
  return T.normalized_height(mask,base,u,v)
end

-- opts (all optional):
-- max_height: active map setting, bounded to the serialized grid's maximum.
-- freeform_edges: override the map setting for this invocation.
-- unit_cost: current PR_TERRAFORM (money, once per recursive invocation).
-- bridge_height(x,z): return height of overhead bridge deck or nil.
-- max_bridge_height: construction.max_bridge_height, default 12.
-- tunnel_in_way(x,z,new_min): return true if lowering intersects a tunnel.
-- validate_tile(pass,x,z,mask,base,maximum,plan) -> extra numeric cost or
-- nil,error_code. Runs in upstream order (ascending tile index, twice);
-- must not mutate grid; callers may keep pass-local staging in their closure.
-- void(x,z): return true to skip infrastructure and type checks.
-- terraform_limit: company remaining quota (integer count of distinct corners).
-- Storage, preview atomicity and phase callback signatures are Bayline adapters.
function T.plan(g,x,z,mask,up,opts)
  opts=opts or {}
  if not tile(g,x,z) or not int(mask) or mask<1 or mask>15 then return nil,"INVALID_SELECTION" end
  local freeform=opts.freeform_edges
  if freeform==nil then freeform=g.freeform_edges end
  local limit=math.min(opts.max_height or g.max_height,g.max_height)
  local price=opts.unit_cost or g.unit_cost
  local direction=up and 1 or -1
  local plan={revision=g.revision,width=g.width,depth=g.depth,levels={},dirty={},changes={},cost=0}
  local dirty={}
  local function mark(tx,tz)
    if tile(g,tx,tz) then dirty[index(g,tx,tz)]=true end
  end
  local function raise(px,pz,height)
    if height<0 then return nil,"ALREADY_AT_SEA_LEVEL" end
    if height>limit then return nil,"TOO_HIGH" end
    if height==T.corner(g,px,pz,plan) then return nil,"NO_EFFECT" end
    if not freeform and (px<=2 or pz<=2 or px>=g.width or pz>=g.depth) then
      return nil,"TOO_CLOSE_TO_EDGE",px==2 and 1 or px,pz==2 and 1 or pz
    end
    mark(px,pz-1)
    mark(px-1,pz-1)
    mark(px-1,pz)
    mark(px,pz)
    plan.levels[index(g,px,pz)]=height
    plan.cost=plan.cost+price

    -- OpenTTD uses cumulative offsets SE, NW, SW, NE; coordinates below
    -- are equivalent, except they do not wrap around a rectangular map.
    for i=1,4 do
      local nx=px+(i==1 and 1 or (i==2 and -1 or 0))
      local nz=pz+(i==3 and 1 or (i==4 and -1 or 0))
      local cur=T.corner(g,nx,nz,plan)
      if cur then
        local diff=height-cur
        if abs(diff)>1 then
          local ok,err,ex,ez=raise(nx,nz,height+(diff<0 and 1 or -1))
          if not ok then return nil,err,ex,ez end
        end
      end
    end
    return true
  end

  -- Same W, S, E, N corner order as CmdTerraformLand; take the starting
  -- heights from the original board, not the partially edited plan.
  for _,q in ipairs({{1,0,1},{1,1,2},{0,1,4},{0,0,8}}) do
    if floor(mask/q[3])%2==1 then
      local px,pz=x+q[1],z+q[2]
      local ok,err,ex,ez=raise(px,pz,T.corner(g,px,pz)+direction)
      if not ok then return nil,err,ex,ez end
    end
  end
  local ids={}
  for id in pairs(dirty) do ids[#ids+1]=id end
  table.sort(ids)
  for _,id in ipairs(ids) do
    local px,pz=xyz(g,id)
    plan.dirty[#plan.dirty+1]={x=px,z=pz}
  end
  ids={}
  for id in pairs(plan.levels) do ids[#ids+1]=id end
  table.sort(ids)
  for _,id in ipairs(ids) do
    local px,pz=xyz(g,id)
    plan.changes[#plan.changes+1]={x=px,z=pz,height=plan.levels[id]}
  end
  for pass=0,1 do
    for _,d in ipairs(plan.dirty) do
      if not opts.void or not opts.void(d.x,d.z) then
        local mask,lo,hi=T.tile(g,d.x,d.z,plan)
        if pass==0 then
          local deck=opts.bridge_height and opts.bridge_height(d.x,d.z)
          if deck then
            if up and deck<=hi then return nil,"MUST_DEMOLISH_BRIDGE_FIRST",d.x,d.z end
            if not up and deck>lo+(opts.max_bridge_height or 12) then
              return nil,"BRIDGE_TOO_HIGH_AFTER_LOWER_LAND",d.x,d.z
            end
          end
          if not up and opts.tunnel_in_way and opts.tunnel_in_way(d.x,d.z,lo) then
            return nil,"EXCAVATION_WOULD_DAMAGE_TUNNEL",d.x,d.z
          end
        end
        if opts.validate_tile then
          local cost,err=opts.validate_tile(pass,d.x,d.z,mask,lo,hi,plan)
          if cost==nil then return nil,err or "TILE_REJECTED",d.x,d.z end
          if pass==1 then plan.cost=plan.cost+cost end
        end
      end
    end
  end
  if opts.terraform_limit and #plan.changes>opts.terraform_limit then return nil,"TERRAFORM_LIMIT_REACHED" end
  return plan
end

function T.apply(g,plan)
  if plan.revision~=g.revision or plan.width~=g.width or plan.depth~=g.depth then
    return nil,"STALE_TERRAIN_PLAN"
  end
  for _,v in ipairs(plan.changes) do g.levels[index(g,v.x,v.z)]=v.height end
  g.revision=g.revision+1
  return true
end

return T
