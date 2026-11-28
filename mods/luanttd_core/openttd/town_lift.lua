-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors, animated_tile.cpp and town_cmd.cpp
-- AnimateTile_Town. Stock house 0x04 is Temperate; 0x05 is Arctic.
local L={}
local floor=math.floor
local source=debug and debug.getinfo(1,"S").source:match("^@(.*/)town_lift%.lua$")
local Motion=dofile((source or (core and core.get_modpath("luanttd_core").."/openttd/") or
  "mods/luanttd_core/openttd/").."world_animation_rc1.lua")
function L.supports(h) return h and (h.id==0x04 or h.id==0x05) end
function L.new(hub) return {order={},states={},built={},sectors={},hub=hub} end
local function sector(x,z) return floor((x-1)/32)+128*floor((z-1)/32) end
function L.visible(a,Sim,tiles,x,z,w,h)
  if not a then return end
  local out={}
  for v=floor((z-1)/32),floor((z+h-2)/32) do
    for u=floor((x-1)/32),floor((x+w-2)/32) do
      for id in pairs(a.sectors[u+128*v] or {}) do
        local a,b=Sim.xy(id)
        if a>=x and a<x+w and b>=z and b<z+h then
          local t=tiles[id]
          local h=t and t.house and t.source_house
          if L.supports(h) and h.completed then out[id]=h.lift_position or 0 end
        end
      end
    end
  end
  return out
end
function L.install(a,id,Sim)
  local x,z=Sim.xy(id)
  local key=sector(x,z)
  local bucket=a.sectors[key]
  if not bucket then bucket={};a.sectors[key]=bucket end
  a.built[id]=key;bucket[id]=true
  L.add(a,id)
end
function L.add(a,id)
  local state=a.states[id]
  if a.hub then Motion.add(a.hub,id,"lift")
  elseif not state then a.order[#a.order+1]=id end
  a.states[id]="active"
end
function L.erase(a,id)
  local key=a.built[id]
  if key~=nil then
    local bucket=a.sectors[key]
    bucket[id],a.built[id]=nil,nil
    if not next(bucket) then a.sectors[key]=nil end
  end
  if a.hub then Motion.delete(a.hub,id,true) end
  if not a.states[id] then return end
  a.states[id]=nil
  for i,v in ipairs(a.order) do
    if v==id then
      a.order[i]=a.order[#a.order];a.order[#a.order]=nil
      return
    end
  end
end
function L.frame(a,id,tick,house,random,changed)
  if tick%4==0 then
    local h=house(id)
    if not L.supports(h) then
      if a.hub then a.states[id]=nil else a.states[id]="delete" end
    else
      local p=h.lift_position or 0
      local dest=h.lift_destination
      if dest==nil then
        repeat dest=floor(random()*7/4294967296) until dest~=1 and dest*6~=p
        h.lift_destination=dest
        h.lift_has_destination=true
      end
      p=p+(p<dest*6 and 1 or -1)
      h.lift_position=p
      if p==dest*6 then
        h.lift_destination,h.lift_has_destination=nil,nil
        if a.hub then a.states[id]=nil else a.states[id]="delete" end
      end
      if changed then changed(id,h) end
    end
  end
  return a.states[id]=="active"
end
function L.step(a,tick,house,random,changed)
  local index=1
  while index<=#a.order do
    local id=a.order[index]
    if a.states[id]~="active" then
      -- The original vector swaps the last entry into the gap. Its
      -- order is observable because each next tile can consume RNG.
      a.order[index]=a.order[#a.order];a.order[#a.order]=nil
      a.states[id]=nil
    else
      L.frame(a,id,tick,house,random,changed)
      index=index+1
    end
  end
end
return L
