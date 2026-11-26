-- OpenTTD 16.0-RC1 water_cmd.cpp, station_cmd.cpp and waypoint_cmd.cpp:
-- ordinary wet facilities and the independent deck above must both survive.
local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Slope,Track=load("sim"),load("openttd/terrain"),load("openttd/slope"),load("openttd/rail_track")
local Basic=load("openttd/road_bridge")(Slope)
local H=load("openttd/rail_height")(Track,Slope)
local Signals=load("openttd/rail_signals")(Track)
local Q=load("openttd/rail_construction")(Track,Signals,H)
local Site=load("openttd/rail_span_site")
local Rail=load("rail_span_world")(Sim,Terrain,H,load("openttd/rail_bridge")(Basic,Q,Site),
  load("openttd/rail_tunnel")(load("openttd/road_tunnel"),Q,Site,Track),Track)
local Aqua=load("ship_aqueduct_world")(Sim,Terrain,load("openttd/aqueduct")(Basic))
local Water=load("openttd/ship_follow")(Track)
local Network=load("ship_network")(Sim,Terrain,Water,load("openttd/ship_facilities")(Track,Water))
local Works=load("ship_water_world")(Sim,Network,load("openttd/water_construction")(Track,Water))
local owner="Clearance"
Sim.W,Sim.H=64,64
local function id(x,z) return Sim.id(x,z) end
local function fresh(deck,shore)
  local s=Sim.new(1950)
  s.tiles,s.sites={},{}
  s.rail_span_enabled=true
  s.stock_generated_profile={width=64,depth=64}
  s.corner_grid=Terrain.new(64,64,function(x,z)
    local bank=math.max(0,deck-math.max(0,math.min(x-7,25-x)))
    return math.max(bank,shore and z<=20 and 1 or 0)
  end,{freeform_edges=true})
  for z=1,64 do for x=1,64 do
    local slope,base=Terrain.tile(s.corner_grid,x,z)
    local wet=x>=12 and x<=19 and (not shore or z>=21)
    s.tiles[id(x,z)]={terrain=wet and "water" or "grass",h=base,variant=1,water_class=wet and "river" or nil}
  end end
  Sim.company(s,owner).cash=2500000
  return s
end
local function project(s,mode,row,dry)
  local a,b=id(7,row),id(24,row)
  if mode=="road" then
    local ok,msg,p=Sim.road_bridge(s,owner,a,b,0,dry)
    if not ok then return nil,msg end
    return dry and p or assert(s.stock_road_bridges[s.bridge_above[id(15,row)]])
  elseif mode=="rail" then
    local p,why=Rail.quote_bridge(s,owner,a,b,0,nil,0)
    if not p or dry then return p,why end
    assert(Rail.commit(s,owner,p));return p
  else
    if dry then return Aqua.quote(s,owner,a,b) end
    return Aqua.build(s,owner,a,b)
  end
end
local function facility(s,kind,dry)
  local at=id(15,(kind=="dock" or kind=="lock") and 20 or 22)
  if kind=="lock" then
    if dry then return Works.quote_lock(s,owner,at) end
    return Works.build_lock(s,owner,at)
  end
  if dry then return Network.quote(s,owner,kind,at,0) end
  return Network.build(s,owner,kind,at,0)
