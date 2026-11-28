-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 town_cmd.cpp AddAcceptedCargoOfHouse,
-- AddAcceptedCargoSetMask; table/town_land.h and table/cargo_const.h.
-- Vanilla types only; NewGRF overrides are not installed.
local here=debug and debug.getinfo(1,"S").source:match("^@(.*/)")
local path=here or (core and core.get_modpath("luanttd_core").."/openttd/") or "mods/luanttd_core/openttd/"
local data=dofile(path.."town_house_acceptance_data_rc1.lua")
local A={}
local masks={
  temperate={goods=true},
  arctic={goods=true,food=true},
  tropic={goods=true,food=true},
  toyland={candy=true,fizzy_drinks=true},
}
local function add(accept,always,cargo,amount)
  if not cargo or amount==0 then return end
  accept[cargo]=(accept[cargo] or 0)+amount
  always[cargo]=true
end
function A.add_to(accept,always,id,climate)
  local p=assert(data[id+1],"Unknown stock HouseID")
  local have=assert(masks[climate or "temperate"],"Unknown stock climate")
  add(accept,always,"passenger",p[1])
  add(accept,always,"mail",p[2])
  if p[4] and have[p[4]] then add(accept,always,p[4],p[3]) end
end
function A.eighths(id,cargo,climate)
  local p=data[id+1]
  if not p then return end
  if cargo=="passenger" then return p[1] end
  if cargo=="mail" then return p[2] end
  return cargo==p[4] and masks[climate or "temperate"][cargo] and p[3] or 0
end
-- The ordinary Temperate catchment reads one cargo at a time. Keep the
-- hot callbacks a single row lookup rather than materializing a vector.
function A.passenger(id) local p=data[id+1];return p and p[1] end
function A.mail(id) local p=data[id+1];return p and p[2] end
function A.goods(id) local p=data[id+1];return p and (p[4]=="goods" and p[3] or 0) end
return A
