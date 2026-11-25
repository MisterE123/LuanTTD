-- Pure projection from worker roadside bytes to native ground and objects.
return function(S,Sim,terrain,road_surface,reg,architecture,Details,Track,png,slope_collision)
  local V={}
  local entries={}
  for _,kind in ipairs({"trees","street_lights"}) do
    entries[kind]={}
    for bits in pairs(Details[kind]) do
      local variants={}
      entries[kind][bits]=variants
      local grades=bits==5 and {0,6,9} or bits==10 and {0,3,12} or {0}
      for _,grade in ipairs(grades) do
        local name=("roadside_%s_%d_%d"):format(kind,bits,grade)
        variants[grade]=architecture(name,name,"roadside_temperate_atlas")
      end
    end
  end
  local tram={barren={normal={},foundation={}},grass={normal={},foundation={}}}
  local Ground=dofile((core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core")
    .."/openttd/road_crossing_ground.lua")
  for class,families in pairs(tram) do
    local tex=png(class=="barren" and "rail_barren" or "grass2")
    families.normal.flat=reg("pure_tram_"..class,{tex,png("hill0"),png("grass_side")})
    families.foundation.flat=reg("pure_tram_"..class.."_retaining",
      {tex,png("hill0"),png("road_surface_retaining")})
    for _,grade in ipairs({3,6,9,12}) do
      for _,foundation in ipairs({"normal","foundation"}) do
        local name=("pure_tram_%s_%s_%d"):format(class,foundation,grade)
        local asset=(foundation=="foundation" and "bl_road_grade_foundation_" or "bl_land_")..grade..".obj"
        families[foundation][grade]=reg(name,{tex,png("road_surface_retaining"),png("road_surface_retaining")},{
          drawtype="mesh",mesh=asset,paramtype="light",sunlight_propagates=true,
          pointable=false,collision_box=slope_collision(grade),
        })
      end
    end
  end
  function V.tram_ground(t,grade,foundation)
    local variants=tram[Ground.pure_tram(t.roadside,t.roadworks)]
    return variants and variants[foundation=="none" and "normal" or "foundation"][grade==0 and "flat" or grade]
  end
  local barren={normal={},foundation={}}
  for bits=0,15 do
    barren.normal[bits],barren.foundation[bits]={},{}
    for quarter=0,3 do
      local name=("roadside_barren_%d_%d"):format(bits,quarter)
      local tex=png("roadside_barren_sheet")..("^[sheet:16x4:%d,%d"):format(bits,quarter)
      barren.normal[bits][quarter]=reg(name,{tex,png("hill0"),png("grass_side")})
      barren.foundation[bits][quarter]=reg(name.."_foundation",{tex,png("hill0"),png("road_surface_retaining")})
    end
  end
  local grades={paved={normal={},foundation={}},barren={normal={},foundation={}}}
  for material,family in pairs(grades) do
    for grade,bits in pairs({[3]=10,[12]=10,[6]=5,[9]=5}) do
      local cell=(bits==5 and 0 or 2)+(material=="paved" and 1 or 0)
      local tex=png("roadside_grade_sheet")..("^[sheet:4x1:%d,0"):format(cell)
      local base=("roadside_grade_%s_%d"):format(material,grade)
      for _,foundation in ipairs({"normal","foundation"}) do
        family[foundation][grade]=reg(base.."_"..foundation,{tex,
            png("road_surface_retaining"),png("road_surface_retaining")},{
          drawtype="mesh",mesh=(foundation=="foundation" and "bl_road_grade_foundation_" or "bl_land_")..grade..".obj",
          paramtype="light",sunlight_propagates=true,pointable=false,collision_box=slope_collision(grade)})
      end
    end
  end
  local function appearance(t)
    if t.roadworks then return t.roadworks=="grass" and "grass" or "paved" end
    return t.roadside
  end
  function V.is_paved(t)
    local material=appearance(t)
    return material==nil and t.road_town or material=="paved" or material=="street_lights" or material=="trees"
  end
  local function zone(foundation)
    return foundation~="none" and "foundation" or "normal"
  end
  function V.flat(t,bits,q,foundation)
    if appearance(t)=="barren" then return barren[zone(foundation)][bits][q] end
  end
  function V.grade(t,grade,foundation)
    local material=appearance(t)
    local family=grades[material] or (V.is_paved(t) and grades.paved)
    return family and family[zone(foundation)][grade] or nil
  end
  local function minimum_deck(id)
    local a
    local function add(layer, spans)
      local key=S[layer] and S[layer][id]
      local t=key and S[spans] and S[spans][key]
      if t and t.deck then a=a and math.min(a,t.deck) or t.deck end
    end
    add("bridge_above","stock_road_bridges")
    add("rail_bridge_above","stock_rail_spans")
    add("aqueduct_above","stock_aqueducts")
    return a
  end
  function V.node(t,id,x,y,z)
    if x%2~=1 or z%2~=1 or not entries[t.roadside] or t.roadworks or t.build~="road"
        or t.road_waypoint_id or t.level_crossing or t.station or t.road_tunnel_id or t.road_bridge_id then return end
    local grade,base=road_surface(id)
    if grade==nil or y~=base+1 then return end
    local rb=Sim.road_bits(S,id)
    local tb=t.tram and (t.tram.tram_bits or 0) or 0
    local all=Track.union(rb,tb)
    local family=entries[t.roadside][all]
    local variant=family and family[grade]
    if not variant then return end
    local shape,rawbase=terrain.tile(id)
    local max=rawbase+(shape>=16 and 2 or shape==0 and 0 or 1)
    return Details.points(t.roadside,rb,all,false,max,minimum_deck(id)) and variant or nil
  end
  return V
end
