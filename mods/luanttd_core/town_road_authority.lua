-- Worker adapter for the OpenTTD road/town authority checks.
-- Uses the stock rating scale, never the older 0–100 delivery score.
return function(Sim,Stock)
  local A={}
  local CELL=16
  local function bucket(n) return math.floor(n/CELL) end
  function A.nearest(s,id)
    local best,distance
    for _,town in pairs(s.sites) do
      if town.kind=="town" then
        local current=Sim.distance(town.tile,id)
        if not distance or current<distance or (current==distance and town.id<best.id) then
          best,distance=town,current
        end
      end
    end
    return best
  end
  function A.quote(s,owner,id,wanted,journal)
    local t=A.nearest(s,id)
    if not t then return true end
    local policy=s.stock_road_town_policy or {}
    local stored=s.companies[owner].stock_town_authority_ratings or {}
    local current=journal.ratings[t.id] or stored[t.id] or Stock.initial
    local around={}
    for direction=1,4 do
      local neighbor=Sim.adjacent(id,direction)
      around[direction]=journal.road[neighbor] or (neighbor and Sim.road_bits(s,neighbor) or 0)
    end
    local changed,why=Stock.check(current,policy.tolerance or 0,policy.extra_dynamite~=false,
      Sim.road_bits(s,id),wanted,around)
    if changed==nil then return nil,why end
    journal.ratings[t.id]=changed
    return true
  end
  function A.apply(company,ratings)
    if not ratings or not next(ratings) then return end
    local ledger=company.stock_town_authority_ratings or {}
    company.stock_town_authority_ratings=ledger
    for town,rating in pairs(ratings) do ledger[town]=rating end
  end
  function A.station_view(s)
    local rows={}
    local function add(id,st,x,z,mode)
      if not (st.owner and s.companies[st.owner] and x and z) then return end
      rows[#rows+1]={owner=st.owner,x=x,z=z,time_since_load=st.time_since_load,
        time_since_unload=st.time_since_unload,mode=mode,id=id}
    end
    for id,st in pairs(s.stations) do
      if st.mode=="road" and st.town_growth_service_clock and s.tiles[st.tile] then
        local x,z=Sim.xy(st.tile)
        add(id,st,x,z,0)
      end
    end
    local commercial=s.stock_ship_commercial and s.stock_ship_commercial.service
    for id,st in pairs(commercial and commercial.stations or {}) do
      local host=st.host_mode=="rail" and s.stock_rail_stations or st.host_mode=="ship" and s.stock_ship_stations or
        st.host_mode=="air" and s.stock_small_airports
      if host and host[st.host_id] and st.sign then add(st.tick_index or id,st,st.sign.x,st.sign.y,1) end
    end
    table.sort(rows,function(a,b) if a.mode~=b.mode then return a.mode<b.mode end return a.id<b.id end)
    local index={}
    for order,row in ipairs(rows) do
      row.order=order
      local x,z=bucket(row.x),bucket(row.z)
      local column=index[x] or {}
      index[x]=column
      local cell=column[z] or {}
      column[z]=cell
      cell[#cell+1]=row
    end
    return index
  end
  function A.month(s,town,index)
    local nearby={}
    local radius=town.radii[1]
    local search=math.min(math.floor(radius/2),math.floor(math.sqrt(radius)))
    for x=bucket(town.x-search),bucket(town.x+search) do
      local column=index[x]
      if column then
        for z=bucket(town.z-search),bucket(town.z+search) do
          for _,row in ipairs(column[z] or {}) do
            if Stock.in_radius(town,row,radius) then
              local list=nearby[row.owner]
              if not list then list={};nearby[row.owner]=list end
              list[#list+1]=row
            end
          end
        end
      end
    end
    for owner,company in pairs(s.companies) do
      local old=company.stock_town_authority_ratings and company.stock_town_authority_ratings[town.id]
      if old or nearby[owner] then
        local list=nearby[owner] or {}
        if #list>1 then table.sort(list,function(a,b)return a.order<b.order end) end
        local rating=Stock.month(old or Stock.initial,list)
        A.apply(company,{[town.id]=rating})
      end
    end
  end
  return A
end
