-- Real normal authority commands, in both RC1 construction orders.
local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Bridge=load("sim"),load("openttd/terrain"),load("openttd/bridge_underlay")
local State=load("packed_campaign")
local player="Underpass"
Sim.W,Sim.H=64,64
local function id(x,z) return Sim.id(x,z) end
local function fresh(deck)
  local s=Sim.new(1950)
  s.tiles,s.sites={},{}
  s.rail_span_enabled=true
  s.rail_paid_service,s.rail_owned_service,s.ship_paid_service=true,true,true
  s.corner_grid=Terrain.new(64,64,function(x)
    return math.max(0,deck-math.max(0,math.min(x-7,25-x)))
  end,{freeform_edges=true})
  for z=1,64 do for x=1,64 do
    local _,base=Terrain.tile(s.corner_grid,x,z)
    s.tiles[id(x,z)]={terrain="grass",h=base,variant=1}
  end end
  local r=load("campaign_authority_runtime")(Sim,m,s,{
    road={start_year=1950,breakdowns=0,service_interval=150},
    rail={ready={},engines={},split={}},air={[215]=true},ferry={[206]=true}
  })
  local a=load("campaign_authority_endpoint")(Sim,r)
  local revision=0
  local function command(c)
    c.revision=revision
    local res=a.command(player,c)
    assert(res.ok,res.why)
    revision=res.revision
    return res.value
  end
  command({kind="company_open"})
  Sim.company(s,player).cash=2500000
  local function purchase(typ,req,deny)
    local q=a[typ.."_quote"](player,req)
    if deny then
      assert(not q.ok and tostring(q.why):find(deny,1,true),tostring(q.why))
      return
    end
    assert(q.ok,q.why)
    local money=Sim.company(s,player).cash
    command({kind=typ.."_commit",token=q.value.token})
    assert(Sim.company(s,player).cash==money-q.value.cost)
  end
  return s,purchase,a,command
end
local function upper(mode,row)
  local request={mode=mode,operation="bridge",style=0,bridge_type=0,tile=id(7,row),last=id(24,row)}
  if mode=="ship" then
    request.operation,request.kind="waterwork","aqueduct"
  end
  return request
end
local function lower(kind,row)
  if kind=="depot" then return {tool="depot",first=id(15,row),direction=2} end
  if kind=="waypoint" then return {tool="waypoint",first=id(15,row)} end
  return {tool="station",first=id(15,row-1),last=id(15,row-1),axis=1,tracks=kind=="roof" and 2 or 1,
    length=3,drag=false}
end
for _,mode in ipairs({"road","rail","ship"}) do
  for _,case in ipairs({{"plain",2,"STATION"},{"roof",5,"STATION"},{"waypoint",2,"RAIL_WAYPOINT"},{"depot",3,"TRAIN_DEPOT"}}) do
    local kind,h,tag=unpack(case)
    local row=22
    local at=id(15,row)
    for bump=-1,0 do
      for side=1,2 do
        local s,issue,authority,command=fresh(h+bump)
        if kind=="waypoint" and (side==2 or bump<0) then issue("rail",{tool="track",first=at,last=at,track=1}) end
        local up=upper(mode,row)
        local down=lower(kind,row)
        if side==1 then
          issue("transport",up)
          if kind=="waypoint" and bump==0 then issue("rail",{tool="track",first=at,last=at,track=1}) end
          local message=kind=="depot" and "too low for the depot" or kind=="waypoint" and "waypoint needs two"
            or "too low for this station"
          issue("rail",down,bump<0 and message or nil)
        else
          issue("rail",down)
          issue("transport",up,bump<0 and "BRIDGE_TOO_LOW_FOR_"..tag or nil)
        end
        if bump==0 then
          assert(Sim.bridge_deck_at(s,at)==h)
          local t=s.tiles[at]
          if kind=="depot" then assert(t.rail_depot_dir==2)
          elseif kind=="waypoint" then assert(t.rail_waypoint_id)
          else assert(t.rail_station_id and t.rail_station_gfx==(kind=="roof" and 5 or 3)) end
          local again=State.decode(State.encode(s))
          assert(again.tiles[at].rail_station_gfx==t.rail_station_gfx and Sim.bridge_deck_at(again,at)==h)
          if kind=="waypoint" then
            issue("rail",{tool="waypoint",first=at,remove=true})
            assert(not s.tiles[at].rail_waypoint_id and s.tiles[at].rail_tracks==2 and Sim.bridge_deck_at(s,at)==h)
          else
            local q=assert(authority.demolition(player,at).value)
            local both={}
            for _,o in ipairs(q.options) do if o.ok then both[o.key]=true end end
            local overhead=mode=="road" and "road_bridge" or mode=="rail" and "rail_bridge" or "aqueduct"
            assert(both.rail_facility and both[overhead])
            command({kind="demolition",token=q.token,layer="rail_facility"})
            assert(not t.rail_station_gfx and not t.rail_station_id and not t.rail_depot_dir and t.rail_tracks)
            assert(Sim.bridge_deck_at(s,at)==h)
          end
        end
      end
    end
  end
end
-- Axis and footprint math follows the upstream platform-order iterator:
-- first track odd bare row, short platforms, long bare ends and both roof halves.
assert(Bridge.rail_gfx(3,1,1,0,1)==3 and Bridge.rail_gfx(3,1,0,0,0)==0)
assert(Bridge.rail_gfx(3,5,0,2,0)==2 and Bridge.rail_gfx(2,5,0,0,1)==1)
assert(Bridge.rail_gfx(2,5,0,3,1)==5 and Bridge.rail_gfx(2,5,1,3,1)==7)
assert(Bridge.rail_gfx(3,5,1,3,0)==4 and Bridge.rail_gfx(3,5,2,3,0)==6)
print("PASS RC1 station layouts and minimum clearance under road, rail and aqueduct decks; both orders, authority receipts and save round-trips")
