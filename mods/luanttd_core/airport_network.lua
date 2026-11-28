-- Saved airfield facility adapter: ordinary, level, clean-ground
-- branch of CmdBuildAirport / CheckFlatLandAirport and the RC1
-- local authority rules. Shared stations and site clearing are separate.
return function(Sim,Terrain,Small,City,OilRig,Heliport,GroundRotary,Noise)
  local N={PRICE_PER_TILE=600,CLEAR_PER_TILE=30}
  local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
  local TownStations=Sim.road_station_retirement and dofile(path.."town_station_services.lua")(Sim)
  function N.layout(name)
    if name=="city" then return City end
    if name=="oilrig" then return OilRig end
    if name=="heliport" then return Heliport end
    if name==nil or name=="country" then return Small end
    return GroundRotary and GroundRotary[name]
  end
  function N.has_hangar(airport)
    local field=airport and N.layout(airport.layout)
    return field and field.hangar~=nil or false
  end
  function N.footprint(origin,name)
    local field=N.layout(name)
    if not field then return {} end
    local tiles={}
    local x,z=Sim.xy(origin)
    for dz=0,field.H-1 do for dx=0,field.W-1 do
      local id=Sim.id(x+dx,z+dz)
      if id then tiles[#tiles+1]=id end
    end end
    return tiles
  end
  -- Noise belongs to the town nearest the occupied perimeter, not
  -- necessarily the station's named town. Derive it from saved stations
  -- so construction, removal, setting changes and reload can't drift.
  local function noise_at(airport,towns,tolerance)
    if airport.layout=="oilrig" then return end
    local level=Noise.level[airport.layout or "country"]
    if not level then return end
    local x,z=Sim.xy(airport.origin)
    local cells={}
    for _,p in ipairs(airport.tiles) do
      cells[#cells+1]={x=x+p.x,z=z+p.z,local_x=p.x,local_z=p.z}
    end
    local town,d=Noise.closest(cells,airport.width,airport.height,towns)
    if town then return town.id,Noise.for_distance(level,d,tolerance),d end
  end
  local function towns(s)
    local out={}
    for _,site in ipairs(s.sites) do
      if site.kind=="town" then
        local x,z=Sim.xy(site.tile)
        out[#out+1]={id=site.id,x=x,z=z}
      end
    end
    return out
  end
  local census=setmetatable({},{__mode="k"})
  local function noise_budget(s,id,locality,tolerance)
    local town=s.sites[id]
    local limit=Noise.town_capacity(town.population or 0,Noise.population_divisor[tolerance])
    local prior=census[s]
    if not prior or prior.revision~=s.topology or prior.tolerance~=tolerance or prior.sites~=#s.sites then
      prior={revision=s.topology,tolerance=tolerance,sites=#s.sites,totals={}}
      for _,d in pairs(s.stock_small_airports or {}) do
        local at,amount=noise_at(d,locality,tolerance)
        if at then
          -- Town::noise_reached is uint16_t.
          prior.totals[at]=((prior.totals[at] or 0)+amount)%65536
        end
      end
      census[s]=prior
    end
    return prior.totals[id] or 0,limit
  end
  function N.town_noise(s,id)
    local policy=s.stock_road_town_policy or {}
    if not (Noise and policy.station_noise_level) then return end
    local t=s.sites[id]
    if not t or t.kind~="town" then return end
    local used,limit=noise_budget(s,id,towns(s),policy.tolerance or 0)
    return {used=used,limit=limit}
  end
  function N.quote(s,owner,origin,name,separate)
    local field=N.layout(name)
    if not field or name=="oilrig" then return nil,"AIRPORT_TYPE_NOT_AVAILABLE" end
    if field.intro_year and Sim.date(s)<field.intro_year then
      local reasons={heliport="HELIPORT_NOT_INTRODUCED",helidepot="HELIDEPOT_NOT_INTRODUCED",helistation="HELISTATION_NOT_INTRODUCED",
        metropolitan="METROPOLITAN_AIRPORT_NOT_INTRODUCED", commuter="COMMUTER_AIRPORT_NOT_INTRODUCED",
        international="INTERNATIONAL_AIRPORT_NOT_INTRODUCED",intercontinental="INTERCONTINENTAL_AIRPORT_NOT_INTRODUCED"}
      return nil,reasons[name] or "CITY_AIRPORT_NOT_INTRODUCED"
    end
    if not (s.corner_grid and origin and s.tiles[origin]) then return nil,"SELECT_AIRFIELD_ORIGIN" end
    local town=Sim.nearest_town(s,origin)
    local policy=s.stock_road_town_policy or {}
    local tolerance=policy.tolerance or 0
    if not Sim.road_tree_authority().new_station(s,owner,origin) then
      return nil,"AIRPORT_AUTHORITY_RATING"
    end
    local x,z=Sim.xy(origin)
    local airport={owner=owner,origin=origin,x=x*16,z=z*16,rotation=0,
      width=field.W,height=field.H,flags=0,tiles={},layout=name~="country" and name or nil,
      delta_z=field.delta_z,catchment_radius=field.catchment_radius}
    local h
    for dz=0,field.H-1 do for dx=0,field.W-1 do
      local a=Sim.id(x+dx,z+dz)
      local t=a and s.tiles[a]
      if not t then return nil,"AIRPORT_OUTSIDE_REGION",a end
      local slope,level=Terrain.tile(s.corner_grid,x+dx,z+dz)
      if slope~=0 or h and level~=h then return nil,"AIRPORT_NEEDS_LEVEL_FIELD",a end
      if t.build or t.owner or t.terrain=="water" or t.tram or t.ship or t.airfield or
          t.site or t.house or t.wood or t.stock_industry or t.stock_landmark or (Sim.rail_span_protected and Sim.rail_span_protected(s,a)) or (s.bridge_above and s.bridge_above[a]) or
          (s.aqueduct_above and s.aqueduct_above[a]) or (s.tunnel_below and s.tunnel_below[a]) then
        return nil,"AIRPORT_SITE_OCCUPIED",a
      end
      h=level
      airport.tiles[#airport.tiles+1]={id=a,x=dx,z=dz}
    end end
    if town then
      airport.town=town.id
      if Noise and policy.station_noise_level then
        local locality=towns(s)
        local at,amount,dist=noise_at(airport,locality,tolerance)
        if at then
          local used,limit=noise_budget(s,at,locality,tolerance)
          if used+amount>limit then return nil,"TOWN_REFUSES_AIRPORT_NOISE",at end
          airport.noise={town=at,name=s.sites[at].name,add=amount,used=used,limit=limit,distance=dist}
        end
      elseif tolerance~=3 then
        local count=0
        for _,d in pairs(s.stock_small_airports or {}) do
          if d.town==town.id and d.layout~="oilrig" then count=count+1 end
        end
        if count>=2 then return nil,"TOWN_REFUSES_THIRD_AIRPORT" end
      end
    end
    airport.ground=h*8
    airport.price=#airport.tiles*N.PRICE_PER_TILE
    local c=s.companies[owner]
    if (c and c.cash or 100000)<airport.price then return nil,"NOT_ENOUGH_MONEY" end
    if not separate and TownStations then
      local reuse=Sim.road_station_retirement().closest(s,"airport",owner,origin)
      airport.reopen=reuse and reuse.id or nil
    end
    return airport
  end
  local function expense(s,owner,cost)
    local c=Sim.company(s,owner)
    c.cash,c.expense,c.month_exp=c.cash-cost,c.expense+cost,c.month_exp+cost
    s.topology=s.topology+1
  end
  function N.build(s,owner,origin,name,separate)
    local airport,why,id=N.quote(s,owner,origin,name,separate)
    if not airport then return nil,why,id end
    -- The price/impact is a quote. Do not persist a stale noise budget.
    airport.noise=nil
    s.stock_small_airports=s.stock_small_airports or {}
    if airport.reopen then
      local Retired=Sim.road_station_retirement()
      local old,phase=Retired.take(s,"airport",airport.reopen)
      airport.id,airport.name,airport.stock_station_id=old.id,old.name,old.stock_station_id
      airport.town=old.town or airport.town
      airport.stock_reactivation={tick=Retired.clock(s,"airport"),phase=phase,
        load=old.time_since_load,unload=old.time_since_unload,sequence=(old.sequence or 0)+1}
      airport.reopen=nil
    else
      airport.id=s.next_small_airport or 1
      s.next_small_airport=airport.id+1
      airport.stock_station_id=Sim.stock_station_slot and Sim.stock_station_slot(s)
    end
    local exact=s.stock_engine_startup_seed~=nil
    if exact then airport.stock_random_bits=Sim.stock_random_u32(s)%65536 end
    s.stock_small_airports[airport.id]=airport
    local dirty={}
    for _,pos in ipairs(airport.tiles) do
      s.tiles[pos.id].airfield={airport=airport.id,x=pos.x,z=pos.z,layout=airport.layout,owner=owner,level=airport.ground/8}
      if exact then s.tiles[pos.id].airfield.stock_random_bits=Sim.stock_random_u32(s)%16 end
      dirty[#dirty+1]=pos.id
    end
    if exact then
      -- CmdBuildAirport calls TriggerAirportTileAnimation(Built) on
      -- every layout tile after placement; stock still draws a word.
      for _=1,#airport.tiles do Sim.stock_random_u32(s) end
    end
    expense(s,owner,airport.price)
    return airport,dirty
  end
  function N.airport_for(s,cell)
    local t=cell and s.tiles[cell]
    local ref=t and t.airfield
    return ref and s.stock_small_airports[ref.airport]
  end
  function N.remove(s,owner,cell,quote,occupied)
    local airport=N.airport_for(s,cell)
    if not airport or owner~=airport.owner then return nil,"SELECT_OWN_AIRFIELD" end
    if airport.flags~=0 or occupied and occupied(airport.id) then return nil,"AIRCRAFT_OCCUPIES_AIRFIELD" end
    local cost=#airport.tiles*N.CLEAR_PER_TILE
    local c=s.companies[owner]
    if not c or c.cash<cost then return nil,"NOT_ENOUGH_MONEY" end
    if not quote and TownStations then TownStations.retire(s,"air",airport) end
    local dirty={}
    for _,pos in ipairs(airport.tiles) do
      dirty[#dirty+1]=pos.id
      if not quote then s.tiles[pos.id].airfield=nil end
    end
    if not quote then s.stock_small_airports[airport.id]=nil;expense(s,owner,cost) end
    return dirty,cost
  end
  return N
end
