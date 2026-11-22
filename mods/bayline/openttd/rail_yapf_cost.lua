-- SPDX-License-Identifier: GPL-2.0-only
-- Originally OpenTTD, copyright OpenTTD contributors; no warranty.
-- OpenTTD 14.1 CYapfCostRailT and CYapfCostBase, rail destination
-- specializations, and safe-waiting-position queries from pbs.cpp.
-- Local (non-global) segment calculation; this module never mutates the map.
return function(T,F)
local C={TILE_LENGTH=100,TILE_CORNER_LENGTH=71,DEAD_END=1,RAIL_TYPE=2,INFINITE_LOOP=4,
  SEGMENT_TOO_LONG=8,CHOICE_FOLLOWS=16,DEPOT=32,WAYPOINT=64,STATION=128,
  SAFE_TILE=256,PATH_TOO_LONG=512,FIRST_TWO_WAY_RED=1024,
  BLOCK=0,ENTRY=1,EXIT=2,COMBO=3,PBS=4,PBS_ONEWAY=5}
local POSSIBLE_TARGET=32+64+128+256
local ABORT=1+4+512+1024
local CACHED=511
local floor,min,max,abs,ceil=math.floor,math.min,math.max,math.abs,math.ceil
local band,bor,has,reverse=T.intersect,T.union,T.has,T.reverse_side
local defaults={rail_firstred_twoway_eol=true,rail_firstred_penalty=1000,
  rail_firstred_exit_penalty=10000,rail_lastred_penalty=1000,rail_lastred_exit_penalty=10000,
  rail_station_penalty=1000,rail_slope_penalty=200,rail_curve45_penalty=100,
  rail_curve90_penalty=600,rail_depot_reverse_penalty=5000,rail_crossing_penalty=300,
  rail_look_ahead_max_signals=10,rail_look_ahead_signal_p0=500,
  rail_look_ahead_signal_p1=-100,rail_look_ahead_signal_p2=5,rail_pbs_cross_penalty=300,
  rail_pbs_station_penalty=800,rail_pbs_signal_back_penalty=1500,rail_doubleslip_penalty=100,
  rail_longer_platform_penalty=800,rail_longer_platform_per_tile_penalty=0,
  rail_shorter_platform_penalty=4000,rail_shorter_platform_per_tile_penalty=0}
local function setting(s,k)
  if s and s[k]~=nil then return s[k] end
  return defaults[k]
end
local function is_pbs(typ) return typ==4 or typ==5 end
local function plain(t) return t.kind=="rail" or t.kind=="signals" end
local function railway(t) return plain(t) or t.kind=="depot" end
local function diagonal(td) return T.track(td)<2 end
local function count_at_least_two(bits)
  local n=bits
  if n==0 then return false end
  while n%2==0 do n=n/2 end
  return n~=1
end
local function first_dir(bits)
  for td=0,13 do if has(bits,td) then return td end end
end
local function signal(t,td)
  if t.kind~="signals" then return false,false,0,false end
  local along,against=T.signal_along(td),T.signal_against(td)
  local p=t.present_signals or 0
  local tr=T.track(td)
  local typ=(tr==T.LOWER or tr==T.RIGHT) and t.lower_signal_type or
    ((tr~=T.LOWER and tr~=T.RIGHT) and t.upper_signal_type or nil)
  if typ==nil then
    local pbs=(tr==T.LOWER or tr==T.RIGHT) and t.lower_pbs
      or ((tr~=T.LOWER and tr~=T.RIGHT) and t.upper_pbs)
    typ=pbs and 4 or 0
  end
  return band(p,along)~=0,band(p,against)~=0,typ,band(t.green_signals or 0,along)~=0
end
local function reserved(t)
  local bits=t.reserved_bits or 0
  if (t.kind=="station" or t.kind=="waypoint") and t.reserved then return bor(bits,2^t.axis) end
  return bits
end
local function intersects_track(bits,track)
  return has(bits,track) or T.tracks_overlap(bor(bits,2^track))
end

function C.node(parent,tile,td,choice)
  return {parent=parent,tile=tile,td=td,last_tile=tile,last_td=td,cost=0,estimate=0,
    choice=choice or (parent and parent.choice) or false,
    signals=parent and parent.signals or 0,
    last_type=parent and parent.last_type or C.PBS,
    last_red=parent and parent.last_red or false,
    last_red_type=parent and parent.last_red_type or C.BLOCK}
end

function C.one_tile(t,td,s)
  if not diagonal(td) then return C.TILE_CORNER_LENGTH end
  return C.TILE_LENGTH+(t.kind=="crossing" and setting(s,"rail_crossing_penalty") or 0)
end

