-- Model-space waiting areas. Every rectangle has a walkable surface below
-- it and is outside the moving vehicle envelope. Numbers refer to the
-- shipped station OBJ geometry, not to an abstract tile center.
local mod=(core and core.get_modpath and core.get_modpath("luanttd_core")) or "mods/luanttd_core"
local Freight=dofile(mod.."/rail_freight_kinds.lua")
return function(api)
  local S,Sim=api.s,api.Sim
  local Z={}
  local function rect(tile,base,x,z,length,width,along,allow)
    local tx,tz=Sim.xy(tile)
    return {x=tx*2+.5+x,y=base,z=tz*2+.5+z,length=length,width=width,
      along=along,side={x=-along.z,z=along.x},slot_ok=allow}
  end
  local function terrain(id)
    if api.terrain then return api.terrain.tile(id) end
    return 0,S.tiles[id].h
  end
  local east={x=1,z=0}
  local dock_axis={[0]=east,[1]={x=0,z=-1},[2]={x=-1,z=0},[3]={x=0,z=1}}
  function Z.rail(id)
    local st=S.stock_rail_stations[id]
    if not st or Freight.role(st) then return end
    local out={}
    for _,tile in ipairs(st.tiles) do
      local t=S.tiles[tile]
      if t and t.rail_tracks and t.rail_station_id==id and t.owner==st.owner then
        local shape,base=terrain(tile)
        local grade,level=api.trackworks.surface(shape,base,t.rail_tracks)
        if grade==0 then
          -- Alongside the inner tactile edge, outside the roof posts,
          -- bench, lamp bases, rear railing and centerline loading gauge.
          local function allow(forward,across)
            return math.abs(forward)>.25 or math.abs(across)<.009 or across<0
          end
          if t.rail_station_axis==0 then
            out[#out+1]=rect(tile,level+.280+.5,0,.612,1.8,.19,east,allow)
          elseif t.rail_station_axis==1 then
            out[#out+1]=rect(tile,level+.280+.5,.612,0,1.8,.19,{x=0,z=-1},allow)
          end
        end
      end
    end
    return out
  end
  function Z.ship(id)
    local st=S.stock_ship_stations[id]
    local freight=S.stock_coal_ship
    if freight and (freight.mine==id or freight.power==id) then return end
    local t=st and S.tiles[st.water]
    local ref=t and t.ship
    local a=ref and dock_axis[ref.dir]
    if not (a and ref.kind=="dock" and ref.station==id and ref.water_part) then return end
    local _,level=terrain(st.water)
    -- Along the center of the level wharf, beside (not inside) the
    -- shelter, bench and bollards. The inclined land ramp is not a queue.
    return {rect(st.water,level+.673,-a.z*.08,a.x*.08,1.48,.32,a)}
  end
  function Z.air(id)
    local st=S.stock_small_airports[id]
    if not st then return end
    if st.layout=="city" then
      local t=st.origin and S.tiles[st.origin]
      if not (t and t.airfield and t.airfield.airport==id) then return end
      local _,level=terrain(st.origin)
      return {rect(st.origin,level+.526,1.665,-.09,.77,.74,east)}
    end
    local out={}
    for _,part in ipairs(st.tiles) do
      local t=S.tiles[part.id]
      if part.z==0 and part.x<2 and t and t.airfield and t.airfield.airport==id then
        local _,level=terrain(part.id)
        -- Open concourse strips in front of the waiting hall and dispatch
        -- office. End the zone before the runway/taxi lane and hangar.
        out[#out+1]=rect(part.id,level+.505,part.x==0 and -.49 or -.17,.66,part.x==0 and .62 or 1.12,.22,east)
      end
    end
    return out
  end
  return Z
end
