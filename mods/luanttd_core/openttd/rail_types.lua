-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, pinned 14.1: table/railtypes.h, rail_type.h,
-- rail.h/.cpp, rail_map.h, rail_cmd.cpp, elrail.cpp, train.h, train_cmd.cpp.
-- Stock facts and conversion permissions checked against 16.0-RC1
-- table/railtypes.h, rail.h and CmdConvertRail in rail_cmd.cpp.
local R={RAIL=0,ELECTRIC=1,MONO=2,MAGLEV=3,INVALID=255,
  STATION_FACTOR=1,CROSSING_FACTOR=2,SPAN_FACTOR=4,DAYS_IN_YEAR=365}
local floor,min,max=math.floor,math.min,math.max
local kinds={
  [0]={label="RAIL",powered=3,compatible=3,cost=8,maintenance=8,fallback=0,bridge=0,curves=0,acceleration=0,sort=7},
  [1]={label="ELRL",powered=2,compatible=3,cost=12,maintenance=12,fallback=0,bridge=0,curves=0,acceleration=0,sort=23,catenary=true},
  [2]={label="MONO",powered=4,compatible=4,cost=16,maintenance=16,fallback=1,bridge=16,curves=1,acceleration=1,sort=39},
  [3]={label="MGLV",powered=8,compatible=8,cost=24,maintenance=24,fallback=2,bridge=24,curves=2,acceleration=2,sort=55},
}
local function uint(n,hi) return type(n)=="number" and n%1==0 and n>=0 and n<=hi end
local function has(n,r) return floor(n/2^r)%2==1 end
local function set(n,r) return has(n,r) and n or n+2^r end
local function union(a,b)
  for r=0,3 do if has(b,r) then a=set(a,r) end end
  return a
end
local function copy(tab)
  local out={}
  for k,v in pairs(tab) do out[k]=v end
  return out
end
function R.entry(r)
  local k=kinds[r]
  if not k then return end
  local out=copy(k)
  out.railtype,out.introduces,out.max_speed=r,2^r,0
  out.no_crossings=false
  return out
end
function R.is_compatible(engine,track)
  return not not (kinds[engine] and kinds[track] and has(kinds[engine].compatible,track))
end
function R.has_power(engine,track)
  return not not (kinds[engine] and kinds[track] and has(kinds[engine].powered,track))
end
function R.available(track,available,hidden)
  return not not (kinds[track] and uint(available,15) and uint(hidden or 0,15)
    and has(available,track) and not has(hidden or 0,track))
end
function R.catenary_drawn(type_id,disable_elrails,invisible)
  local k=kinds[type_id]
  return not not (k and k.catenary and not disable_elrails and not invisible)
end
function R.flags(mask)
  if not uint(mask,15) then return end
  local a={}
  for r=0,3 do if has(mask,r) then a[r]=true end end
  return a
end
-- rail_map.h uses the low six bits of m8, not the track bitmask or owner.
-- Preserve the independent upper two map bits. 4..63 remain raw IDs;
-- no stock engine, cost, or construction rule is implied for those IDs.
function R.tile_type(m8) if uint(m8,255) then return m8%64 end end
function R.set_tile_type(m8,r) if uint(m8,255) and uint(r,63) then return m8-m8%64+r end end

-- Stock vanilla records have no date-only railtype introductions:
-- each company's non-wagon engine eligibility introduces its own type.
-- OpenTTD keeps a type that had general introduction even after models retire.
function R.engine_type(intended,disable_elrails)
  if intended==1 and disable_elrails then return 0 end
  if kinds[intended] then return intended end
end
function R.company_types(engines,company,climate,date,disable_elrails)
  if not uint(company,14) or not uint(climate,3) or not uint(date,2147483647) then return end
  local mask=0
  for _,e in ipairs(engines) do
    local r=R.engine_type(e.intended_railtype,disable_elrails)
    if r and e.kind~="wagon" and has(e.climates,climate) and
        (has(e.company_avail or 0,company) or date>=e.intro_date+R.DAYS_IN_YEAR) then
      mask=set(mask,r)
    end
  end
  return mask
end

-- SettingsDisableElrail marks existing electric vehicles permanently:
-- re-enabling restores the catalog's required railtype, not that train's
-- saved flag. ConsistChanged clears front cache, accumulates each actual
-- powered engine's original mask, then applies the legacy flag to that
-- physical unit. A flagged follower changes local power but does not
-- itself add RAIL to the head's route mask in the restored setting.
function R.flag_existing(unit,disable_elrails)
  return unit.legacy_normal==true or disable_elrails and unit.railtype==R.ELECTRIC or false
