-- SPDX-License-Identifier: GPL-2.0-only
-- Host bridge for the OpenTTD forest/sawmill chain. Does not own a map
-- cursor, loader, running cost or station/company effect UI.
return function(Rules,Catchment)
  local R={VERSION=1}
  local function copy(v)
    if type(v)~="table" then return v end
    local r={}
    for k,x in pairs(v) do r[k]=copy(x) end
    return r
  end
  local function sorted(t)
    local a={}
    for key in pairs(t) do a[#a+1]=key end
    table.sort(a)
    return a
  end
  local function uint(v) return type(v)=="number" and v>=0 and v%1==0 end
  function R.new()
    return {version=R.VERSION,stations={},production={},months={},visited={}}
  end

  function R.bind(world,ledger,ctx)
    assert(ledger.version==R.VERSION,"Unsupported timber industry save")
    assert(uint(ctx.width) and ctx.width>0 and uint(ctx.height) and ctx.height>0)
    assert(ctx.stations and ctx.industries and ctx.xy)
    local width,height=ctx.width,ctx.height
    local industries,by_id,tiles,stations,covers={},{},{},{},{}
    for _,i in ipairs(Rules.ordered(ctx.industries)) do
      assert(not by_id[i.id],"Duplicate timber industry ID")
      by_id[i.id]=i
      industries[#industries+1]=i
      for _,p in ipairs(i.tiles) do
        if not i.removed then
          assert(p.x>=0 and p.z>=0 and p.x<width and p.z<height)
          local key=p.z*width+p.x
          assert(not tiles[key],"Overlapping stock timber industry footprint")
          tiles[key]={ind=i,tile=p}
        end
      end
    end
    for _,st in ipairs(ctx.stations) do
      if ctx.serve_neutral~=nil then st.serve_neutral=ctx.serve_neutral end
      if not stations[st.id] then
        stations[st.id]=st
        covers[st.id]=ctx.coverage and ctx.coverage[st.id] or Catchment.build(st,width,height,ctx.modified)
      else assert(stations[st.id]==st,"Conflicting native station references") end
    end
    local opts=ctx.opts or {}
    local B={industries=industries}
    function B.station(id) return stations[id] end
    function B.covered(id,x,z)
      return covers[id] and Catchment.contains(covers[id],x,z) or false
    end
    function B.report(id,cargo)
      local st=stations[id]
      if st then return Rules.acceptance(st,covers[id],cargo,industries,ctx.house_at) end
    end
    -- Call from the existing landscape loop. Replay protection is per
    -- physical tile and tick, not per-industry: multiple legit tiles of
    -- one sawmill can release separate 255-unit capped lots in a tick.
    local function visit(t,key,tick,offer_rig_passengers)
      if ledger.open_station then return 0,0,"PREVIOUS_STATION_SCAN_PENDING" end
      if ledger.station_phase_tick and ledger.station_phase_tick>=tick or
          ledger.industry_phase_tick and ledger.industry_phase_tick>=tick then
        return 0,0,"LANDSCAPE_PHASE_CLOSED"
      end
      if ledger.landscape_tick and ledger.landscape_tick>tick then return 0,0,"STALE_TILE_VISIT" end
      if ledger.landscape_tick~=tick then ledger.landscape_tick=tick;ledger.visited={} end
      if ledger.visited[key] then return 0,0,"DUPLICATE_TILE_VISIT" end
      ledger.visited[key]=true
      local o={recession=opts.recession and opts.recession(world,tick),editor=opts.editor and opts.editor(world,tick)}
      return Rules.tile_loop(t.ind,t.tile,o,function(ind,cargo,n)
        if ind.kind=="oil_rig" and cargo=="passenger" and offer_rig_passengers then return offer_rig_passengers(ind,n) end
        return Rules.distribute(ind,cargo,n,ctx.stations,covers,{
          select_goods=ctx.select_goods,town_rights=ctx.town_rights,neutral_owner=ctx.neutral_owner,
          packet_allocatable=ctx.packet_allocatable,
        })
      end)
    end

    function B.tile_visit(x,z,tick,offer_rig_passengers)
      assert(uint(tick))
      if x<0 or z<0 or x>=width or z>=height then return 0,0 end
      local key=z*width+x
      local t=tiles[key]
      if t then return visit(t,key,tick,offer_rig_passengers) end
      return 0,0
    end
    -- Bound by the owner to an exact stock cursor for this day. A
    -- present entry still runs the same ledger/order checks in visit().
    function B.landscape(width_,height_)
      if width==width_ and height==height_ then return tiles,visit end
    end

    -- Single world industry iteration, by source IndustryID, so common
    -- RNG draw order with preexisting coal remains under caller control.
    function B.produce(id,tick)
      assert(uint(tick))
      local ind=by_id[id]
      if not ind then return 0 end
      if ledger.open_station then return 0,"PREVIOUS_STATION_SCAN_PENDING" end
      if ledger.industry_phase_tick and tick<ledger.industry_phase_tick or
          ledger.landscape_tick and tick<ledger.landscape_tick or ledger.station_phase_tick and tick<ledger.station_phase_tick then
        return 0,"STALE_INDUSTRY_PHASE"
      end
      local last=ledger.production[id]
      if last and tick<=last then return 0,"DUPLICATE_OR_STALE_PRODUCTION" end
      ledger.production[id],ledger.industry_phase_tick=tick,tick
      return Rules.production_tick(ind,{editor=opts.editor and opts.editor(world,tick),
        scale=opts.scale and opts.scale(world,tick),random_u32=ctx.random_u32,ambient=ctx.ambient})
    end
    function B.month(id,ordinal,year,options)
      assert(uint(ordinal))
      local ind=by_id[id]
      if not ind then return end
      if ledger.months[id] and ledger.months[id]>=ordinal then return nil,"DUPLICATE_OR_STALE_MONTH" end
      ledger.months[id]=ordinal
      local o=copy(options or {});o.random_u32=o.random_u32 or ctx.random_u32
      return Rules.month(ind,year,o)
    end

    local function batch(id,tick)
      assert(uint(tick))
      if not stations[id] then return nil,"UNKNOWN_STATION" end
      if ledger.open_station and ledger.open_station~=id then return nil,"PREVIOUS_STATION_SCAN_PENDING" end
      local s=ledger.stations[id]
      if not s then s={};ledger.stations[id]=s end
      if s.closed and tick<=s.closed then return nil,"STALE_STATION_SCAN" end
      if s.open and s.open.tick~=tick then return nil,"PREVIOUS_STATION_SCAN_PENDING" end
      if ledger.industry_phase_tick and ledger.industry_phase_tick>=tick or
          ledger.landscape_tick and ledger.landscape_tick>tick or ledger.station_phase_tick and ledger.station_phase_tick>tick then
        return nil,"STATION_PHASE_CLOSED"
      end
      if not s.open then s.open={tick=tick,receipts={},order={},processors={}} end
      ledger.open_station,ledger.station_phase_tick=id,tick
      return s
    end
    local function key_signature(p,cargo_tile,opts_)
      return table.concat({p.cargo,tostring(p.units),tostring(p.source_type),tostring(p.source),
        tostring(p.age or 0),tostring(p.origin_station),tostring(p.origin_tile),
        tostring(p.travel_x),tostring(p.travel_z),tostring(cargo_tile),tostring(opts_.transfer),
        tostring(opts_.no_unload),tostring(opts_.distance)},":")
    end
    -- The caller supplies an actual unload pulse identity
    -- (vehicle visit/round/packet ordinal). Replay returns no payable
    -- result; return 3 is informational on an exact duplicate only.
    function B.stage(id,tick,key,packet,cargo_tile,opts_)
      opts_=opts_ or {}
      assert(type(key)=="string" and #key>0 and Rules.cargo[packet.cargo] and uint(packet.units) and packet.units>0)
      assert(uint(cargo_tile),"The wagon/truck actual cargo tile is required")
      local s,why=batch(id,tick)
      if not s then return nil,why end
      local p=s.open
      local signature=key_signature(packet,cargo_tile,opts_)
      local known=p.receipts[key]
      if known then
        if known.signature~=signature then return nil,"DELIVERY_ID_COLLISION" end
        return nil,"REPLAYED_DELIVERY",copy(known.result)
      end
      local st=stations[id]
      local acceptance=ctx.acceptance and ctx.acceptance(st,packet.cargo,tick) or B.report(id,packet.cargo)
      local result=Rules.deliver(st,acceptance,packet,function(i)return by_id[i] end,{
        cargo_tile=cargo_tile,xy=ctx.xy,
        economy_date=opts.economy_date and opts.economy_date(world,tick) or tick,
        distance=opts_.distance,current_payment=opts.current_payment and opts.current_payment(world,tick,packet.cargo),
        refuses=ctx.refuses,transfer=opts_.transfer,no_unload=opts_.no_unload,
      })
      p.order[#p.order+1]=key
      p.receipts[key]={signature=signature,result=result}
      for _,i in ipairs(result.industries) do p.processors[i.id]=true end
      return copy(result)
    end

    -- This is the end of one real Station::LoadUnloadStation scan.
    -- No goods are minted by the road callback itself, or credited to
    -- town/vehicle during processing. Returns station effects once.
    function B.finish(id,tick)
      local s=ledger.stations[id]
      if not s or not s.open then return nil,"NO_PENDING_STATION_SCAN" end
      if tick~=s.open.tick then return nil,"NOT_PENDING_STATION_SCAN" end
      local out={station=id,tick=tick,deliveries={},conversion={}}
      local open=s.open
      local processed=sorted(open.processors)
      for _,iid in ipairs(processed) do
        local ind=by_id[iid]
        if not ind or ind.removed then return nil,"PENDING_PROCESSOR_UNAVAILABLE" end
      end
      for _,key in ipairs(open.order) do
        out.deliveries[#out.deliveries+1]=copy(open.receipts[key].result)
      end
      for _,iid in ipairs(processed) do
        local made,used=Rules.trigger(by_id[iid])
        out.conversion[#out.conversion+1]={id=iid,consumed=used,produced=made}
      end
      s.closed,s.open,ledger.open_station=tick,nil,nil
      return out
    end
    return B
  end
  return R
end
