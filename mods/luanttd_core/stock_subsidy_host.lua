-- SPDX-License-Identifier: GPL-2.0-only
-- RC1 subsidy board adapter: typed stock origins and physical destination
-- catchments on the shared economy and final-delivery paths.
local Types={[0]="passenger","coal","mail","oil","livestock","goods","grain","wood","iron_ore","steel","valuables"}
local Cargo={}
for id,name in pairs(Types) do Cargo[name]=id end
local chains={coal="stock_coal_industries",timber="stock_timber_industries",oil="stock_oil_industries",
  farm="stock_farm_industries",heavy="stock_heavy_industries",bank="stock_bank_industries"}
local mixed_family={"timber","farm","oil","heavy","bank"}
local function source_key(chain,id) return chain..":"..id end

return function(Sim,Rules,House,Acceptors,Stats)
  local A={}
  function A.new()
    return {version=1,industry_slots={},industry_keys={},next_free=0,subsidies=Rules.new()}
  end

  -- Register at actual world placement and release at closure; the stock
  -- pool reuses the smallest free ID, even between two month callbacks.
  function A.register(book,chain,native)
    local key=source_key(chain,native)
    local id=book.industry_keys[key]
    if id~=nil then return id end
    id=book.next_free
    assert(book.industry_slots[id]==nil,"Subsidy industry pool cursor is not free")
    book.industry_slots[id],book.industry_keys[key]=key,id
    repeat book.next_free=book.next_free+1 until book.industry_slots[book.next_free]==nil
    return id
  end

  function A.remove(book,chain,native)
    local key=source_key(chain,native)
    local id=book.industry_keys[key]
    if id==nil then return end
    Rules.delete_source(book.subsidies,{id=id,type="industry"})
    book.industry_keys[key],book.industry_slots[id]=nil,nil
    if id<book.next_free then book.next_free=id end
    return id
  end

  -- subsidy.cpp CheckSubsidised. Use the actual station sphere of influence,
  -- not its associated town, the packet's destination, or only the industry
  -- that took this payment. A single unload can award multiple offers but
  -- the engine applies the difficulty multiplier only once.
  -- tiles is the union of the station's physical catchment tiles, zero based.
  -- neutral_industry is the shared station's own live industry key, when any.
  function A.deliver(s,book,cargo,company,packet,profit,tiles,chain,neutral_industry,emit)
    if profit==nil or not book or book.subsidies.count==0 then return profit end
    local cargo_id=Cargo[cargo]
    if cargo_id==nil or packet.source==nil then return profit end
    local kind=packet.source_type or "town"
    local src
    local function firm_by_key(wanted)
      local family,id=wanted:match("^([^:]+):(%d+)$")
      local entries=family and s[chains[family]]
      local rec=entries and entries[tonumber(id)]
      return rec and not rec.removed and rec or nil
    end
    if kind=="town" then
      local towns=s.stock_town_growth and s.stock_town_growth.towns
      if towns and towns[packet.source] then src={id=packet.source-1,type=kind} end
    elseif kind=="industry" then
      -- The existing coal and mixed transport ledgers retain chain-local
      -- native producer IDs in packets. Mixed freight already reserves
      -- noncolliding ID bands; coal can grow beyond that range on a wide
      -- world and is distinguished by its actual packet cargo.
      chain=chain or (cargo=="coal" and "coal" or cargo=="passenger" and "oil"
        or mixed_family[math.floor(packet.source/4096)])
      if not chain then return profit end
      local key=source_key(chain,packet.source)
      local id=book.industry_keys[key]
      if id~=nil and firm_by_key(key) then src={id=id,type=kind} end
    end
    if not src then return profit end

    local towns,firms
    local function coverage()
      towns,firms={},{}
      if neutral_industry and s.stock_serve_neutral_industries==false then
        if firm_by_key(neutral_industry) then firms[neutral_industry]=true end
        return
      end
      local covered=type(tiles)=="function" and tiles() or tiles
      for tile_id in pairs(covered) do
        local tile=s.tiles[tile_id+1]
        local home=tile and tile.house and tile.source_house
        if home and home.town then towns[home.town-1]=true end
        local industry=tile and tile.stock_industry
        if industry then
          local key=source_key(industry.chain or "coal",industry.id)
          if not firms[key] then
            local firm=firm_by_key(key)
            local accepted=firm and firm.accepted
            if accepted and (accepted.cargo or #accepted>0 or industry.chain==nil) and
                (s.stock_serve_neutral_industries~=false or firm.neutral_station==nil) then
              firms[key]=true
            end
          end
        end
      end
    end
    local function near(dst)
      if not towns then coverage() end
      if dst.type=="town" then return towns[dst.id]==true end
      return firms[book.industry_slots[dst.id]]==true
    end
    local duration=book.duration or 1
    if Rules.deliver(book.subsidies,cargo_id,company,src,near,duration,emit) then
      return Rules.pay(profit,book.multiplier or 2)
    end
    return profit
  end

  local function industries(s)
    local active,pick,by_site={},{},{}
    for chain,list in pairs(chains) do
      for native,firm in pairs(s[list] or {}) do
        local site=firm.site
        if site and s.sites[site] and not firm.removed then
          assert(not by_site[site],"Multiple stock industries at one site")
          local key=source_key(chain,native)
          local rec={type="industry",native=native,chain=chain,key=key,site=site,
            x=firm.x+1,z=firm.z+1,firm=firm}
          active[key],by_site[site]=rec,rec
        end
      end
    end
    -- Site insertion order before the first rollover is stock creation
    -- order, rather than the type-specific gameplay ID bands.
    for id=1,#s.sites do
      if by_site[id] then pick[#pick+1]=by_site[id] end
    end
    return active,pick
  end

  function A.board(s,book)
    local active,pick=industries(s)
    for i,key in pairs(book.industry_slots) do
      local rec=active[key]
      if not rec then
        local chain,native=key:match("^([^:]+):(%d+)$")
        A.remove(book,chain,tonumber(native))
      else rec.id=i end
    end
    for _,rec in ipairs(pick) do
      if rec.id==nil then rec.id=A.register(book,rec.chain,rec.native) end
    end

    local stocks=s.stock_town_growth
    local B={towns={},industries=pick,passengers={Cargo.passenger},by_town={},industry_by_key=active}
    for _,id in ipairs(stocks.order) do
      local town=stocks.towns[id]
      local rec={type="town",id=id-1,site=id,x=town.x,z=town.z,population=town.population,town=town}
      B.towns[#B.towns+1]=rec;B.by_town[id]=rec
    end
    table.sort(B.towns,function(a,b)return a.id<b.id end)
    table.sort(B.industries,function(a,b)return a.id<b.id end)

    local function local_houses(town,radius,fn)
      local x,z=town.x,town.z
      for v=math.max(1,z-radius),math.min(Sim.H,z+radius) do
        for u=math.max(1,x-radius),math.min(Sim.W,x+radius) do
          local tile=s.tiles[Sim.id(u,v)]
          local home=tile and tile.house and tile.source_house
          if home then fn(home) end
        end
      end
    end
    function B.valid_cargo(cargo) return Types[cargo]~=nil end
    function B.town_cargo(town,radius)
      local mail=false
      local_houses(town,radius,function(h) if House.specs[h.id][2]>0 then mail=true end end)
      return mail and {Cargo.mail} or {}
    end
    function B.town_accepts(town,cargo,radius)
      local accepts=Acceptors[Types[cargo]]
      if not accepts then return 0 end
      local total=0
      local_houses(town,radius,function(h) total=total+assert(accepts(h.id)) end)
      return total
    end
    function B.town_transported(town,cargo)
      return Stats.last_month_percent(town.town,assert(Types[cargo]))
    end
    function B.industry_accepts(ob,cargo)
      local a=ob.firm.accepted
      if not a then return false end
      local name=Types[cargo]
      if ob.chain=="coal" then return name=="coal" end
      if a.cargo then return a.cargo==name end
      for _,row in ipairs(a) do if row.cargo==name then return true end end
      return false
    end
    function B.industry_produced(ob)
      local slots=ob.firm.produced
      local valid={}
      if not slots then return valid end
      local function add(out,name)
        local cargo=Cargo[name]
        if cargo==nil then return end
        local last=assert(out.last,"Missing stock industry history")
        valid[#valid+1]={cargo=cargo,production=last.production,
          transported_pct=Rules.percent(last.transported,last.production)}
      end
      if ob.chain=="coal" then add(slots,"coal")
      elseif slots.cargo then add(slots,slots.cargo)
      else for _,p in ipairs(slots) do if p.cargo then add(p,p.cargo) end end end
      return valid
    end
    function B.source(kind,id,chain)
      if kind=="town" then return B.by_town[id] end
      if kind=="industry" and chain then return active[source_key(chain,id)] end
    end
    return B
  end
  A.types,A.cargo=Types,Cargo
  return A
end
