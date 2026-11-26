-- Derive visual continuity from the complete authority board, not from
-- whichever neighboring terrain sectors currently happen to be loaded.
local M={}
local masks={4,8,16,32}
local shifts={[4]=1,[8]=4,[16]=16,[32]=64}
function M.mode(mask,bits)
  local shift=shifts[bits]
  return shift and math.floor((mask or 0)/shift)%4 or 0
end
function M.dual(mask,bits)
  local first,second
  if bits==12 then first,second=4,8 elseif bits==48 then first,second=16,32 else return end
  local a,b=M.mode(mask,first),M.mode(mask,second)
  if a+b>0 then return ("%d_%d_%d"):format(bits,a,b) end
end
function M.make(Sim,Diag,terrain)
  local function roof(s,id,t)
    local gfx=t and t.rail_station_gfx
    if not (gfx and gfx>=4 and gfx<=7 and t.rail_station_id and (t.rail_type or 0)<2) then return end
    local st=s.stock_rail_stations and s.stock_rail_stations[t.rail_station_id]
    if st and st.coal_role and (st.coal_stage_tile or st.tiles[#st.tiles])==id then return end
    return gfx
  end
  return function(s,id,t)
    if not t.rail_tracks then return end
    local gfx=roof(s,id,t)
    if gfx then
      local x,z=Sim.xy(id)
      local _,_,top=terrain.tile(id)
      local axis=gfx%2
      local dx,dz=1-axis,axis
      local canopy=0
      for i=0,1 do
        local sign=i==0 and -1 or 1
        local neighbor=Sim.id(x+dx*sign,z+dz*sign)
        local other=neighbor and s.tiles[neighbor]
        if roof(s,neighbor,other)==gfx and other.rail_station_id==t.rail_station_id and other.owner==t.owner then
          local _,_,next_top=terrain.tile(neighbor)
          if top==next_top then canopy=canopy+2^i end
        end
      end
      local sign=gfx<6 and 1 or -1
      local mate=Sim.id(x+dz*sign,z+dx*sign)
      local other=mate and s.tiles[mate]
      if roof(s,mate,other)==gfx+2*sign and other.rail_station_id==t.rail_station_id and other.owner==t.owner then
        local _,_,mate_top=terrain.tile(mate)
        if top==mate_top then canopy=canopy+4 end
      end
      return nil,canopy>0 and canopy or nil
    end
    if t.rail_station_id or t.rail_depot_dir~=nil or t.rail_waypoint_id or t.rail_span_id or t.level_crossing then return end
    local packed=0
    for _,bits in ipairs(masks) do
      if math.floor(t.rail_tracks/bits)%2==1 then
        packed=packed+shifts[bits]*Diag.mode(s,id,bits)
      end
    end
    return packed>0 and packed or nil
  end
end
return M
