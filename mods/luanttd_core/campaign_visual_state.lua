-- Sparse, disposable state for the existing node painter. It deliberately
-- excludes company balances, fleets, commands, and the simulation clock.
return function(Sim,baseline)
  local F={}
  local keep={"stock_generated_profile","stock_coastal_flood","road_economy","road_mail","road_stock_clock"}
  local metadata={}
  for _,key in ipairs(keep) do metadata[key]=baseline[key] end
  local current=baseline
  local proxy=setmetatable({},{
    __index=function(_,k) return current[k] end,
    __newindex=function() error("renderer cannot mutate campaign state") end,
  })
  F.state=proxy
  function F.accept(projection)
    local state={tiles={},sites={},stations={},fleet={},topology=0,river_directions={},paint_tops={},front_steps={},rail_diagonal={},rail_canopy={},rail_wire={},
      bridge_above={},stock_road_bridges={},stock_road_tunnels={},stock_rail_spans={},
      corner_grid={width=Sim.W,depth=Sim.H,levels={},revision=0,max_height=255}}
    for key,value in pairs(metadata) do state[key]=value end
    local windows=projection.windows()
    for _,receipt in ipairs(windows) do
      local w=receipt.value
      for _,row in ipairs(w.tiles) do
        state.tiles[row.id]=row.surface
        state.paint_tops[row.id]=math.max(row.top or 0,row.surface.h or 0)+3
        state.front_steps[row.id]=row.front_steps
        state.rail_diagonal[row.id],state.rail_canopy[row.id],state.rail_wire[row.id]=row.rail_diagonal,row.rail_canopy,row.rail_wire
        if row.river_direction then state.river_directions[row.id]=row.river_direction end
      end
      for dz=0,w.height do
        for dx=0,w.width do
          local h=w.corners:byte(1+dz*(w.width+1)+dx)
          local idx=(w.z+dz-1)*(Sim.W+1)+w.x+dx
          state.corner_grid.levels[idx]=h
        end
      end
      for name,records in pairs(w.registries or {}) do
        local target=state[name] or {};state[name]=target
        for key,record in pairs(records) do target[key]=record end
      end
      state.topology=math.max(state.topology,receipt.revision or 0)
    end
    local function rise(id,spans,key)
      local p=key and spans and spans[key]
      local y=p and (p.deck or p.base)
      if y then state.paint_tops[id]=math.max(state.paint_tops[id],y+3) end
    end
    local aqueducts=state.stock_aqueducts
    for id,t in pairs(state.tiles) do
      -- Heights of anchors, not mesh extents. The three-node margin
      -- covers sloped track and power/bridge-wire overlay anchors.
      rise(id,state.stock_road_bridges,t.road_bridge_id or state.bridge_above[id])
      rise(id,state.stock_road_tunnels,t.road_tunnel_id)
      rise(id,state.stock_rail_spans,t.rail_span_id or state.rail_bridge_above and state.rail_bridge_above[id])
      rise(id,aqueducts,t.ship and t.ship.aqueduct or state.aqueduct_above and state.aqueduct_above[id])
      local field=state.stock_farm_fields and state.stock_farm_fields[id]
      if field then state.paint_tops[id]=math.max(state.paint_tops[id],field.base+3) end
      if t.level_crossing then state.paint_tops[id]=math.max(state.paint_tops[id],t.level_crossing.top+3) end
    end
    if state.signals then state.stock_rail_dispatch={signals={records=state.signals}} end
    current=state
  end
  return F
end