function C.slope_cost(t,td,s)
  if not diagonal(td) or t.kind=="tunnel" then return 0 end
  local slope=t.slope or 0
  local uphill
  if t.kind=="bridge" then
    -- GetBridgeFoundation + HasBridgeFlatRamp: flat ground or a flat
    -- foundation means the ramp climbs on its approach; an inclined
    -- foundation or an already suitable side slope gives a flat ramp.
    if t.dir~=T.exit_side(td) then return 0 end
    local axis=t.dir%2
    local ramp_flat=slope==1 or slope==2 or slope==4 or slope==8 or slope>=16 or
      (axis==0 and (slope==12 or slope==3)) or (axis==1 and (slope==9 or slope==6))
    uphill=not ramp_flat
  else
    uphill=has(assert(T.uphill_trackdirs(slope%32),"invalid raw tile slope"),td)
  end
  return uphill and setting(s,"rail_slope_penalty") or 0
end

function C.curve_cost(td1,td2,s)
  if not (s and s.forbid_90) and has(T.crossing_trackdirs(td1),td2) then
    return setting(s,"rail_curve90_penalty")
  elseif td2~=T.next_trackdir(td1) then
    return setting(s,"rail_curve45_penalty")
  end
  return 0
end

function C.switch_cost(a,b,exit,s)
  if plain(a) and plain(b) and
      count_at_least_two(band(a.trackbits,T.trackbits(T.reachable(reverse(exit))))) and
      count_at_least_two(band(b.trackbits,T.trackbits(T.reachable(exit)))) then
    return setting(s,"rail_doubleslip_penalty")
  end
  return 0
end

function C.platform_penalty(length,platform,s)
  local missing=ceil(length/16)-platform
  if missing<0 then
    return setting(s,"rail_longer_platform_penalty")-missing*setting(s,"rail_longer_platform_per_tile_penalty")
  elseif missing>0 then
    return setting(s,"rail_shorter_platform_penalty")+missing*setting(s,"rail_shorter_platform_per_tile_penalty")
  end
  return 0
end

function C.reservation_cost(board,n,id,td,skip,s)
  if n.signals>=floor(setting(s,"rail_look_ahead_max_signals")/2) or not is_pbs(n.last_type) then return 0 end
  local t=board.tile(id)
  if t.kind=="station" then
    local k=id
    for _=0,skip do
      if board.tile(k).reserved then return setting(s,"rail_pbs_station_penalty")*(skip+1) end
      k=board.adjacent(k,reverse(T.exit_side(td)))
    end
  end
  if intersects_track(reserved(t),T.track(td)) then
    local cost=setting(s,"rail_pbs_cross_penalty")
    if not diagonal(td) then cost=floor(cost*C.TILE_CORNER_LENGTH/C.TILE_LENGTH) end
    return cost*(skip+1)
  end
  return 0
end

function C.signal_cost(board,n,id,td,s,options)
  local t=board.tile(id)
  local along,against,typ,green=signal(t,td)
  if against and not along and typ~=C.PBS then
    n.reason=bor(n.reason,C.DEAD_END)
    return 0
  end
  local cost=0
  if along then
    n.last_type=typ
    local i=n.signals
    local look=i<setting(s,"rail_look_ahead_max_signals") and
      (setting(s,"rail_look_ahead_signal_p0")+i*(setting(s,"rail_look_ahead_signal_p1")+
        i*setting(s,"rail_look_ahead_signal_p2"))) or 0
    if green then
      n.last_red=false
      if look<0 then cost=cost-look end
    else
      if not is_pbs(typ) and setting(s,"rail_firstred_twoway_eol") and
          (not options or options.treat_first_red~=false) and n.choice and against and i==0 then
        if options and options.prune then options.prune(n) end
        n.reason=bor(n.reason,C.DEAD_END)
        n.stopped_on_first_two_way=true
        return -1
      end
      n.last_red_type=typ
      n.last_red=true
      if not is_pbs(typ) and look>0 then cost=cost+look end
      if i==0 then
        if typ==C.COMBO or typ==C.EXIT then cost=cost+setting(s,"rail_firstred_exit_penalty") end
        if typ==C.BLOCK or typ==C.ENTRY then cost=cost+setting(s,"rail_firstred_penalty") end
      end
    end
    n.signals=i+1
    n.last_signal_tile,n.last_signal_td=id,td
  end
  if against and is_pbs(typ) and n.signals<setting(s,"rail_look_ahead_max_signals") then
    cost=cost+setting(s,"rail_pbs_signal_back_penalty")
  end
  return cost
end

