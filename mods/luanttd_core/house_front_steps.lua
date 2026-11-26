-- Original 3D presentation in front of approved stock single-parcel models.
-- The OpenTTD building foundation and road layout remain authoritative.
local M={}
local eligible={[0x01]=true,[0x02]=true,[0x03]=true,[0x04]=true,[0x06]=true,
  [0x0D]=true,[0x0E]=true,[0x0F]=true,[0x10]=true,[0x12]=true,[0x13]=true,
  [0x18]=true,[0x19]=true,[0x1A]=true,[0x1B]=true}
local north_or_south={[1]=true,[3]=true}
local west=4
local house_anchor_x={[1]=1,[2]=0,[3]=0,[4]=1}
local house_anchor_z={[1]=1,[2]=1,[3]=0,[4]=0}
function M.anchor(d) return 1-house_anchor_x[d],1-house_anchor_z[d] end
function M.direction(key) return (key-1)%4+1 end
local normal={{0,-1},{1,0},{0,1},{-1,0}}
function M.vertices(key)
  local d=M.direction(key)
  local dx,dz=M.anchor(d)
  local nx,nz=unpack(normal[d])
  local tx,tz=nz~=0 and 1 or 0,nx~=0 and 1 or 0
  if key>4 then tx,tz=-tx,-tz end
  return function(u,y,v)
    return {x=.5+nx*(1+v)+tx*u-dx,y=y,z=.5+nz*(1+v)+tz*u-dz}
  end
end
function M.tread(i)
  local first=-.95+(i-1)*.255
  return first,i==7 and .95 or first+.255,-1.5+i/7
end
function M.boxes(key)
  local p=M.vertices(key)
  local boxes={}
  for i=1,7 do
    local first,last,y=M.tread(i)
    local a,b=p(first,-1.5,0),p(last,y,.317)
    boxes[i]={math.min(a.x,b.x),a.y,math.min(a.z,b.z),math.max(a.x,b.x),b.y,math.max(a.z,b.z)}
  end
  return boxes
end
function M.make(frontage)
  local function busy(t)
    return t and (t.station or t.build=="road_station" or t.road_stop_pair
      or t.build=="road_depot" or t.build=="road_waypoint" or t.road_waypoint_id
      or t.tram and t.tram.kind~="road")
  end
  return function(Sim,S,id,t,deck)
    local r=t and t.house and not t.site and t.source_house
    if not (r and r.completed and not r.asset_root and eligible[r.id] and deck) then return end
    local d=frontage.road(Sim,S,id,t)
    if not d then return end
    local road_id=Sim.adjacent(id,d)
    local road=S.tiles[road_id]
    if not road or road.build~="road" or busy(road) or road.tram or road.level_crossing
      or road.road_bridge_id or road.road_tunnel_id or road.stock_void or road.water_class
      or S.bridge_above and S.bridge_above[road_id]
      or S.rail_bridge_above and S.rail_bridge_above[road_id]
      or S.aqueduct_above and S.aqueduct_above[road_id] then return end
    local bits=Sim.road_bits(S,road_id)
    if bits~=(north_or_south[d] and 10 or 5) then return end
    local slope,curb=Sim.road_surface(S,road_id)
    if slope~=0 or curb~=deck-1 then return end
    -- The foot, not the landing, is used by pedestrians approaching from
    -- the tangent road. Reserve both orientations only if both ends have
    -- platforms. This keeps the stair itself outside the waiting area.
    local first_side=north_or_south[d] and west or 1
    local id1=Sim.adjacent(road_id,first_side)
    local id2=Sim.adjacent(road_id,(first_side+1)%4+1)
    local a,b=S.tiles[id1],S.tiles[id2]
    local a_busy,b_busy=busy(a),busy(b)
    if a_busy and b_busy then return end
    return d+(a_busy and 4 or 0)
  end
end
return M
