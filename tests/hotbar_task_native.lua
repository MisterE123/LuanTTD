-- Native graphical probe. All commands and windows are opened through
-- actual input; this helper only positions QA and observes the result.
local target,logged=nil,{}
local function marker(key,suffix)
  if logged[key] then return end
  logged[key]=true
  core.log("action","HOTBAR_TASK "..key..(suffix and " "..suffix or ""))
end
local original_form=core.show_formspec
core.show_formspec=function(n,form,def)
  if n=="ToolbarQA" and form=="luanttd_core:worker_depot" and def:find("Road",1,true) then
    marker("ROAD_SERVICE")
  end
  if n=="ToolbarQA" and form=="luanttd_core:worker_fleet" and
      def:find("All,Road,Rail,Water,Air,Tram",1,true) then
    marker("FLEET_FILTERS")
    if def:find("All,Road,Rail,Water,Air,Tram;2",1,true) and def:find("0 vehicles",1,true) then
      marker("FLEET_ROAD_READY")
    end
  end
  return original_form(n,form,def)
end
local function scan()
  local p=core.get_player_by_name("ToolbarQA")
  if not (p and authority and authority.status()=="owned") then core.after(.22,scan);return end
  local s=assert(OwnerCheckpoint and OwnerCheckpoint.read())
  if not target then
    for z=5,Sim.H-5 do
      for x=5,Sim.W-5 do
        local a=Sim.id(x,z)
        local row=s.tiles[a]
        local m,h=api.terrain.tile(a)
        if row and row.terrain~="water" and m==0 and h>=1 and not
            (row.stock_void or row.wood or row.house or row.site or row.build or row.stock_industry or row.stock_landmark or row.airfield
              or s.stock_farm_fields and s.stock_farm_fields[a]) then
          target={x=x,z=z,tile=a,h=h};break
        end
      end
      if target then break end
    end
    assert(target,"native baseline must offer one flat empty road-depot site")
  end
  if world.target(p)~=target.tile then
    p:set_pos({x=2*target.x+.5-3.0,y=target.h+3.8,z=2*target.z+.5+4.0})
    p:set_look_horizontal(math.atan2(-3,-4));p:set_look_vertical(math.atan2(4.77,5))
  end
  local function slot(key)
    local inv=p:get_inventory()
    for i=1,10 do if inv:get_stack("main",i):get_name()=="luanttd_core:menu_"..key then return i end end
  end
  local menu=world.menu(p)
  if menu=="home" and world.target(p)==target.tile then
    for k,id in pairs({ROAD="section_roads",RAIL="section_railworks",WATER="section_harbor",AIR="section_airfields",FLEET="section_fleet"}) do
      marker("HOME_"..k,assert(slot(id),id))
    end
  elseif menu=="roads" then
    marker("DEPOT_TOOL",assert(slot("road_depot")))
    marker("ROAD_OPEN",assert(slot("service_depot")))
    marker("ROAD_STOPS",assert(slot("road_station")))
    if s.tiles[target.tile].build=="road_depot" then marker("DEPOT_BUILT") end
  elseif menu=="railworks" then
    marker("RAIL_OPEN",assert(slot("service_depot")))
    assert(slot("rail_autotrack") and slot("rail_platform") and slot("rail_depot_tool"))
  elseif menu=="harbor" then
    marker("WATER_OPEN",assert(slot("service_depot")))
    assert(slot("ship_dock") and slot("ship_depot"))
  elseif menu=="airfields" then
    marker("AIR_OPEN",assert(slot("service_hangar")))
  elseif menu=="fleet" then
    marker("FLEET_LIST",assert(slot("company")))
  end
  core.after(.22,scan)
end
core.after(.4,scan)