-- pbs.cpp uses railtype compatibility (not power-specific vehicle flags)
-- for safe-position probing, then explicitly applies the no-90 policy.
local function waiting_follow(board,v,tile,td,s)
  local info=board.railtype and board.railtype(v.railtype)
  local compatible=info and info.compatible or v.compatible
  local f=F.follow(board,{owner=v.owner,compatible=compatible},tile,td)
  local eligible=band(f.trackdirs,T.reachable(f.exit))
  local next_tile=board.tile(f.tile)
  if F.disallow_90(board,board.tile(tile).railtype,next_tile and next_tile.railtype,s and s.forbid_90 or false) then
    eligible=T.remove(eligible,T.crossing_trackdirs(td))
  end
  return f,eligible
end

function C.safe_waiting(board,v,tile,td,include_line_end,s)
  local old=board.tile(tile)
  if old.kind=="depot" then return true end
  local along,_,typ=signal(old,td)
  if along and not is_pbs(typ) then return true end
  local f,eligible=waiting_follow(board,v,tile,td,s)
  if not f.ok and include_line_end or eligible==0 then return include_line_end end
  if not count_at_least_two(eligible) then
    local next_tile=board.tile(f.tile)
    if next_tile then
      local forward,back,sig=signal(next_tile,first_dir(eligible))
      if forward and is_pbs(sig) then return true end
      if back and sig==C.PBS_ONEWAY then return include_line_end end
    end
  end
  return false
end

function C.waiting_free(board,v,tile,td,s)
  local old=board.tile(tile)
  if intersects_track(reserved(old),T.track(td)) then return false end
  if old.kind=="depot" then return true end
  local along,_,typ=signal(old,td)
  if along and not is_pbs(typ) then return true end
  local f,eligible=waiting_follow(board,v,tile,td,s)
  if not f.ok then return true end
  return band(reserved(board.tile(f.tile)),T.trackbits(eligible))==0
end

-- Destination adapter: station_area(station, "station"|"waypoint")
-- returns {tile,w,h} or nil and the sign tile. xy/tile_at are stock axes.
function C.destination(board,v,order)
  local d={kind=order.kind,tile=order.tile,station=order.station,vehicle=v}
  if order.kind=="station" or order.kind=="waypoint" then
    local box,sign=board.station_area(order.station,order.kind)
    d.tile=sign
    if box and box.tile~=nil then
      local x,y=board.xy(v.tile)
      local bx,by=board.xy(box.tile)
      d.tile=board.tile_at(max(bx,min(x,bx+box.w-1)),max(by,min(y,by+box.h-1)))
    end
    d.complex_waypoint=order.kind=="waypoint" and order.complex
  elseif order.kind~="any_depot" and order.kind~="safe" and order.kind~="nearest_depot_order" then
    d.trackdirs=T.status(board.tile(d.tile))
  end
  return d
end

function C.detect(board,d,id,td,s)
  local t=board.tile(id)
  if d.kind=="station" or d.kind=="waypoint" then
    return (t.kind=="station" or t.kind=="waypoint") and t.station==d.station and t.axis==T.track(td)
  elseif d.kind=="any_depot" or d.kind=="nearest_depot_order" then
    return t.kind=="depot"
  elseif d.kind=="safe" then
    return C.safe_waiting(board,d.vehicle,id,td,true,s) and C.waiting_free(board,d.vehicle,id,td,s)
  else
    return id==d.tile and has(d.trackdirs,td)
  end
end

local dx,dy={[0]=-1,0,1,0},{[0]=0,1,0,-1}
function C.estimate(board,d,n,s)
  if d.kind=="any_depot" or d.kind=="safe" or C.detect(board,d,n.last_tile,n.last_td,s) then
    return n.cost
  end
  local x1,y1=board.xy(n.last_tile)
  local x2,y2=board.xy(d.tile)
  local side=T.exit_side(n.last_td)
  local x,y=abs(2*x1+dx[side]-2*x2),abs(2*y1+dy[side]-2*y2)
  return n.cost+min(x,y)*71+(abs(x-y)-1)*50
end

local function waypoint_occupied(board,v,id,td,s)
  local pos,remaining=id,20
  while true do
    local f=F.follow(board,v,pos,td) -- always the regular Rail follower here
    if not f.ok then break end
    pos=f.tile
    remaining=remaining-1
    if pos==id or remaining==0 or count_at_least_two(f.trackdirs) then return true end
    td=first_dir(f.trackdirs)
    if C.safe_waiting(board,v,pos,td,true,s) then break end
  end
  return not C.safe_waiting(board,v,pos,td,true,s) or not C.waiting_free(board,v,pos,td,s)
end

