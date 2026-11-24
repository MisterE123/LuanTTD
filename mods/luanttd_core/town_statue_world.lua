-- TownActionBuildStatue's host adapter. Own the entire transaction in the
-- authority worker; no scene or preview state can buy the council action.
return function(Sim,Terrain,Stock)
  local M={}
  local function coordinate(s,id)
    local t=s.tiles[id]
    if not t then return end
    local x,z=Sim.xy(id)
    return t,Terrain.tile(s.corner_grid,x,z)
  end
  local function make_board(s,growth)
    return {
      width=Sim.W,depth=Sim.H,
      tile=function(n)
        local id=n+1
        local t,slope=coordinate(s,id)
        if not t or not slope or t.stock_void then return {class="void",slope=0} end
        local bridge=s.bridge_above and s.bridge_above[id] or s.rail_bridge_above and s.rail_bridge_above[id]
          or s.aqueduct_above and s.aqueduct_above[id]
        local class="obstruction"
        if not (t.build or t.owner or t.site or t.stock_industry or t.stock_landmark or t.stock_object or
            t.ship or t.airfield or t.tram or t.rail_tracks or t.level_crossing or t.terrain=="water" or
            s.tunnel_below and s.tunnel_below[id] or s.rail_tunnel_below and s.rail_tunnel_below[id]) then
          class=t.house and "house" or t.wood and "trees" or "clear"
        end
        return {class=class,slope=slope,bridge_above=bridge}
      end,
      can_clear=function(n,t)
        if t.class~="house" then return true end
        local actual=s.tiles[n+1]
        -- LandscapeClear of a house acts on the whole stock footprint.
        if not actual.source_house then return false end
        local parts=growth.footprint(s,actual.source_house)
        return parts~=nil
      end,
    }
  end
  function M.quote(s,owner,id,growth)
    local mapped=s.sites[id]
    local company=s.companies[owner]
    local town=s.stock_town_growth and s.stock_town_growth.towns[id]
    if not (company and town and mapped and s.corner_grid and mapped.kind=="town") then
      return {why="Town statue is unavailable."}
    end
    local existing=town.statues and town.statues[owner]
    if existing then return {existing=existing,cost=Stock.price()} end
    local offer,why=Stock.quote(make_board(s,growth),{center=mapped.tile-1},company,{
      unwanted=town.unwanted and (town.unwanted[owner] or 0)>0})
    if not offer then
      return {cost=Stock.price(),why=why=="STATUE_NO_SUITABLE_PLACE" and
        "No suitable plot in this town." or "The council is not offering this action."}
    end
    return {tile=offer.id+1,cost=offer.cost,affordable=offer.affordable}
  end
  function M.apply(s,owner,id,quote,growth)
    local fresh=M.quote(s,owner,id,growth)
    if fresh.tile~=quote.tile or fresh.cost~=quote.cost or not fresh.affordable then
      return nil,fresh.why or (fresh.existing and "This company already has a statue here.")
        or (fresh.affordable==false and "Not enough cash to commission a statue.")
        or "The statue plot has changed. Review the latest council offer."
    end
    local t=s.tiles[fresh.tile]
    local dirty,seen={fresh.tile},{[fresh.tile]=true}
    if t.source_house then
      local parts=assert(growth.footprint(s,t.source_house))
      for _,part in ipairs(parts) do
        local k=s.tiles[part.id]
        growth.remove(s,part.record)
        k.house,k.source_house=nil,nil
        if not seen[part.id] then dirty[#dirty+1]=part.id;seen[part.id]=true end
      end
    end
    if s.stock_farm_fields then s.stock_farm_fields[fresh.tile]=nil end
    t.wood,t.stock_clear_ground,t.stock_clear_density=nil,nil,nil
    -- Reuse the projected and protected landmark pathway. Stock makes a
    -- statue unremovable in ordinary play, including by its own company.
    t.stock_landmark={kind="statue",town=id,owner=owner}
    t.owner=owner
    local town=s.stock_town_growth.towns[id]
    town.statues=town.statues or {};town.statues[owner]=fresh.tile
    s.stock_statue_count=(s.stock_statue_count or 0)+1
    s.topology=s.topology+1
    return dirty,fresh.cost
  end
  return M
end
