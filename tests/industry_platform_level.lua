local base="mods/luanttd_core/openttd/"
local Terrain=dofile(base.."terrain.lua")
local Level=dofile(base.."industry_platform_level.lua")(Terrain)
local manifest={}
for fixture=1,24 do
  local function height(x,z)
    local d=math.abs(x-(10+fixture%3))+math.abs(z-(10+fixture%4))
    return math.max(1,4-math.floor(d/2))
  end
  local real=Terrain.new(23,19,height)
  local reference=Terrain.new(23,19,height)
  local target={x=6,z=6,width=9,height=8,level=fixture%2+2}
  local denied_count,allowed_count=0,0
  local function opts()
    return {validate_tile=function(_,x,z)
      if fixture%4==0 and x==8 and z==8 then return nil,"PROTECTED_TILE" end
      return 0
    end}
  end
  for z=7,14 do for x=7,15 do
    local h=Terrain.corner(reference,x,z)
    while h~=target.level do
      local up=h<target.level
      local cmd=Terrain.plan(reference,x,z,8,up,opts())
      if cmd then allowed_count=allowed_count+1; assert(Terrain.apply(reference,cmd))
      else denied_count=denied_count+1 end
      h=h+(up and 1 or -1)
    end
  end end
  local before=real.revision
  local receipt=Level.plan(real,target,opts)
  assert(receipt.revision==before and real.revision==before)
  for z=1,real.depth+1 do for x=1,real.width+1 do assert(Terrain.corner(real,x,z)==height(x,z)) end end
  assert(#receipt.commands==allowed_count and #receipt.failures==denied_count)
  assert(Level.apply(real,receipt))
  for i,value in ipairs(reference.levels) do assert(real.levels[i]==value) end
  assert(real.revision==reference.revision)
  local ok,why=Level.apply(real,receipt)
  if allowed_count>0 then assert(not ok and why=="STALE_INDUSTRY_PLATFORM") end
  manifest[#manifest+1]={allowed_count,denied_count}
end
assert(manifest[1][1]>0 and manifest[4][2]>0)
print("PASS 24 sparse industrial platform execution plans match direct row-major corner commands; no quote writes")
