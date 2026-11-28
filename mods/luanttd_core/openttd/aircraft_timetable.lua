-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 timetable_cmd.cpp UpdateVehicleTimetable, and
-- linkgraph/refresh.cpp Run, RefreshLinks, RefreshStats, ordinary manual
-- station-order loop with no refits or conditionals. Explicit timetable
-- UI and automatic link-graph distribution are separate port work.
local M={TICKS_PER_SECOND=37}
local floor,ceil,max,abs=math.floor,math.ceil,math.max,math.abs
local function mul_high(a,b)
  local hi,lo=floor(a/65536),a%65536
  local hi2,lo2=floor(b/65536),b%65536
  return hi*hi2+floor((hi*lo2+lo*hi2+floor(lo*lo2/65536))/65536)
end
function M.order_list(run)
  return run.transport_orders or {{kind="station",id=run.first},{kind="station",id=run.second}}
end
function M.cursor(run,orders)
  local c=run.transport_order_cursor
  if c then return c.real+1 end
  local o=run.vehicle.order
  for i,row in ipairs(orders) do if o and row.id==o.id then return i end end
end
function M.tick(run)
  local clock=run.stock_air_timetable
  if not clock then
    clock={time=0,order_times={},links={}}
    run.stock_air_timetable=clock
  end
  clock.time=clock.time+1
end
function M.observe(run,travelling,airport)
  local clock=run.stock_air_timetable
  if not clock then return end
  local orders=M.order_list(run)
  local i=M.cursor(run,orders)
  if not i or orders[i].id~=airport or orders[i].kind~="station" then return end
  local time=clock.time
  clock.time=0
  if travelling and i==1 and not clock.started then clock.started=true;return end
  if not clock.started then return end
  local saved=clock.order_times[i]
  if not saved or saved.station~=airport then saved={station=airport};clock.order_times[i]=saved end
  -- The learned value is not an explicitly timetabled wait; it estimates
  -- full-load link capacity but never forces the aircraft to wait longer.
  local key=travelling and "travel" or "wait"
  local n=M.TICKS_PER_SECOND
  saved[key]=ceil(max(time,1)/n)*n
end
function M.duration(run,orders)
  local clock=run.stock_air_timetable
  local total=0
  for i,o in ipairs(orders) do
    local r=clock.order_times[i]
    if r and r.station==o.id then total=total+(r.travel or 0)+(r.wait or 0) end
  end
  return total
end
-- Store sampled edge refreshments under physical StationID for the
-- ordinary route. This is not a new source of cargo or a second rating.
function M.refresh_full(run,bodies,current,stations,display_speed,delay,random,at)
  local clock=run.stock_air_timetable
  if not clock or display_speed<=0 then return end
  local orders=M.order_list(run)
  local cursor=M.cursor(run,orders)
  if not cursor then return end
  local duration=M.duration(run,orders)
  local amounts={}
  for _,b in ipairs(bodies) do amounts[b.cargo]=(amounts[b.cargo] or 0)+b.capacity end
  local seen,has_cargo={},run.arrivals>0
  local function decision(i)
    for _=1,#orders do
      local o=orders[i]
      if o.kind=="station" and floor((o.nonstop or 0)/2)%2==0 then return i end
      i=i%#orders+1
    end
  end
  local f=decision(cursor)
  if not f then return end
  local i,next_=f,decision(f%#orders+1)
  while next_ and not seen[i] do
    seen[i]=true
    local a,b=orders[i],orders[next_]
    if a.load_type~=4 or has_cargo and a.unload_type~=1 and a.unload_type~=2 then
      has_cargo=true
      local from,to=stations(a.id),stations(b.id)
      if from and to and from.physical~=to.physical then
        for _,cargo in ipairs({"passenger","mail"}) do -- Temperate CargoID 0 then 2
          local quantity=amounts[cargo] or 0
          if quantity>0 then
            local least,time,increment=quantity,
              floor((abs(from.x-to.x)+abs(from.z-to.z))*4096/display_speed),false
            if from.physical==current and duration>clock.time then
              local effective=quantity*delay
              if effective>duration then least,time,increment=floor(effective/duration),0,true
              elseif mul_high(random(),duration)<effective then least,time,increment=1,0,true end
            end
            local k=from.physical..":"..to.physical..":"..cargo
            local edge=clock.links[k]
            if not edge then edge={capacity=0};clock.links[k]=edge end
            if increment then edge.capacity=edge.capacity+least
            else edge.capacity=max(edge.capacity,least);edge.estimate=time end
            edge.restricted=a.load_type==4 or nil
            edge.refreshed=at
          end
        end
      end
    else has_cargo=false end
    i,next_=next_,decision(next_%#orders+1)
  end
end
return M
