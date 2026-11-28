-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 effectvehicle.cpp BubbleInit/BubbleTick
-- and industry_cmd.cpp TileLoopIndustry_BubbleGenerator.
-- The view may show different particles, but this source motion consumes
-- the shared simulation RNG and can activate the physical catcher tile.
local B={}
local spawn_x,spawn_y,spawn_z={11,0,-4,-14},{-4,-10,-4,1},{49,59,60,65}
local moves={
  { -- float_sw
    {0,0,1,0},{1,0,1,1},{0,0,1,0},{1,0,1,2},{1,4,0,0},
  },
  { -- float_ne
    {0,0,1,0},{-1,0,1,1},{0,0,1,0},{-1,0,1,2},{1,4,0,0},
  },
  { -- float_se
    {0,0,1,0},{0,1,1,1},{0,0,1,0},{0,1,1,2},{1,4,0,0},
  },
  { -- float_nw
    {0,0,1,0},{0,-1,1,1},{0,0,1,0},{0,-1,1,2},{1,4,0,0},
  },
  { -- burst
    {0,0,1,2},{0,0,1,7},{0,0,1,8},{0,0,1,9},{0,4,0,0},
  },
  { -- absorb
    {0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},
    {0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},
    {0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},
    {0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},
    {0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},
    {0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},
    {0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},
    {0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},
    {0,0,1,0},{0,0,1,1},{0,0,1,0},{0,0,1,2},{0,0,1,0},{0,0,1,1},{2,1,3,0},
    {1,1,3,1},{2,1,3,0},{1,1,3,2},{2,1,3,0},{1,1,3,1},{2,1,3,0},{1,0,1,2},
    {0,0,1,0},{1,0,1,1},{0,0,1,0},{1,0,1,2},{0,0,1,0},{1,0,1,1},{0,0,1,0},
    {1,0,1,2},{2,4,0,0},{0,0,0,10},{0,0,0,11},{0,0,0,12},{0,0,0,13},{0,0,0,14},
    {0,4,0,0},
  },
}
function B.new(x,y,direction,height)
  local n=direction+1
  x=x*16+spawn_x[n]
  y=y*16+spawn_y[n]
  return {x=x,y=y,z=height(x,y)+spawn_z[n],direction=direction,progress=0,
    movement=0,animation_state=0,frame=0}
end

function B.tick(v,random,catcher)
  v.progress=(v.progress+1)%256
  if v.progress%4~=0 then return true end
  local at
  if v.movement==0 then
    v.frame=v.frame+1
    if v.frame<3 then return true end
    v.movement=v.direction~=0 and random()%4+1 or 6
    at=0
  else
    at=v.animation_state+1
  end
  local step=assert(moves[v.movement][at+1])
  if step[2]==4 then
    if step[1]==0 then return false end
    if step[1]==1 then
      if v.z>180 or math.floor((random()%65536*96+48)/65536)==0 then v.movement=5 end
      at=0
    elseif step[1]==2 then
      at=at+1
      catcher(math.floor(v.x/16),math.floor(v.y/16))
    end
  end
  v.animation_state=at
  step=assert(moves[v.movement][at+1])
  v.x,v.y,v.z,v.frame=v.x+step[1],v.y+step[2],v.z+step[3],step[4]
  return true
end
return B
