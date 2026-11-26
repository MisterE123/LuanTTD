-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: industry_cmd.cpp TileLoop_Industry,
-- AnimateMineTower, AnimatePowerPlantSparks, and AnimateOilWell.
-- Operates on completed vanilla tiles after the cargo-distribution
-- branch. The native owner supplies the shared random word and phase.
local M={MINE_REST=0,MINE_RUN=1,POWER_SPARKS=10,OIL_REST=29,OIL_FIRST=30,OIL_LAST=32}
local floor=math.floor
local function chance(n,random)
  return floor(((random()%65536)*n+floor(n/2))/65536)==0
end

-- GFX/animation byte and registration are independent in the source:
-- an already animated power tile can have another ambient sound draw.
function M.visit(t,tick,random)
  local g=t.gfx
  local low=tick%2048<1024
  if g==M.MINE_REST and low then
    if chance(2,random) then
      t.gfx,t.animation_frame,t.animated=M.MINE_RUN,0x80,true
    end
  elseif g==M.MINE_RUN and low then
    t.gfx,t.completed,t.stage,t.animated=M.MINE_REST,true,3,nil
    return true
  elseif g==M.POWER_SPARKS then
    if chance(3,random) then t.animated=true;return false,true end
  elseif g==M.OIL_REST and chance(6,random) then
    t.gfx,t.animation_frame,t.animated=M.OIL_FIRST,0,true
  end
  return false,false
end

function M.animate(t,tick,random)
  if not t.animated then return false,false end
  local gfx,frame=t.gfx,t.animation_frame or 0
  if gfx==M.POWER_SPARKS then
    if tick%4~=0 then return false,false end
    if frame==6 then t.animation_frame,t.animated=0,nil
    else t.animation_frame=frame+1 end
    return true,false
  end
  if gfx>=M.OIL_FIRST and gfx<=M.OIL_LAST then
    if tick%8~=0 then return false,false end
    local stop=chance(7,random)
    frame=frame+1
    if frame==4 then
      frame,gfx=0,gfx+1
      if gfx>M.OIL_LAST then
        if stop then
          t.gfx,t.stage,t.animated=M.OIL_REST,3,nil
          return true,false
        end
        gfx=M.OIL_FIRST
      end
    end
    t.gfx,t.animation_frame=gfx,frame
    return true,false
  end
  if gfx~=M.MINE_RUN then return false,false end
  local phase=tick%2048-1024
  if phase<0 then return false,false end
  local noise=false
  if phase<0x1A0 then
    if phase<0x20 or phase>=0x180 then
      if frame%128<64 then frame=frame+64;t.animation_frame=frame;noise=true end
      if phase%8~=0 then return false,noise end
    elseif phase%4~=0 then return false,false end
    frame=(frame+1)%256
    if frame%128<64 then frame=frame+64 end
    t.animation_frame=frame>0xC2 and 0xC0 or frame
    return true,noise
  end
  if phase>=0x200 and phase<0x3A0 then
    local step=(phase<0x220 or phase>=0x380) and 8 or 4
    if phase%step~=0 then return false,false end
    if frame%128>=64 then frame=frame-64 end
    frame=(frame-1)%256
    t.animation_frame=frame<0x80 and 0x82 or frame
    return true,false
  end
  return false,false
end
return M