-- Local version of PfCalcCost. tf is the incoming follower result, including
-- skipped platform/span tiles. options.mask_reserved selects FreeRail for the
-- safe search; the upstream segment's internal iterator itself remains
-- unmasked. record optionally emits the reconstructed directional traversal.
function C.calc(board,v,d,n,tf,s,options,record)
  options=options or {}
  local parent=n.parent
  local prev,ptd=parent and parent.last_tile,parent and parent.last_td
  local cur,td=n.tile,n.td
  local segment,entry,extra=0,0,0
  local reason
  n.reason=0
  while true do
    local tile=assert(board.tile(cur))
    if prev then
      local transition=C.curve_cost(ptd,td,s)+C.switch_cost(board.tile(prev),tile,T.exit_side(ptd),s)
      if segment==0 then entry=transition else segment=segment+transition end
    end
    if record then record(cur,td,tf) end
    segment=segment+C.one_tile(tile,td,s)+100*tf.skip+C.slope_cost(tile,td,s)
    segment=segment+C.signal_cost(board,n,cur,td,s,options)
    segment=segment+C.reservation_cost(board,n,cur,td,tf.skip,s)
    reason=n.reason
    if cur==prev then
      assert(tile.kind=="depot")
      segment=segment+setting(s,"rail_depot_reverse_penalty")
    elseif tile.kind=="depot" then
      reason=bor(reason,C.DEPOT)
    elseif tile.kind=="waypoint" then
      if d.complex_waypoint and tile.station==d.station and waypoint_occupied(board,v,cur,td,s) then
        extra=extra+setting(s,"rail_lastred_penalty")
      end
      reason=bor(reason,C.WAYPOINT)
    elseif tf.station then
      segment=segment+setting(s,"rail_station_penalty")*(tf.skip+1)
      reason=bor(reason,C.STATION)
    elseif options.mask_reserved and railway(tile) then
      local yes,_,typ=signal(tile,td)
      if yes and not is_pbs(typ) then reason=bor(reason,C.SAFE_TILE) end
    end
    if n.signals<setting(s,"rail_look_ahead_max_signals") then
      local limit,min_speed=F.speed_limit(board,board.tile(tf.old_tile))
      local speed=min(v.max_speed,v.order_max_speed or 65535)
      if limit<speed then extra=extra+floor(100*(speed-limit)*(4+tf.skip)/speed) end
      if min_speed>speed then extra=extra+100*(min_speed-speed) end
    end
    if options.max_cost and options.max_cost>0 and (parent and parent.cost or 0)+entry+segment>options.max_cost then
      reason=bor(reason,C.PATH_TOO_LONG)
    end
    tf=F.follow(board,v,cur,td,s)
    if not tf.ok then
      reason=bor(reason,tf.error==F.EC_RAIL_ROAD_TYPE and C.RAIL_TYPE or C.DEAD_END)
      if options.mask_reserved then
        local yes,back,typ=signal(tile,td)
        if not (back and not yes and typ~=C.PBS) then reason=bor(reason,C.SAFE_TILE) end
      end
      break
    end
    if count_at_least_two(tf.trackdirs) then reason=bor(reason,C.CHOICE_FOLLOWS);break end
    local nxt,ntd=tf.tile,first_dir(tf.trackdirs)
    local dst=board.tile(nxt)
    if options.mask_reserved and railway(dst) then
      local along,back,typ=signal(dst,ntd)
      if along and is_pbs(typ) then
        reason=bor(reason,C.SAFE_TILE)
      elseif back and typ==C.PBS_ONEWAY then
        reason=bor(reason,C.SAFE_TILE+C.DEAD_END)
        extra=extra+setting(s,"rail_lastred_exit_penalty")
      end
    end
    if dst.railtype~=tile.railtype then reason=bor(reason,C.RAIL_TYPE);break end
    if nxt==n.tile and ntd==n.td then reason=bor(reason,C.INFINITE_LOOP);break end
    if segment>10000 and railway(dst) then reason=bor(reason,C.SEGMENT_TOO_LONG);break end
    if reason~=0 then break end
    prev,ptd=cur,td
    cur,td=nxt,ntd
  end
  if band(reason,C.PATH_TOO_LONG)~=0 then return false end
  local target=band(reason,POSSIBLE_TARGET)~=0 and C.detect(board,d,cur,td,s)
  n.segment_cost,n.reason,n.last_tile,n.last_td=segment,band(reason,CACHED),cur,td
  if not target and band(reason,ABORT)~=0 then return false end
  if target then
    n.target=true
    if n.last_red then
      if n.last_red_type==C.EXIT then extra=extra+setting(s,"rail_lastred_exit_penalty")
      elseif not is_pbs(n.last_red_type) then extra=extra+setting(s,"rail_lastred_penalty") end
    end
    if band(reason,C.STATION)~=0 then
      local length=F.platform(board,cur,reverse(T.exit_side(td)))
      extra=extra-setting(s,"rail_station_penalty")*length+C.platform_penalty(v.length,length,s)
    end
  end
  n.cost=(parent and parent.cost or 0)+entry+segment+extra
  return true
end

return C
end