end
local cases={
  {"buoy",22,1,"BUOY"}, {"depot",22,3,"SHIP_DEPOT"},
  {"dock",20,3,"DOCK"},{"dock",21,3,"DOCK"},
  {"lock",19,3,"LOCK"},{"lock",20,3,"LOCK"},{"lock",21,3,"LOCK"},
}
for _,mode in ipairs({"road","rail","water"}) do
  for _,c in ipairs(cases) do
    local kind,row,deck,reason=unpack(c)
    local at=id(15,row)
    local shore=kind=="dock" or kind=="lock"
    for extra=-1,0 do
      local height=deck+extra
      if height>=1 and (not shore or height>=2) then
        local s=fresh(height,shore)
        local original,e=facility(s,kind)
        assert(original,kind..": "..tostring(e))
        local part=assert(s.tiles[at].ship)
        local b=Network.board(s)
        local bits=Water.at(b,at)
        local cash=s.companies[owner].cash
        local plan,why=project(s,mode,row,true)
        if extra<0 then
          assert(not plan and why:find("BRIDGE_TOO_LOW_FOR_"..reason,1,true),mode.." "..kind.."/"..row..": "..tostring(why))
          assert(s.companies[owner].cash==cash and s.tiles[at].ship==part)
        else
          assert(plan and plan.deck==height,mode.." "..kind.."/"..row..": "..tostring(why))
          for _,clear in ipairs(plan.clears) do assert(clear~=at,"A valid lower layer is not cleared") end
          local p,why=project(s,mode,row)
          assert(p,why)
          assert(s.tiles[at].ship==part and b.tile(at).bridge_deck==height and Water.at(b,at)==bits)
          local api={s=s,Sim=Sim,structure_tools=true,rail_spans=Rail,
            shipyard={busy=function() return false end,reason=tostring}}
          local function clear_water(n,tile,preview)
            local sp=s.tiles[tile].ship
            if sp.kind=="lock" then return Works.remove_lock(s,n,tile,preview) end
            if sp.kind=="aqueduct" then return Aqua.remove(s,n,tile,preview) end
            return Network.remove(s,n,tile,nil,preview)
          end
          local structure=load("demolition_structures")(api,clear_water,tostring)
          local choices=load("demolition_layer_choices")(api,structure)(owner,at)
          assert(#choices==2 and choices[1].ok and choices[2].ok and choices[2].key=="harbor")
          assert(choices[2].title:find(", keep overhead bridge",1,true))
          local handled,ids,msg=choices[2].apply()
          assert(handled and ids,msg)
          assert(not s.tiles[at].ship and Sim.bridge_deck_at(s,at)==height)
        end
      end
    end
    -- CmdBuildLock uses the middle maximum for all heads when building
    -- the lock second. Its lower bank needs one extra level in this order.
    local reverse=deck+(kind=="lock" and row==21 and 1 or 0)
    for delta=-1,0 do
      local height=reverse+delta
      if height>=1 and (not shore or height>=2) then
        local s=fresh(height,shore)
        local p,why=project(s,mode,row)
        assert(p,why)
        local cash=s.companies[owner].cash
        local quote,err=facility(s,kind,true)
        if delta<0 then
          assert(not quote and err=="BRIDGE_TOO_LOW_FOR_"..reason,tostring(err))
          assert(not s.tiles[at].ship and s.companies[owner].cash==cash)
        else
          assert(quote,err)
          local built,e=facility(s,kind)
          assert(built,e)
          local part=assert(s.tiles[at].ship)
          assert(Sim.bridge_deck_at(s,at)==height)
          local b=Network.board(s)
          local bits=Water.at(b,at)
          local portal=id(7,row)
          local gone,e
          if mode=="road" then gone,e=Sim.remove_wood_bridge(s,owner,portal)
          elseif mode=="rail" then gone,e=Rail.clear(s,owner,portal)
          else gone,e=Aqua.remove(s,owner,portal) end
          assert(gone,e)
          assert(s.tiles[at].ship==part and not Sim.bridge_deck_at(s,at) and Water.at(b,at)==bits)
        end
      end
    end
  end
end
for _,mode in ipairs({"road","rail","water"}) do
  local s=fresh(2)
  local id=id(15,22)
  local t=s.tiles[id]
  t.build,t.owner,t.stock_canal,t.water_class="canal","Other",true,"canal"
  assert(project(s,mode,22))
  assert(t.build=="canal" and t.owner=="Other" and t.stock_canal and t.water_class=="canal")
end
print("PASS RC1 road, rail and aqueduct wet facility height boundaries in both construction orders; independent water, track bits, money and selective removal")
