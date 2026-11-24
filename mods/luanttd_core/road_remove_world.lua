-- Plain public road layer adapter for the stock RemoveRoadLong kernel.
-- Special structures and ownership/rating rules have their own hooks.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Slope=dofile(mod.."/openttd/road_slope.lua")
local Sweep=dofile(mod.."/openttd/road_remove_long.lua")
return function(Sim,Terrain,rules)
  local W={}
  local board={xy=Sim.xy}
  function board.next(id,axis) return Sim.adjacent(id,axis==0 and 2 or 3) end
  local function count(bits)
    local n=0
    while bits>0 do n=n+bits%2;bits=math.floor(bits/2) end
    return n
  end
  local function quote_tile(s,owner,id,wanted,ctx,journal)
    local tile=s.tiles[id]
    if not tile or tile.stock_void then return nil,"NO_ROAD" end
    if tile.build~="road" or tile.level_crossing or tile.road_bridge_id or tile.road_tunnel_id
        or tile.station or tile.stop_axis or tile.road_stop_pair then
      if rules.special then return rules.special(s,owner,id,tile,wanted,ctx) end
      return nil,"NOT_PLAIN_ROAD"
    end
    if (tile.roadtype or 0)~=0 or Sim.road_bits(s,id)==0 then return nil,"NO_ROAD" end
    if not rules.occupied then return nil,"OCCUPANCY_UNKNOWN" end
    if rules.occupied(s,id,ctx) then return nil,"VEHICLE_IN_THE_WAY" end
    if tile.road_town then
      if not rules.town then return nil,"TOWN_REFUSES" end
      local allowed,why=rules.town(s,owner,id,wanted,journal)
      if not allowed then return nil,why or "TOWN_REFUSES" end
    elseif tile.owner and tile.owner~=owner then return nil,"OWNED_BY" end
    if tile.roadworks then return nil,"ROAD_WORKS_IN_PROGRESS" end
    local x,z=Sim.xy(id)
    local shape=Terrain.tile(s.corner_grid,x,z)
    if shape==nil then return nil,"PARAMETERS" end
    local other=tile.tram and tile.tram.bits or tile.tram_bits or 0
    local edit,why=Slope.remove(shape,wanted,Sim.road_bits(s,id),other,rules.build_on_slopes~=false)
    if not edit then return nil,why end
    edit.id,edit.cost,edit.under=id,count(edit.removed)*40+(edit.foundation and 250 or 0),other
    edit.tool,edit.build="remove",edit.road_bits==0 and "land" or "road"
    return edit
  end
  function W.plan(s,owner,first,last,axis,start_half,end_half)
    if not s.corner_grid or not s.tiles[first] or not s.tiles[last] or not s.companies[owner] then
      return nil,"PARAMETERS"
    end
    local x,z=Sim.xy(first)
    local u,v=Sim.xy(last)
    if math.abs(x-u)+math.abs(z-v)>=128 then return nil,"ROAD_DRAG_TOO_LONG" end
    local req,why=Sweep.request(board,first,last,axis,start_half,end_half)
    if not req then return nil,why end
    local ctx=rules.context and rules.context(s)
    local function run(journal)
      return function(id,bits) return quote_tile(s,owner,id,bits,ctx,journal) end
    end
    if rules.town then
      local has_town
      for _,edge in ipairs(req) do
        local t=s.tiles[edge.tile]
        if t and t.road_town and t.build=="road" then has_town=true;break end
      end
      if has_town then
        -- RC1 preflight has a shadow town ledger but its map doesn't
        -- change. CmdNoTest allows execution to see earlier removals as
        -- the line is worked from the lowest tile index to the highest.
        local initial,invalid=Sweep.sweep(req,run({ratings={},road={}}))
        if not initial then return nil,invalid end
        local journal={ratings={},road={}}
        local actual,why=Sweep.sweep(req,run(journal),true,s.companies[owner].cash,function(edit)
          journal.road[edit.id]=edit.road_bits
        end)
        if not actual then return nil,why end
        if #actual.changes==0 then return nil,"NOT_ENOUGH_CASH" end
        actual.ratings=journal.ratings
        return actual
      end
    end
    return Sweep.sweep(req,run())
  end
  function W.apply_plain(s,edit)
    local t=s.tiles[edit.id]
    if edit.road_bits==0 then
      t.build,t.road_bits,t.roadtype,t.road_town=nil,nil,nil,nil
      t.owner=t.tram and t.tram.owner or nil
    else
      t.road_bits=edit.road_bits
    end
    -- Removing any road pavement clears its own one-way bits. The
    -- untouched tram descriptor, when present, is not rewritten.
    t.road_disallowed,t.disallowed=nil,nil
  end
  return W
end
