-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 genworld.cpp: after Game::StartNew, run the
-- landscape's TileLoop procs before incrementing TimerGameTick, without
-- advancing calendar, economy, per-game-tick effects or vehicle timers.
return function(Sim,H,Lift)
  local M={}
  local TICKS=0x500
  function M.settle(s,growth,Farm,water,trees,random,pulse,machines)
    local profile=assert(s.stock_generated_profile)
    local clock=assert(s.passenger_house_clock)
    assert(not profile.frontage and not profile.initial_landscape and clock.counter==0,
      "The pregame landscape runs once, before live simulation")
    assert(not next(s.stations) and not next(s.fleet),"This startup pass requires a fresh world")
    assert(2^clock.log_x==Sim.W and 2^clock.log_y==Sim.H)
    local source=s.stock_town_growth.towns
    local tiles=s.tiles
    local field_rows=s.stock_farm_fields or {}
    local fields=Farm.field_board(s)
    local decorate=growth.reconstruction.decorate
    local road_before,field_before={},{}
    for id,field in pairs(field_rows) do
      if Farm.field(s,id)==field then field_before[id]=field.variant
      else field_rows[id]=nil end
    end
    local stats={start_head=clock.head,ticks=TICKS,tree_changes=0,tide_changes=0,houses=0,completed=0,
      passenger=0,mail=0,industry_machinery=0}
    local opts={percentage=s.stock_cargo_scale_percent or 100}
    if s.stock_town_lifts then
      opts.start_lift=function(_,tile) Lift.add(s.stock_town_lifts,tile+1) end
    end
    local floor,width=math.floor,Sim.W
    -- One 32-bit word per 32 cells at most; do not allocate one
    -- Lua table entry for every tile of a large ocean.
    local quiet_water,flag={},{}
    for i=0,31 do flag[i]=2^i end
    local function open_water(t)
      return t and t.terrain=="water" and t.water_class=="sea" and
        not (t.coastal_water or t.wood or t.build or t.ship or t.station or t.rail_tracks or
          t.tram or t.airfield or t.stock_industry or t.stock_landmark or t.stock_object or
          t.stock_void or t.stock_canal)
    end
    local function tide(x,z,tick,id,record)
      local cell=id-1
      local word,mask=floor(cell/32)+1,flag[cell%32]
      local quiet=quiet_water[word] or 0
      if floor(quiet/mask)%2==1 then return 0 end
      local old=s.changed and #s.changed or 0
      local changed=water(x,z,tick)
      if changed>0 then
        -- Invalidate the actual touched sea neighbors as in RC1's
        -- ClearNeighbourNonFloodingStates. The board is private until
        -- generation ends; no construction/clearing command can run.
        for i=old+1,#s.changed do
          local a,b=Sim.xy(s.changed[i])
          for dz=-1,1 do for dx=-1,1 do
            local at=Sim.id(a+dx,b+dz)
            -- Retest this small word on the next visit. Clearing
            -- a few extra bits is conservative and keeps writes cheap.
            if at then quiet_water[floor((at-1)/32)+1]=nil end
          end end
        end
      elseif x>0 and x<width-1 and z>0 and z<Sim.H-1
          and open_water(record)
          and open_water(tiles[id-width-1]) and open_water(tiles[id-width]) and open_water(tiles[id-width+1])
          and open_water(tiles[id-1]) and open_water(tiles[id+1])
          and open_water(tiles[id+width-1]) and open_water(tiles[id+width]) and open_water(tiles[id+width+1]) then
        -- A conservative subset of stock non-flooding water: open sea
        -- enclosed by open sea. This cache is never saved or used live.
        quiet_water[word]=quiet+mask
      end
      return changed
    end
    local function visit(tile,tick)
      local id=tile+1
      local t=tiles[id]
      if not t or t.stock_void then return end
      local field=field_rows[id] or s.stock_farm_grass and s.stock_farm_grass[id]
      if not (t.house or t.build=="road" or t.wood or t.terrain=="water" or
              t.stock_clear_density or field or t.stock_industry) then return end
      local x,z=tile%width,floor(tile/width)
      if t.stock_industry and machines then
        if machines.visit(id,tick) then stats.industry_machinery=stats.industry_machinery+1 end
      elseif t.house and t.source_house then
        local h=t.source_house
        local was_complete=h.completed
        if growth.advance_house(s,id,h,tick) then
          if not was_complete and h.completed then stats.completed=stats.completed+1 end
          return
        end
        if h.completed then
          stats.houses=stats.houses+1
          H.produce_tile(tile,tick,h,opts,random,function(cargo,amount)
            if amount<=0 then return end
            local town=assert(source[h.town],"Generated house must have a source town")
            local record=town.supplied[cargo] or {}
            town.supplied[cargo]=record
            -- TownGenerateCargo counts production even before the first
            -- station. Do not fabricate transported cargo or delivery.
            record.new_max=(record.new_max or 0)+amount
            stats[cargo]=stats[cargo]+amount
          end)
        end
      elseif t.build=="road" and t.road_town and not t.roadworks then
        if road_before[id]==nil then road_before[id]=t.roadside or false end
        decorate(s,x+1,z+1)
      elseif type(t.wood)=="table" then
        if t.coastal_water then stats.tide_changes=stats.tide_changes+tide(x,z,tick,id,t) end
        local old=t.wood
        local event=trees(x+1,z+1,tick)
        if event or t.wood~=old then stats.tree_changes=stats.tree_changes+1 end
      elseif t.terrain=="water" then
        if t.water_class~="river" or t.coastal_water then
          stats.tide_changes=stats.tide_changes+tide(x,z,tick,id,t)
        end
      elseif field then
        fields.visit(x,z,tick,false)
      elseif t.stock_clear_density then
        trees(x+1,z+1,tick)
      end
    end
    H.advance_initial(clock,TICKS,visit,pulse and function(tick)
      if tick%16==0 then pulse(tick,TICKS) end
    end)
    if pulse then pulse(TICKS,TICKS) end
    stats.next_head=clock.head
    profile.initial_landscape=stats
    local frontage={road=0,decorated=0,fields=0,grown=0}
    for id,before in pairs(road_before) do
      frontage.road=frontage.road+1
      if (tiles[id].roadside or false)~=before then frontage.decorated=frontage.decorated+1 end
    end
    for id,before in pairs(field_before) do
      frontage.fields=frontage.fields+1
      local r=field_rows[id]
      if r and r.variant~=before then frontage.grown=frontage.grown+1 end
    end
    profile.frontage=frontage
    return frontage,stats
  end
  return M
end
