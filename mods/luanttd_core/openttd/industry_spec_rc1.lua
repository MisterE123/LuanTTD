-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 SetupCargoForClimate and GetActiveCargoLabel.
local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local Data=dofile(dir.."stock_industry_specs_rc1.lua")
local M={data=Data}
local index={temperate=0,arctic=1,tropic=2,toyland=3}
local by_climate={}
for climate,slots in pairs(Data.climate_slots) do
  local by={}
  for n,j in ipairs(slots) do
    local c=Data.default_cargo[j]
    if c[1] then by[c[1]]={id=n-1,definition=c} end
  end
  by_climate[climate]=by
end
function M.cargo(climate,label)
  if not label then return nil end
  local by=assert(by_climate[climate],"Unsupported stock climate")
  local mixed=Data.groups[label]
  if not mixed then return by[label] end
  for _,kind in ipairs(mixed) do
    if by[kind] then return by[kind] end
  end
end
local function slots(list,climate)
  local out={}
  for i,p in ipairs(list) do
    local c=M.cargo(climate,p[1])
    out[i]={cargo=c or false,value=p[2]}
  end
  return out
end
function M.get(kind,climate)
  local r=Data.industry[kind]
  if not r then return end
  local bit=2^assert(index[climate],"Unsupported stock climate")
  if math.floor(r[13]/bit)%2==0 then return end
  local behavior={}
  for _,flag in ipairs(r[14]) do behavior[flag]=true end
  return {kind=r[1],id=kind,cost_factor=r[2],procurement_probability=r[3],appearance=r[4],
    generation=r[5],map_colour=r[6],conflicts=r[7],check=r[8],produce=slots(r[9],climate),
    minimum=r[10],accept=slots(r[11],climate),life=r[12],climates=r[13],behavior=behavior}
end
return M
