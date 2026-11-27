-- Worker adapter for the OpenTTD road/town authority checks.
-- Uses the stock rating scale, never the older 0–100 delivery score.
return function(Sim,Stock)
  local A={}
  local path=(core and core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/"
  local Stations=dofile(path.."town_station_services.lua")(Sim)
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
    return best,distance
  end
  local town_index=setmetatable({},{__mode="k"})
  function A.invalidate_towns(s) town_index[s]=nil end
  -- ClosestTownFromTile only accepts a strict Manhattan threshold. The
  -- fixed generated town centers can be bucketed once; live industries,
  -- buildings, station admissions and road edits never move a town center.
  -- The explicit invalidation hook is for a future town editor.
  function A.nearest_in(s,id,limit)
    if limit<=0 then return end
    if not s.stock_generated_profile then
      local town,distance=A.nearest(s,id)
      if distance and distance<limit then return town,distance end
      return
    end
    local cache=town_index[s]
    if not cache or cache.sites~=s.sites or cache.w~=Sim.W or cache.h~=Sim.H then
      cache={sites=s.sites,w=Sim.W,h=Sim.H,rows={}}
      town_index[s]=cache
      for _,t in pairs(s.sites) do
        if t.kind=="town" then
          local x,z=Sim.xy(t.tile)
          local k,l=bucket(x),bucket(z)
          local row=cache.rows[l] or {};cache.rows[l]=row
          local cell=row[k] or {};row[k]=cell
          cell[#cell+1]={town=t,x=x,z=z}
        end
      end
    end
    local x,z=Sim.xy(id)
    local best,distance=nil,limit
    local r=limit-1
    for bz=bucket(z-r),bucket(z+r) do
      local row=cache.rows[bz]
      if row then
        for bx=bucket(x-r),bucket(x+r) do
          local cell=row[bx]
          if cell then
            for _,p in ipairs(cell) do
              local d=math.abs(x-p.x)+math.abs(z-p.z)
              if d<distance or d==distance and best and p.town.id<best.id then best,distance=p.town,d end
            end
          end
        end
      end
    end
    return best,best and distance or nil
  end
  function A.company_view(s,company,town)
    local policy=s.stock_road_town_policy or {}
    local ratings=company.stock_town_authority_ratings
    local rating=ratings and ratings[town.id] or Stock.initial
    local limit=policy.dist_local_authority or 20
    return {id=town.id,town=town.name,rating=rating,grade=Stock.rating_name(rating),
      new_stations=Stock.allow_new_station(rating,0,limit,policy.tolerance or 0,false),
      road_minimum=Stock.road_removal_minimum(policy.tolerance or 0),
      extra_dynamite=policy.extra_dynamite~=false}
  end
  function A.new_station(s,owner,id,no_test)
    local policy=s.stock_road_town_policy or {}
    local tolerance=policy.tolerance or 0
    if tolerance==3 or no_test then return true end
    local limit=policy.dist_local_authority or 20
    local town,distance=A.nearest_in(s,id,limit)
    local company=s.companies[owner]
    local all=company and company.stock_town_authority_ratings
    local rating=town and all and all[town.id] or Stock.initial
    if Stock.allow_new_station(rating,distance,limit,tolerance,no_test) then
      return true
    end
    return nil,"STATION_AUTHORITY_RATING",town.id
  end
  function A.tree_town(s,id)
    local policy=s.stock_road_town_policy or {}
    if policy.magic_bulldozer then return end
    local t=A.nearest_in(s,id,policy.dist_local_authority or 20)
    return t and t.id
  end
  function A.clear_road_trees(company,town)
    if not town then return end
    local ratings=company.stock_town_authority_ratings or {}
    company.stock_town_authority_ratings=ratings
    local before=ratings[town] or Stock.initial
    ratings[town]=Stock.clear_trees(before)
    return before~=ratings[town]
  end
  -- RC1 ClearTile_Water and ChangeTownRating: only an actual river
  -- demolition within the town's local authority radius is penalized.
  function A.clear_river(s,company,id)
    local policy=s.stock_road_town_policy or {}
    if policy.magic_bulldozer then return end
    local town=A.nearest_in(s,id,policy.dist_local_authority or 20)
    if not town then return end
    local ratings=company.stock_town_authority_ratings
    local before=ratings and ratings[town.id] or Stock.initial
    local after=before>-1000 and math.max(-1000,before-200) or before
    A.apply(company,{[town.id]=after})
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
  function A.span_removal(s,company,id)
    local town=A.nearest(s,id)
    if not town then return {} end
    local policy=s.stock_road_town_policy or {}
    local ratings=company.stock_town_authority_ratings or {}
    local changed,why=Stock.span_removal(ratings[town.id] or Stock.initial,
      policy.tolerance or 0,policy.magic_bulldozer)
    if not changed then return nil,why end
    return {[town.id]=changed}
  end
  function A.apply(company,ratings)
    if not ratings or not next(ratings) then return end
    local ledger=company.stock_town_authority_ratings or {}
    company.stock_town_authority_ratings=ledger
    for town,rating in pairs(ratings) do ledger[town]=rating end
  end
  function A.station_view(s,rows)
    local index={}
    for order,row in ipairs(rows or Stations.view(s,true)) do
      if row.owner and s.companies[row.owner] then
        local x,z=bucket(row.x),bucket(row.z)
        local column=index[x]
        if not column then column={};index[x]=column end
        local cell=column[z]
        if not cell then cell={};column[z]=cell end
        cell[#cell+1]={owner=row.owner,x=row.x,z=row.z,order=order,
          time_since_load=row.time_since_load,time_since_unload=row.time_since_unload}
      end
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
