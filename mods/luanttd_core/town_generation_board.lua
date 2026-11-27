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
local TownSpans=dofile(path.."openttd/town_spans.lua")
local RoadGrade=dofile(path.."openttd/town_road_grade.lua")
local dx,dz={[0]=-1,0,1,0},{[0]=0,1,0,-1}
local function has(bits,bit) return math.floor(bits/bit)%2~=0 end
local function difference(mask) return 15-mask%16 end

return function(Sim,Terrain,s,G,Worldgen,read,live)
  local B={}
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
        if not useful then bits=bits-b end
      end
    end
    return bits
  end
  function B.road_quote(town,x,z,bits)
    if live and not live.roadable(x,z) then return end
    return Sim.town_road_piece(s,town.id,Sim.id(x,z),bits,false)
  end
  function B.parallel_bridge(x,z,distance,facing)
    local board={width=Sim.W,height=Sim.H}
    return Worldgen.circular(board,x-1,z-1,distance,function(u,v)
      local t=B.tile(u+1,v+1)
      if not t or t.kind~="bridge" then return false end
      for _,bit in ipairs({1,2,4,8}) do
        if has(t.slope,bit) and has(facing,bit) then return true end
      end
      return false
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
    local ok,_,plan=Sim.road_tunnel(s,"town",Sim.id(x,z),true,town.id)
    return ok and plan["end"]==Sim.id(u,v) and plan or nil
  end
  function B.road_span(town,x,z,d,random)
    return Spans.bridge(town,B,x,z,d,random) or Spans.tunnel(town,B,x,z,d)
  end
  function B.terraform_land(x,z,mask,up,cost_limited)
    if mask==0 then return false end
    local price=250 -- RC1 construction base terraform price for this economy.
    local p=Terrain.plan(s.corner_grid,x,z,mask,up,{
        unit_cost=price,max_height=s.stock_generated_profile.map_height_limit,
        void=function(u,v) return s.tiles[Sim.id(u,v)].stock_void end,
        validate_tile=function(_,u,v)
          local t=B.tile(u,v)
          if not t or t.kind~="clear" or t.owner or t.bridge_above or
              live and not live.houseable(u,v) then return nil,"TOWN_PROTECTED_TERRAIN" end
          return Sim.road_site_clear_cost(s.tiles[Sim.id(u,v)])
        end,
      })
    if not p or cost_limited and p.cost>=(price+2)*8 then return false end
    assert(Terrain.apply(s.corner_grid,p))
    for _,d in ipairs(p.dirty) do
      local id=Sim.id(d.x,d.z)
      local t=s.tiles[id]
      if not t.stock_void then
        local _,base=Terrain.tile(s.corner_grid,d.x,d.z)
        t.terrain,t.h=base>0 and "hill" or "grass",base
        t.stock_clear_ground,t.stock_clear_density,t.stock_clear_visits=nil,nil,nil
      end
      if live then live.dirty(id) end
    end
    if live then live.grade_changed() end
    return true
  end
  function B.level_land(x,z)
    local cell=B.tile(x,z)
    if not cell or not cell.slope or cell.slope==0 or cell.kind=="house" then return false end
    return B.terraform_land(x,z,difference(cell.slope),true,true) or
      B.terraform_land(x,z,cell.slope%16,false,true)
  end
  return B
end