end
function R.consist(parts,disable_elrails)
  local units,route_mask={},0
  for i,p in ipairs(parts) do
    local intended=R.engine_type(p.intended_railtype,disable_elrails)
    if not intended or not uint(p.hp or 0,65535) then return nil,"INVALID_RAIL_UNIT" end
    local legacy=p.legacy_normal==true
    if not p.articulated and (p.hp or 0)>0 then route_mask=union(route_mask,kinds[intended].powered) end
    if not p.articulated and legacy and i==1 then route_mask=set(route_mask,R.RAIL) end
    units[i]={railtype=not p.articulated and legacy and R.RAIL or intended,hp=p.hp or 0,
      multiheaded=p.multiheaded==true,articulated=p.articulated==true,legacy_normal=legacy}
  end
  return {units=units,route_mask=route_mask,compatible=R.flags(route_mask)}
end
function R.unit_power(unit,track)
  if unit.articulated or not R.has_power(unit.railtype,track) then return 0 end
  return unit.multiheaded and floor(unit.hp/2) or unit.hp
end
function R.depot_accepts(kind,vehicle,track)
  if kind=="wagon" then return R.is_compatible(vehicle,track) end
  if kind=="engine" then return R.has_power(vehicle,track) end
  return false
end

-- Stock first electric through AsiaStar: raw EngineInfo/RailVehicleInfo.
-- No model is buildable from this detached catalog. The host supplies real
-- per-company preview and engine expiry events; an intro date is not an offer.
local electrics={
  [23]={name="SH '30'",image_index=20,cost_factor=26,speed=160,hp=3600,tare=84,
    running_factor=180,base_intro=16437,vehicle_life=23,model_life=30},
  [24]={name="SH '40'",image_index=20,cost_factor=30,speed=176,hp=5000,tare=82,
    running_factor=205,base_intro=19359,vehicle_life=23,model_life=80},
  [25]={name="'T.I.M.'",image_index=21,cost_factor=40,speed=240,hp=7000,tare=90,
    running_factor=240,base_intro=23376,vehicle_life=25,model_life=30,multiheaded=true},
  [26]={name="'AsiaStar'",image_index=23,cost_factor=43,speed=264,hp=8000,tare=95,
    running_factor=250,base_intro=26298,vehicle_life=25,model_life=50,multiheaded=true},
}
function R.electric_engine(id)
  if not electrics[id] then return end
  local out=copy(electrics[id])
  out.stock_id,out.intended_railtype,out.railtype,out.kind=id,1,1,"engine"
  out.climates,out.capacity,out.length,out.decay_speed,out.running_base=1,0,8,20,4800
  return out
end

-- Same authoritative prices interface as rail_construction.prices().
function R.build_cost(r,prices)
  if not kinds[r] then return end
  return floor((prices and prices.rail or 100)*kinds[r].cost/8)
end
function R.clear_cost(r,prices)
  local b=R.build_cost(r,prices)
  if b then return max(prices and prices.clear_rail or -70,0-floor(b*3/4)) end
end
function R.convert_cost(from,to,prices)
  local a,b=R.build_cost(from,prices),R.build_cost(to,prices)
  if not (a and b) then return end
  local rebuild=b+R.clear_cost(from,prices)
  if R.has_power(from,to) or R.has_power(to,from) then
    return min(floor(b/8)+max(0,b-a),rebuild)
  end
  return rebuild
end

-- CmdBuildSingleRail existing-track railtype branch, AFTER normal geometry,
-- ownership/occupancy and signal-removal checks. Its conversion applies to
-- every EXISTING track bit; the added piece is priced separately at request.
function R.add_piece_type(existing,request)
  if not R.is_compatible(existing,request) then return nil,"IMPOSSIBLE_TRACK_COMBINATION" end
  if existing~=request and not R.has_power(request,existing) then
    if not R.has_power(existing,request) then return nil,"INVALID_PARAMETER" end
    return request,true
  end
  return existing,false
end

local function count(bits)
  local n=0
  for i=0,5 do if has(bits,i) then n=n+1 end end
  return n
end
local function normal(t) return t.kind=="rail" or t.kind=="signals" end
local function span(t) return t.kind=="bridge" or t.kind=="tunnel" end
local function station(t) return t.kind=="station" or t.kind=="waypoint" end
local function convertible(t)
  if not t then return false end
  return normal(t) or t.kind=="depot" or t.kind=="crossing" or
    station(t) and t.has_station_rail~=false or span(t) and (t.transport==nil or t.transport=="rail")
