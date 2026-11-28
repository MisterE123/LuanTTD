-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 industry_cmd.cpp CreateChimneySmoke, effectvehicle.cpp
-- ChimneySmokeInit/Tick. Physical pool occupancy is needed even when the
-- client draws a different particle effect or its viewport is elsewhere.
local E={}
function E.add(s,id,tile,word)
  local effects=s.stock_effect_vehicles
  if not effects then effects={};s.stock_effect_vehicles=effects end
  assert(effects[id]==nil)
  effects[id]={tile=tile,frame=word%8,progress=math.floor(word/65536)%8}
end
-- Non-chimney cases from effectvehicle.cpp SmokeTick, ExplosionLargeTick
-- and ExplosionSmallTick: 5 smoke frames, 16 large and 12 small.
local timed={aircraft_smoke={72,12},explosion_large={64,0},explosion_small={48,0}}
function E.add_timed(s,id,kind,x,y,z,creator,duration)
  local effects=s.stock_effect_vehicles
  if not effects then effects={};s.stock_effect_vehicles=effects end
  assert(effects[id]==nil)
  local t=kind=="ship_smoke" and {assert(duration),0} or assert(timed[kind])
  -- If the higher slot is still ahead of the creator inside Vehicle::Iterate,
  -- it receives its first tick this frame; a lower slot waits until next.
  local elapsed=id>creator and 1 or 0
  effects[id]={kind=kind,x=x,y=y,z=z,remaining=t[1]-elapsed,progress=t[2]+elapsed}
end
function E.step(s)
  for id,row in pairs(s.stock_effect_vehicles or {}) do
    if row.kind then
      row.remaining,row.progress=row.remaining-1,row.progress+1
      if row.remaining==0 then s.stock_effect_vehicles[id]=nil
      elseif row.kind=="aircraft_smoke" and row.progress%4==0 then row.y=row.y+1 end
    elseif row.progress>0 then
      row.progress=row.progress-1
    elseif s.tiles[row.tile].stock_industry then
      row.frame=(row.frame+1)%8
      row.progress=7
    else
      s.stock_effect_vehicles[id]=nil
    end
  end
end
return E
