-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: industry_cmd.cpp TileLoop_Industry,
-- AnimateMineTower, AnimatePowerPlantSparks, and AnimateOilWell.
-- Operates on completed vanilla tiles after the cargo-distribution
-- branch. The native owner supplies the shared random word and phase.
local M={MINE_REST=0,MINE_RUN=1,POWER_SPARKS=10,OIL_REST=29,OIL_FIRST=30,OIL_LAST=32,
  COPPER_REST=47,COPPER_RUN=48,COPPER_SMOKE=49,GOLD_REST=79,GOLD_RUN=88,
  TOY_FACTORY=143,PLASTIC_FIRST=148,PLASTIC_LAST=155,BUBBLE_GENERATOR=161,BUBBLE_CATCHER=162,
  TOFFEE=165,SUGAR=174}
local towers={[M.MINE_REST]=M.MINE_RUN,[M.COPPER_REST]=M.COPPER_RUN,[M.GOLD_REST]=M.GOLD_RUN}
local tower_rest={[M.MINE_RUN]=M.MINE_REST,[M.COPPER_RUN]=M.COPPER_REST,[M.GOLD_RUN]=M.GOLD_REST}
local floor=math.floor
local function chance(n,random)
  return floor(((random()%65536)*n+floor(n/2))/65536)==0
end

-- GFX/animation byte and registration are independent in the source:
-- an already animated power tile can have another ambient sound draw.
function M.visit(t,tick,random,firm)
  local g=t.gfx
  local low=tick%2048<1024
  if towers[g] and low then
    if chance(2,random) then
      t.gfx,t.animation_frame,t.animated=towers[g],0x80,true
    end
  elseif tower_rest[g] and low then
    t.gfx,t.completed,t.stage,t.animated=tower_rest[g],true,3,nil
    return true
  elseif g==M.POWER_SPARKS then
    if chance(3,random) then t.animated=true;return false,true end
  elseif g==M.OIL_REST and chance(6,random) then
    t.gfx,t.animation_frame,t.animated=M.OIL_FIRST,0,true
  elseif g==M.COPPER_SMOKE then
    return false,false,{effect="copper_smoke"}
  elseif g==M.TOY_FACTORY and firm and firm.was_cargo_delivered then
    firm.was_cargo_delivered=false
    t.animation_loop,t.animated=0,true
  elseif g==M.BUBBLE_GENERATOR then
    return false,true,{effect="bubble",direction=random()%4}
  elseif g==M.TOFFEE then
    t.animated=true
  elseif g==M.SUGAR and chance(3,random) then
    t.animated=true
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
  if gfx>=M.PLASTIC_FIRST and gfx<=M.PLASTIC_LAST then
    if tick%4~=0 then return false,false end
    t.gfx=gfx<M.PLASTIC_LAST and gfx+1 or M.PLASTIC_FIRST
    return true,false
  end
  if gfx==M.TOY_FACTORY then
    if tick%2~=0 then return false,false end
    frame=(frame+1)%256
    local sound=frame==1 or frame==23 or frame==28
    if frame>=50 then
      frame=0
      local n=(t.animation_loop or 0)+1
      if n>=8 then n=0;t.animated=nil end
      t.animation_loop=n
    end
    t.animation_frame=frame
    return true,sound
  end
  if gfx==M.SUGAR or gfx==M.TOFFEE or gfx==M.BUBBLE_CATCHER then
    if tick%(gfx==M.TOFFEE and 4 or 2)~=0 then return false,false end
    local next_frame=(frame+1)%256
    local sound=gfx==M.SUGAR and (next_frame%8==2 or next_frame%8==6)
      or gfx==M.TOFFEE and frame<70 and frame%14==0
    local limit=gfx==M.SUGAR and 96 or gfx==M.TOFFEE and 70 or 40
    if next_frame>=limit then next_frame=0;t.animated=nil end
    t.animation_frame=next_frame
    return true,sound
  end
  if not tower_rest[gfx] then return false,false end
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