end
local function type_counts(t)
  if normal(t) then
    local bits=t.trackbits
    if not uint(bits,63) or bits==0 then return end
    local n=count(bits)
    return n,(n>1 and bits~=12 and bits~=48) and n*n or n
  end
  if station(t) then return 1,t.kind=="station" and t.blocked and 0 or R.STATION_FACTOR end
  if t.kind=="crossing" then return 1,R.CROSSING_FACTOR end
  if span(t) then
    if not uint(t.length,65535) then return end
    return t.length+2,(t.length+2)*R.SPAN_FACTOR
  end
  return 1,1
end

-- Source command semantics after the host materializes the actual stock
-- TileIterator (orthogonal/diagonal, ascending or not). Ordinary company
-- only; non-rail and foreign tiles are skipped, no changes before quote.
-- t={kind,owner,railtype,trackbits?|track?,blocked?,other?,length?}
-- Optional reservations(id) returns rows {train, railtype, track}, already
-- sorted by track. Span reservations are inspected on the chosen portal.
function R.quote_convert(board,tiles,target,o)
  o=o or {}
  if not kinds[target] then return nil,"UNSUPPORTED_RAILTYPE_CONVERSION" end
  if not R.available(target,o.available,o.hidden) or type(tiles)~="table" or #tiles<1 then
    return nil,"INVALID_PARAMETER"
  end
  local selected={}
  for _,id in ipairs(tiles) do
    if not uint(id,(board.size or 2^32)-1) or selected[id] then return nil,"INVALID_PARAMETER" end
    selected[id]=true
  end
  local out={target=target,cost=0,updates={},charged={},errors={},free_reservations={},infra={[0]=0,[1]=0,[2]=0,[3]=0}}
  local err="NO_SUITABLE_RAILROAD_TRACK"
  local accepted_span={}
  for _,id in ipairs(tiles) do
    local t=board.tile(id)
    if convertible(t) and t.railtype~=target and not
        (o.disable_elrails and target==R.RAIL and t.railtype==R.ELECTRIC) then
      if t.owner~=o.owner then
        err="OWNED_BY_ANOTHER"
        out.errors[#out.errors+1]={id=id,error=err}
      elseif not kinds[t.railtype] then
        return nil,"UNSUPPORTED_RAILTYPE_CONVERSION"
      elseif not span(t) or not accepted_span[id] and not (selected[t.other] and t.other<id) then
        local price_parts,infra_parts=type_counts(t)
        if not price_parts then return nil,"INVALID_RAIL_TILE" end
        local edits={id}
        local other
        if span(t) then
          other=t.other and board.tile(t.other)
          if not other or t.other==id or not span(other) or other.kind~=t.kind or other.other~=id or
              other.railtype~=t.railtype or other.owner~=t.owner or other.length~=t.length then
            return nil,"INVALID_RAIL_SPAN"
          end
          edits[2]=t.other
        end
        local busy,why
        if not R.is_compatible(t.railtype,target) then
          if other and board.span_occupied then busy,why=board.span_occupied(id,t.other)
          elseif not other and board.tile_occupied then
            busy,why=board.tile_occupied(id,normal(t) and t.trackbits or nil)
          else busy=t.occupied or other and other.occupied end
        end
        if busy then
          err=why or "RAIL_CONVERSION_OCCUPIED"
          out.errors[#out.errors+1]={id=id,error=err}
        else
          if other then accepted_span[id],accepted_span[t.other]=true,true end
          for _,tile in ipairs(edits) do
            out.updates[#out.updates+1]={id=tile,from=t.railtype,to=target}
          end
          local cost=price_parts*R.convert_cost(t.railtype,target,o.prices)
          out.charged[#out.charged+1]={id=id,pieces=price_parts,infrastructure=infra_parts,cost=cost}
          out.cost=out.cost+cost
          out.infra[t.railtype]=out.infra[t.railtype]-infra_parts
          out.infra[target]=out.infra[target]+infra_parts
          if board.reservations then
            for _,r in ipairs(board.reservations(id) or {}) do
              local powered=R.has_power(r.railtype,target)
              if r.railtypes then
                powered=false
                for e=0,3 do
                  if has(r.railtypes,e) and R.has_power(e,target) then powered=true;break end
                end
              end
              if not powered then
                out.free_reservations[#out.free_reservations+1]={id=id,track=r.track,train=r.train}
              end
            end
          end
        end
      end
    end
  end
  if #out.charged==0 then return nil,err end
  if o.cash and out.cost>o.cash then return nil,"NOT_ENOUGH_MONEY",out.cost end
  return out
end

return R
