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
function E.step(s)
  for id,row in pairs(s.stock_effect_vehicles or {}) do
    if row.progress>0 then
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
