-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors; 16.0-RC1 town_cmd.cpp IsRoadAllowedHere,
-- IsNeighbourRoadTile, LevelTownLand and GrowTownWithRoad. This board
-- is used both before site placement and on the live owner. Live
-- callbacks only clear/grade explicitly admitted map classes.
local source=debug and debug.getinfo(1,"S").source
local path=(core and core.get_modpath and core.get_modpath("luanttd_core") and core.get_modpath("luanttd_core").."/")
  or assert(source and source:sub(2):match("^(.+[\\/])"),"Cannot locate town construction adapter")
local art=dofile(path.."stock_town_art.lua")
local Road=dofile(path.."openttd/road_slope.lua")
local Slope=dofile(path.."openttd/slope.lua")
local RailTrack=dofile(path.."openttd/rail_track.lua")
local TownSpans=dofile(path.."openttd/town_spans.lua")
local RoadGrade=dofile(path.."openttd/town_road_grade.lua")
local HouseRoadTypes=dofile(path.."openttd/town_house_roadtypes.lua")
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local function has(bits,bit) return math.floor(bits/bit)%2~=0 end
local function difference(mask) return 15-mask%16 end

return function(Sim,Terrain,s,G,Worldgen,read,live)
  local policy=s.stock_road_town_policy
  local B={town_level_crossings=not policy or policy.allow_town_level_crossings~=false,
    house_roadtypes=HouseRoadTypes.on_board(Sim,s)}
  local Spans,Grade=TownSpans(G),RoadGrade(G.chance)
  function B.tile(x,z)
    local t=read(x,z)
    if not t then return end
    local id=Sim.id(x,z)
    t.bridge_above=Sim.bridge_deck_at(s,id)
    local native=s.tiles[id]
    local span=native.road_bridge_id and s.stock_road_bridges and s.stock_road_bridges[native.road_bridge_id]
      or native.road_tunnel_id and s.stock_road_tunnels and s.stock_road_tunnels[native.road_tunnel_id]
    if span then
      local head=id==span.start and span.head or span.tail
      local x2,z2=Sim.xy(id==span.start and span["end"] or span.start)
      local d=head.inside_direction
      t.kind,t.inside,t.other_x,t.other_z=native.road_bridge_id and "bridge" or "tunnel",d,x2,z2
      t.road_bits=d%2==0 and 10 or 5
    end
    return t
  end
  function B.distance_to_edge(x,z) return math.min(x-1,z-1,Sim.W-x,Sim.H-z) end
  function B.house_supported(id,x,z)
    local t=B.tile(x,z)
    return art[id]~=nil and t and t.slope and t.slope<16
  end
  function B.clear_quote(x,z,kind)
    if live and kind=="house" then return live.houseable(x,z) end
    local t=B.tile(x,z)
    if not t or t.owner or t.bridge_above then return false end
    if t.coast then return Sim.town_clear_coast(s,Sim.id(x,z),false)~=nil end
    return t.kind=="clear"
  end
  function B.seed_road_clear_quote(x,z)
    local t=B.tile(x,z)
    if not t or t.slope~=0 or t.owner or t.bridge_above or
        live and not live.roadable(x,z) then return false end
    if t.kind=="trees" then return true end
    return B.clear_quote(x,z,"road")
  end
  function B.road_allowed(town,x,z,d,random)
    local t=B.tile(x,z)
    if not t or B.distance_to_edge(x,z)<=0 or t.road_town and t.road_town~=town.id then return false end
    local axis=d%2==0 and 10 or 5
    if t.bridge_above then
      for _,l in ipairs(Sim.bridge_layers) do
        local key=s[l[1]] and s[l[1]][Sim.id(x,z)]
        local span=key and s[l[2]] and s[l[2]][key]
        if span and span.axis==d%2 then return false end
      end
    end
    -- CmdBuildRoad/clear lookahead, followed by the EXISTING foundation,
    -- not the grade of a merely prospective road.
    if (t.road_bits or 0)==0 and not Sim.town_road_piece(s,town.id,Sim.id(x,z),axis,false)
        and not B.clear_quote(x,z,"road") then return false end
    local current=t.slope
    if not current then return false end
    local policy=s.stock_road_town_policy
    if (not policy or policy.build_on_slopes~=false) and t.kind=="road" and (t.road_bits or 0)>0 then
      local foundation=Road.foundation(current,t.road_bits)
      if foundation=="invalid" then return false end
      current=Slope.foundation(current,foundation)
    end
    local ret=true
    local dist=town.layout=="original" and 1 or 2
    for pos=4,(dist+1)*4-1 do
      local side=(d+(pos%2==1 and 1 or 3))%4
      local back=math.floor(pos/2)%2==1
      local n=math.floor(pos/4)
      local u,v=x+dx[side]*n,z+dz[side]*n
      if back then u,v=u-dx[d],v-dz[d] end
      local neighbor=B.tile(u,v)
      if neighbor and has(neighbor.road_bits or 0,2^(3-(back and d or (d+2)%4))) then ret=false;break end
    end
    return Grade.allowed(current,d,ret,not live,random,B.terraform_land,x,z)
  end
  function B.clean_road_bits(_,x,z,bits)
    -- Ordinary clear/normal-road/shore classes of RC1 CleanUpRoadBits.
    for d=0,3 do
      local b=2^(3-d)
      if has(bits,b) then
        local t=B.tile(x+dx[d],z+dz[d])
        local useful=t and (t.kind=="clear" or t.kind=="road" or t.kind=="trees" or t.coast
          or (t.inside and t.inside==d))
        local mirrored=2^((3-d+2)%4)
        if t and (t.crossing or t.kind=="drive_stop") then
          useful=has(t.road_bits or 0,mirrored)
        elseif t and (t.kind=="depot" or t.kind=="bay_stop") then
          useful=t.entrance~=nil and 2^(3-t.entrance)==mirrored
        end
        -- RC1 road.cpp IsPossibleCrossing: geometrical connectivity,
        -- not affordability, occupancy or town construction policy.
        if t and t.kind=="rail" and t.plain_track==2^(1-d%2) then
          local foundation=RailTrack.foundation(t.slope,t.plain_track)
          useful=foundation~="invalid" and Slope.foundation(t.slope,foundation)==0
        end
        if not useful then bits=bits-b end
      end
    end
    return bits
  end
  function B.road_quote(town,x,z,bits)
    local t=B.tile(x,z)
    if live and not live.roadable(x,z) and not (t and (t.kind=="rail" and t.plain_track or t.company_road)) then return end
    return Sim.town_road_piece(s,town.id,Sim.id(x,z),bits,false)
  end
  function B.parallel_bridge(x,z,distance,facing)
    local board={width=Sim.W,height=Sim.H}
    -- Stock uses the radius overload with an empty rectangle (0,0).
    -- Its 2r × 2r window is not the centered diameter-r overload.
    return Worldgen.circular(board,x-1,z-1,2*distance,function(u,v)
      local t=B.tile(u+1,v+1)
      if not t or t.kind~="bridge" then return false end
      return has(t.slope,1) and has(facing,1) or has(t.slope,2) and has(facing,2)
        or has(t.slope,4) and has(facing,4) or has(t.slope,8) and has(facing,8)
    end)~=nil
  end
  function B.bridge_quote(town,x,z,u,v,style)
    local a,b=Sim.id(x,z),Sim.id(u,v)
    if live and not live.span_ends(x,z,u,v) then return end
    local ok,_,plan=Sim.road_bridge(s,"town",a,b,style,true,town.id)
    if not ok or plan.replacement then return end
    if live and not live.bridge_clears(plan.clears) then return end
    return plan
  end
  function B.tunnel_quote(town,x,z,u,v)
    if live and not live.span_ends(x,z,u,v) then return end
    local ok,_,plan=Sim.road_tunnel(s,"town",Sim.id(x,z),true,town.id,B.excavation)
    return ok and plan["end"]==Sim.id(u,v) and plan or nil
  end
  function B.road_span(town,x,z,d,random)
    return Spans.bridge(town,B,x,z,d,random) or Spans.tunnel(town,B,x,z,d)
  end
  local terraform_price=250 -- RC1 construction base terraform price for this economy.
  local function plan_earthworks(x,z,mask,up,cleared_portal)
    if mask==0 then return end
    return Terrain.plan(s.corner_grid,x,z,mask,up,{
        unit_cost=terraform_price,max_height=s.stock_generated_profile.map_height_limit,
        void=function(u,v) return s.tiles[Sim.id(u,v)].stock_void end,
        validate_tile=function(_,u,v)
          local t=B.tile(u,v)
          -- RC1's tree terraform callback delegates to LandscapeClear.
          -- Quote the stems before committing any shared corner. Leave
          -- non-tree structures and protected company land alone.
          if not t or (t.kind~="clear" and t.kind~="trees") or t.owner or t.bridge_above or
              live and not live.houseable(u,v) then return nil,"TOWN_PROTECTED_TERRAIN" end
          local id=Sim.id(u,v)
          -- A house can occupy the independent surface over a bore.
          -- Grading must still preserve its cover and remains excluded.
          if (s.tunnel_below and s.tunnel_below[id]) or (s.rail_tunnel_below and s.rail_tunnel_below[id]) then
            return nil,"TOWN_PROTECTED_TERRAIN"
          end
          -- CmdBuildTunnel already paid to clear the far portal.
          if id==cleared_portal then return 0 end
          return Sim.road_site_clear_cost(s.tiles[id],s.stock_farm_fields and s.stock_farm_fields[id])
        end,
      })
  end
  local function apply_earthworks(p,up,random)
    local height_limit=s.stock_generated_profile.map_height_limit
    -- CmdTerraformLand visits the sorted non-void tile set twice on
    -- Execute, in both world founding and live growth. The validation pass
    -- still draws; only pass 1 clears. Pure quotes never consume RNG.
    local rock={}
    assert(type(random)=="function","Town earthworks must use the simulation RNG")
    for pass=0,1 do
      for _,d in ipairs(p.dirty) do
        local id=Sim.id(d.x,d.z)
        if not s.tiles[id].stock_void then
          local _,_,top=Terrain.tile(s.corner_grid,d.x,d.z,p)
          local make_rocks=G.range(height_limit,random())<=top
          if pass==1 and not up and make_rocks then rock[id]=true end
        end
      end
    end
    assert(Terrain.apply(s.corner_grid,p))
    for _,d in ipairs(p.dirty) do
      local id=Sim.id(d.x,d.z)
      local t=s.tiles[id]
      if not t.stock_void then
        local _,base=Terrain.tile(s.corner_grid,d.x,d.z)
        t.terrain,t.h=base>0 and "hill" or "grass",base
        t.wood,t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=nil,rock[id] and 2 or nil,
          live and not rock[id] and 0 or nil,nil
        if s.stock_farm_fields and s.stock_farm_fields[id] then
          Sim.mark_clear_land(s,id)
          if s.stock_farm_grass then s.stock_farm_grass[id]=nil end
        end
      end
      if live then live.dirty(id) end
    end
    if live then live.grade_changed() end
    return true
  end
  function B.terraform_land(x,z,mask,up,cost_limited,random)
    local p=plan_earthworks(x,z,mask,up)
    if not p or cost_limited and p.cost>=(terraform_price+2)*8 then return false end
    return apply_earthworks(p,up,random)
  end
  B.excavation={
    quote=function(id,mask,expected,base)
      local x,z=Sim.xy(id)
      local p=plan_earthworks(x,z,mask,false,id)
      if not p then return end
      local actual,h=Terrain.tile(s.corner_grid,x,z,p)
      if actual==expected and h==base then return p end
    end,
    apply=function(p,random) return apply_earthworks(p,false,random) end,
  }
  function B.level_land(x,z,random)
    local cell=B.tile(x,z)
    if not cell or not cell.slope or cell.slope==0 or cell.kind=="house" then return false end
    return B.terraform_land(x,z,difference(cell.slope),true,true,random) or
      B.terraform_land(x,z,cell.slope%16,false,true,random)
  end
  return B
end
