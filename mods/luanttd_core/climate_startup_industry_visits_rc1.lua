-- SPDX-License-Identifier: GPL-2.0-only
-- Vanilla RC1 MakeIndustryTileBigger and TileLoop_Industry, during the
-- pregame landscape visits. No vehicle animation runs in this phase.
return function(Sim,Terrain,s)
  local dir=(core and core.get_modpath and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
  local function o(n)return dofile(dir.."openttd/"..n..".lua")end
  local Rules,Layout=o("industry_machinery_rc1"),o("stock_industry_layouts_rc1")
  local Fields=o("farm_factory_fields")(o("coal_industry")())
  local FieldWorld=dofile(dir.."farm_factory_world.lua")(Sim,Terrain,nil,Fields)
  local records,by_id={},{}
  for _,firm in ipairs(assert(s.stock_worldgen_climate_firms)) do
    by_id[firm.id]=firm
    for _,tile in ipairs(firm.cells) do records[Sim.id(tile.x+1,tile.z+1)]={tile,firm} end
  end
  local Field={}
  function Field.field_board(state) return FieldWorld.field_board(state,{industries=by_id,exact_grid=true}) end
  function Field.field(state,id) return FieldWorld.field(state,id) end
  local M={}
  local function random() return Sim.stock_random_u32(s) end
  local function reset_stage(t)
    t.completed,t.stage,t.construction_counter=false,0,0
  end
  function M.visit(id,tick)
    local r=records[id]
    if not r then return false end
    local t,firm=r[1],r[2]
    if not t.completed then
      local count=t.construction_counter+1
      if count~=4 then t.construction_counter=count;return false end
      t.stage,t.construction_counter=t.stage+1,0
      random() -- TriggerIndustryTileAnimation_ConstructionStageChanged
      if t.stage==3 then
        t.completed=true
        if t.gfx==8 then
          -- A fresh unplayed map has room for this puff. Its sprite phase
          -- consumes one word even though the controlled board has no art.
          t.stock_chimney_start=random()
        elseif t.gfx==Rules.TOY_FACTORY or t.gfx==Rules.BUBBLE_CATCHER or t.gfx==Rules.TOFFEE then
          t.animation_frame,t.animation_loop=0,0
        elseif t.gfx>=Rules.PLASTIC_FIRST and t.gfx<=Rules.PLASTIC_LAST then
          t.animated=true
        end
      end
      return true
    end
    -- No revenue or industry production ticks occur between generation
    -- and the initial landscape. There are no offered cargo packets here.
    random() -- TriggerIndustryTileAnimation(TileLoop)
    local next=Layout.anim_next[t.gfx]
    if next~=nil then reset_stage(t);t.gfx=next;return true end
    local g,f,a=t.gfx,t.animation_frame,t.animated
    local changed,_,fx=Rules.visit(t,tick,random,firm)
    if fx then
      M.events=M.events or {}
      M.events[#M.events+1]={id=id,tick=tick,effect=fx.effect,direction=fx.direction}
    end
    return changed or t.gfx~=g or t.animation_frame~=f or t.animated~=a
  end
  return M,Field
end
