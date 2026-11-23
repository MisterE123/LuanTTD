-- Luanti client-interest window, never a mask on simulation.
-- A sector covers 32 x 32 game tiles (64 x 64 Luanti nodes).
local M={SECTOR=64}
local floor=math.floor
function M.new()
  local I={}
  local eyes={}
  local function sector(x,z) return x..":"..z end
  function I.refresh(players)
    eyes={}
    for _,p in ipairs(players) do
      local at=p:get_pos()
      if at then eyes[#eyes+1]={x=at.x,z=at.z} end
    end
  end
  function I.near(pos,exists,enter,leave)
    if not pos then return false end
    local r=exists and (leave or 112) or (enter or 96)
    for _,p in ipairs(eyes) do
      local dx,dz=p.x-pos.x,p.z-pos.z
      if dx*dx+dz*dz<=r*r then return true end
    end
    return false
  end
  function I.sector(x,z)
    return sector(floor(x/M.SECTOR),floor(z/M.SECTOR))
  end
  function I.sectors(radius)
    local found={}
    local length=M.SECTOR
    for _,p in ipairs(eyes) do
      for z=floor((p.z-radius)/length),floor((p.z+radius)/length) do
        for x=floor((p.x-radius)/length),floor((p.x+radius)/length) do
          found[sector(x,z)]=true
        end
      end
    end
    return found
  end
  function I.each_tile(Sim,radius,visit)
    for key in pairs(I.sectors(radius)) do
      local sx,sz=key:match("^(%-?%d+):(%-?%d+)$")
      local length=M.SECTOR/2
      sx,sz=sx*length,sz*length
      for z=math.max(1,sz),math.min(Sim.H,sz+length-1) do
        for x=math.max(1,sx),math.min(Sim.W,sx+length-1) do visit(Sim.id(x,z)) end
      end
    end
  end
  return I
end
return M
